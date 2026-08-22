//
//  InstagramProfileFeedResolver.swift
//  ig_save
//

import Foundation
import WebKit

enum InstagramProfileFeedError: LocalizedError, Sendable {
    case invalidUsername
    case loginRequired
    case invalidResponse
    case noPostsFound

    var errorDescription: String? {
        switch self {
        case .invalidUsername:
            "请输入有效的 Instagram 用户名。"
        case .loginRequired:
            "获取账号内容前，请先在 App 内登录 Instagram。"
        case .invalidResponse:
            "Instagram 主页加载失败，请稍后再试。"
        case .noPostsFound:
            "没有找到可访问的帖子。请确认用户名正确，并且当前登录账号有权查看该主页。"
        }
    }
}

@MainActor
final class InstagramProfileFeedResolver: NSObject {
    func latestPosts(for rawUsername: String, limitPerKind: Int = 5) async throws -> [InstagramProfilePost] {
        guard let username = normalizedUsername(from: rawUsername) else {
            throw InstagramProfileFeedError.invalidUsername
        }

        guard await InstagramSessionStore.hasActiveSession() else {
            throw InstagramProfileFeedError.loginRequired
        }

        guard let profileURL = URL(string: "https://www.instagram.com/\(username)/") else {
            throw InstagramProfileFeedError.invalidUsername
        }

        let webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 390, height: 844),
            configuration: configuration()
        )
        let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
        webView.customUserAgent = userAgent
        let loadDelegate = ProfileLoadDelegate()
        webView.navigationDelegate = loadDelegate

        var request = URLRequest(url: profileURL)
        request.timeoutInterval = 35
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let loadTask = Task {
            try await loadDelegate.waitForFinish(timeout: 24)
        }

        webView.load(request)
        try await loadTask.value

        try await checkLoadedPage(in: webView)
        await triggerProfileFeedRequests(in: webView, username: username)

        var bestPosts: [InstagramProfilePost] = []
        var bestScore = 0
        let extractionLimit = max(30, limitPerKind * 8)

        // Instagram now hydrates profile grids asynchronously. Polling also gives its
        // authenticated GraphQL/API request enough time to finish on slower networks.
        for attempt in 0..<20 {
            if attempt > 0, attempt.isMultiple(of: 2) {
                _ = try? await evaluateJavaScript(
                    "window.scrollTo(0, Math.max(700, document.documentElement.scrollHeight, document.body.scrollHeight));",
                    in: webView
                )
            }

            try await Task.sleep(for: .seconds(attempt == 0 ? 2 : 1))
            try await checkLoadedPage(in: webView)

            let posts = try await extractPosts(from: webView, username: username, limit: extractionLimit)
            let regularPostCount = posts.lazy.filter { $0.contentKind == .post }.count
            let reelCount = posts.lazy.filter { $0.contentKind == .reel }.count
            let storyCount = posts.lazy.filter { $0.contentKind == .story }.count
            let score = min(regularPostCount, limitPerKind) +
                min(reelCount, limitPerKind) +
                min(storyCount, limitPerKind)

            if score > bestScore || (score == bestScore && posts.count > bestPosts.count) {
                let latestRegularPosts = Array(
                    posts.filter { $0.contentKind == .post }.prefix(limitPerKind)
                )
                let latestReels = Array(
                    posts.filter { $0.contentKind == .reel }.prefix(limitPerKind)
                )
                let latestStories = Array(
                    posts.filter { $0.contentKind == .story }.prefix(limitPerKind)
                )

                bestPosts = latestRegularPosts + latestReels + latestStories
                bestScore = score
            }

            let requestsFinished = await profileFeedRequestsFinished(in: webView)
            if regularPostCount >= limitPerKind,
               reelCount >= limitPerKind,
               requestsFinished {
                return bestPosts
            }
        }

        guard !bestPosts.isEmpty else {
            throw InstagramProfileFeedError.noPostsFound
        }

        return bestPosts
    }

    private func configuration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: Self.networkCaptureScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )

        return configuration
    }

    private static let networkCaptureScript = #"""
    (() => {
      if (window.__igSaveCaptureInstalled) return;
      window.__igSaveCaptureInstalled = true;
      window.__igSaveCapturedResponses = [];

      const remember = (url, body) => {
        if (typeof body !== 'string' || body.length < 2 || body.length > 5000000) return;
        const target = String(url || '');
        if (!/instagram\.com/i.test(target) && target.startsWith('http')) return;
        const entries = window.__igSaveCapturedResponses;
        entries.push({ url: target, body });
        if (entries.length > 30) entries.splice(0, entries.length - 30);
      };

      const originalFetch = window.fetch;
      if (typeof originalFetch === 'function') {
        window.fetch = function(...args) {
          return originalFetch.apply(this, args).then((response) => {
            try {
              response.clone().text().then((body) => remember(response.url, body)).catch(() => {});
            } catch (_) {}
            return response;
          });
        };
      }

      const originalOpen = XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open = function(method, url, ...rest) {
        this.__igSaveURL = String(url || '');
        this.addEventListener('load', function() {
          try {
            if (!this.responseType || this.responseType === 'text') {
              remember(this.responseURL || this.__igSaveURL, this.responseText);
            } else if (this.responseType === 'json') {
              remember(this.responseURL || this.__igSaveURL, JSON.stringify(this.response));
            }
          } catch (_) {}
        });
        return originalOpen.call(this, method, url, ...rest);
      };
    })();
    """#

    private func triggerProfileFeedRequests(in webView: WKWebView, username: String) async {
        let escapedUsername = username
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        let script = """
        (() => {
          const username = '\(escapedUsername)';
          window.__igSaveProfileFeedRequestsFinished = false;
          const headers = {
            'Accept': '*/*',
            'X-IG-App-ID': '936619743392459',
            'X-Requested-With': 'XMLHttpRequest'
          };

          const loadFeedPages = async (userID) => {
            let nextMaxID = null;
            for (let page = 0; page < 3; page += 1) {
              const query = new URLSearchParams({ count: '24' });
              if (nextMaxID) query.set('max_id', nextMaxID);
              const feedURL = `/api/v1/feed/user/${encodeURIComponent(userID)}/?${query}`;
              const feedResponse = await fetch(feedURL, { credentials: 'include', headers });
              const feedJSON = await feedResponse.clone().json();
              nextMaxID = feedJSON?.next_max_id || null;
              if (!feedJSON?.more_available || !nextMaxID) break;
            }
          };

          const loadStories = async (userID) => {
            const query = new URLSearchParams({ reel_ids: String(userID) });
            const storyURLs = [
              `/api/v1/feed/reels_media/?${query}`,
              `/api/v1/feed/user/${encodeURIComponent(userID)}/story/`
            ];
            await Promise.allSettled(
              storyURLs.map((url) => fetch(url, { credentials: 'include', headers }))
            );
          };

          const loadProfileContent = async () => {
            const profileURL = `/api/v1/users/web_profile_info/?username=${encodeURIComponent(username)}`;
            const profileResponse = await fetch(profileURL, { credentials: 'include', headers });
            const profileJSON = await profileResponse.clone().json();
            const userID = profileJSON?.data?.user?.id || profileJSON?.data?.user?.pk;
            if (!userID) return;

            await Promise.allSettled([
              loadFeedPages(userID),
              loadStories(userID)
            ]);
          };

          loadProfileContent()
            .catch(() => {})
            .finally(() => { window.__igSaveProfileFeedRequestsFinished = true; });
        })();
        """
        _ = try? await evaluateJavaScript(script, in: webView)
    }

    private func profileFeedRequestsFinished(in webView: WKWebView) async -> Bool {
        (try? await evaluateJavaScript(
            "window.__igSaveProfileFeedRequestsFinished === true",
            in: webView
        ) as? Bool) == true
    }

    private func checkLoadedPage(in webView: WKWebView) async throws {
        guard let rawURL = try await evaluateJavaScript("location.href", in: webView) as? String else {
            throw InstagramProfileFeedError.invalidResponse
        }

        let lowercasedURL = rawURL.lowercased()
        if lowercasedURL.contains("/accounts/login") {
            throw InstagramProfileFeedError.loginRequired
        }

        if lowercasedURL.contains("/challenge/") || lowercasedURL.contains("/accounts/suspended") {
            throw InstagramProfileFeedError.invalidResponse
        }
    }

    private func extractPosts(
        from webView: WKWebView,
        username: String,
        limit: Int
    ) async throws -> [InstagramProfilePost] {
        let escapedUsername = username
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        let script = """
        (() => {
          const targetUsername = '\(escapedUsername)'.toLowerCase();
          const structured = new Map();
          const visible = new Map();
          let discoveryIndex = 0;

          const normalizeURL = (value) => {
            try { return new URL(value, location.origin); } catch (_) { return null; }
          };

          const thumbnailFromNode = (node) => {
            if (typeof node.display_url === 'string') return node.display_url;
            if (typeof node.thumbnail_src === 'string') return node.thumbnail_src;
            if (typeof node.image_url === 'string') return node.image_url;
            const candidates = node.image_versions2?.candidates;
            if (Array.isArray(candidates) && candidates.length) {
              return candidates
                .filter((item) => item && typeof item.url === 'string')
                .sort((a, b) => ((b.width || 0) * (b.height || 0)) - ((a.width || 0) * (a.height || 0)))[0]?.url || null;
            }
            const resources = node.display_resources;
            if (Array.isArray(resources) && resources.length) {
              return resources
                .filter((item) => item && typeof item.src === 'string')
                .sort((a, b) => ((b.config_width || 0) * (b.config_height || 0)) - ((a.config_width || 0) * (a.config_height || 0)))[0]?.src || null;
            }
            return null;
          };

          const storyMediaFromNode = (node) => {
            const videos = node.video_versions;
            if (Array.isArray(videos) && videos.length) {
              const video = videos
                .filter((item) => item && typeof item.url === 'string')
                .sort((a, b) => ((b.width || 0) * (b.height || 0)) - ((a.width || 0) * (a.height || 0)))[0];
              if (video?.url) return { url: video.url, mediaKind: 'video' };
            }

            const image = thumbnailFromNode(node);
            return image ? { url: image, mediaKind: 'image' } : null;
          };

          const walk = (value, inheritedUsername = null, forcedKind = null) => {
            if (!value || typeof value !== 'object') return;
            if (Array.isArray(value)) {
              value.forEach((item) => walk(item, inheritedUsername, forcedKind));
              return;
            }

            const nodeUsername = value.user?.username || value.owner?.username || value.author?.username ||
              (typeof value.username === 'string' ? value.username : null) || inheritedUsername;
            const code = value.code || value.shortcode;
            const timestamp = Number(value.taken_at || value.taken_at_timestamp || value.timestamp || 0);
            const thumbnail = thumbnailFromNode(value);

            if (
              forcedKind === 'story' &&
              typeof nodeUsername === 'string' &&
              nodeUsername.toLowerCase() === targetUsername &&
              thumbnail
            ) {
              const rawStoryID = value.pk || value.id;
              const storyID = String(rawStoryID || '').split('_')[0];
              if (/^\\d+$/.test(storyID)) {
                const key = `story-${storyID}`;
                const existing = structured.get(key);
                const media = storyMediaFromNode(value);
                if (!existing || timestamp > existing.timestamp || !existing.thumbnail || (!existing.mediaURL && media?.url)) {
                  structured.set(key, {
                    code: key,
                    url: `https://www.instagram.com/stories/${targetUsername}/${storyID}/`,
                    thumbnail,
                    kind: 'story',
                    mediaURL: media?.url || null,
                    mediaKind: media?.mediaKind || null,
                    timestamp,
                    discoveryIndex: existing?.discoveryIndex ?? discoveryIndex++
                  });
                }
              }
            }

            if (
              forcedKind !== 'story' &&
              typeof code === 'string' &&
              code.length >= 5 &&
              typeof nodeUsername === 'string' &&
              nodeUsername.toLowerCase() === targetUsername
            ) {
              const productType = String(value.product_type || value.media_type || '').toLowerCase();
              const isReel = productType === 'clips' || productType === 'reels' || productType === '2';
              const kind = isReel ? 'reel' : 'post';
              const url = `https://www.instagram.com/${kind === 'reel' ? 'reel' : 'p'}/${code}/`;
              const existing = structured.get(code);
              if (!existing || timestamp > existing.timestamp || (!existing.thumbnail && thumbnail)) {
                structured.set(code, {
                  code, url, thumbnail, kind, timestamp,
                  discoveryIndex: existing?.discoveryIndex ?? discoveryIndex++
                });
              }
            }

            Object.values(value).forEach((child) => walk(child, nodeUsername, forcedKind));
          };

          document.querySelectorAll('script[type="application/json"]').forEach((element) => {
            try { walk(JSON.parse(element.textContent || '')); } catch (_) {}
          });

          const captured = Array.isArray(window.__igSaveCapturedResponses)
            ? window.__igSaveCapturedResponses
            : [];
          captured.forEach((entry) => {
            try {
              const isTargetProfileResponse =
                /web_profile_info/i.test(entry.url || '') &&
                decodeURIComponent(entry.url || '').toLowerCase().includes(targetUsername);
              const isStoryResponse =
                /\\/feed\\/reels_media\\//i.test(entry.url || '') ||
                /\\/feed\\/user\\/[^/]+\\/story\\//i.test(entry.url || '');
              walk(
                JSON.parse(entry.body || ''),
                isTargetProfileResponse ? targetUsername : null,
                isStoryResponse ? 'story' : null
              );
            } catch (_) {}
          });

          document.querySelectorAll('a[href]').forEach((anchor) => {
            const url = normalizeURL(anchor.href);
            if (!url || !/(^|\\.)instagram\\.com$/i.test(url.hostname)) return;
            const match = url.pathname.match(/^\\/(p|reel|tv)\\/([^/]+)\\/?/i);
            if (!match) return;

            const code = match[2];
            if (visible.has(code)) return;
            const image = anchor.querySelector('img');
            const thumbnail = image?.currentSrc || image?.src || null;
            visible.set(code, {
              code,
              url: `https://www.instagram.com/${match[1].toLowerCase()}/${code}/`,
              thumbnail,
              kind: match[1].toLowerCase() === 'reel' ? 'reel' : 'post',
              timestamp: 0
            });
          });

          const ordered = [...structured.values()].sort((a, b) => {
            if (a.timestamp && b.timestamp && a.timestamp !== b.timestamp) {
              return b.timestamp - a.timestamp;
            }
            if (a.timestamp !== b.timestamp) return b.timestamp - a.timestamp;
            return a.discoveryIndex - b.discoveryIndex;
          });
          const seen = new Set(ordered.map((item) => item.code));
          visible.forEach((item) => {
            if (!seen.has(item.code)) ordered.push(item);
          });

          return JSON.stringify(ordered.slice(0, \(max(1, limit))));
        })();
        """

        guard
            let jsonString = try await evaluateJavaScript(script, in: webView) as? String,
            let data = jsonString.data(using: .utf8),
            let objects = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            throw InstagramProfileFeedError.invalidResponse
        }

        return objects.compactMap(post(from:))
    }

    private func post(from object: [String: Any]) -> InstagramProfilePost? {
        guard
            let id = object["code"] as? String,
            let rawURL = object["url"] as? String,
            let url = URL(string: rawURL),
            let kindValue = object["kind"] as? String
        else {
            return nil
        }

        let contentKind: InstagramContentKind
        switch kindValue {
        case "reel":
            contentKind = .reel
        case "story":
            contentKind = .story
        default:
            contentKind = .post
        }
        let thumbnailURL = (object["thumbnail"] as? String).flatMap(URL.init(string:))
        let directMediaURL = (object["mediaURL"] as? String).flatMap(URL.init(string:))
        let mediaKind = (object["mediaKind"] as? String).flatMap(MediaKind.init(rawValue:))

        return InstagramProfilePost(
            id: id,
            url: url,
            thumbnailURL: thumbnailURL,
            contentKind: contentKind,
            directMediaURL: directMediaURL,
            mediaKind: mediaKind
        )
    }

    private func evaluateJavaScript(_ script: String, in webView: WKWebView) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: result)
                }
            }
        }
    }

    private func normalizedUsername(from rawValue: String) -> String? {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)

        if let url = URL(string: value), url.host(percentEncoded: false)?.contains("instagram.com") == true {
            value = url.pathComponents.first(where: { $0 != "/" }) ?? ""
        }

        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "@/"))

        guard
            (1...30).contains(value.count),
            value.range(of: #"^[A-Za-z0-9._]+$"#, options: .regularExpression) != nil
        else {
            return nil
        }

        return value
    }
}

@MainActor
private final class ProfileLoadDelegate: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?
    private var timeoutTask: Task<Void, Never>?

    func waitForFinish(timeout seconds: Int) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                await MainActor.run {
                    self?.resume(throwing: InstagramProfileFeedError.invalidResponse)
                }
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        resume()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        resume(throwing: error)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        resume(throwing: error)
    }

    private func resume(throwing error: Error? = nil) {
        guard let continuation else {
            return
        }

        self.continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil

        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume(returning: ())
        }
    }
}
