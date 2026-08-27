//
//  InstagramWebStoryResolver.swift
//  ig_save
//

import Foundation
import WebKit

@MainActor
final class InstagramWebStoryResolver: NSObject {
    func resolve(_ rawInput: String) async throws -> MediaResolution {
        guard let url = firstURL(in: rawInput) else {
            throw MediaResolverError.noURL
        }

        guard isStoryURL(url) else {
            throw MediaResolverError.unsupportedHost
        }

        guard await InstagramSessionStore.hasActiveSession() else {
            throw MediaResolverError.storyLoginRequired
        }

        let webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 390, height: 844),
            configuration: configuration()
        )
        let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
        webView.customUserAgent = userAgent
        let loadDelegate = StoryLoadDelegate()
        webView.navigationDelegate = loadDelegate

        var request = URLRequest(url: url)
        request.timeoutInterval = 35
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let loadTask = Task {
            try await loadDelegate.waitForFinish(timeout: 24)
        }

        webView.load(request)
        try await loadTask.value
        try await checkLoadedPage(in: webView)

        guard
            let username = storyUsername(from: url),
            let storyID = storyID(from: url)
        else {
            throw MediaResolverError.noURL
        }

        await triggerStoryRequests(in: webView, username: username)

        var uniqueCandidates: [MediaCandidate] = []
        for attempt in 0..<12 {
            try await Task.sleep(for: .seconds(attempt == 0 ? 2 : 1))
            try await checkLoadedPage(in: webView)

            let candidates = try await extractCandidates(
                from: webView,
                storyID: storyID,
                username: username
            )
            uniqueCandidates = deduplicated(candidates)

            if !uniqueCandidates.isEmpty {
                break
            }

            if await storyRequestsFinished(in: webView), attempt >= 4 {
                break
            }
        }

        guard !uniqueCandidates.isEmpty else {
            throw MediaResolverError.storyMediaUnavailable
        }

        let assets = uniqueCandidates.enumerated().map { offset, candidate in
            MediaAsset(
                sourceURL: candidate.sourceURL,
                kind: candidate.kind,
                suggestedFilename: suggestedFilename(for: candidate.sourceURL, kind: candidate.kind, index: offset + 1)
            )
        }

        return MediaResolution(
            assets: assets,
            username: username,
            contentKind: .story,
            sourceURL: url
        )
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
        #if os(iOS)
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        #endif

        return configuration
    }

    private static let networkCaptureScript = #"""
    (() => {
      if (window.__igSaveStoryCaptureInstalled) return;
      window.__igSaveStoryCaptureInstalled = true;
      window.__igSaveStoryResponses = [];

      const remember = (url, body) => {
        if (typeof body !== 'string' || body.length < 2 || body.length > 8000000) return;
        const target = String(url || '');
        if (!/instagram\.com/i.test(target) && target.startsWith('http')) return;
        const entries = window.__igSaveStoryResponses;
        entries.push({ url: target, body });
        if (entries.length > 24) entries.splice(0, entries.length - 24);
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
        this.__igSaveStoryURL = String(url || '');
        this.addEventListener('load', function() {
          try {
            if (!this.responseType || this.responseType === 'text') {
              remember(this.responseURL || this.__igSaveStoryURL, this.responseText);
            } else if (this.responseType === 'json') {
              remember(this.responseURL || this.__igSaveStoryURL, JSON.stringify(this.response));
            }
          } catch (_) {}
        });
        return originalOpen.call(this, method, url, ...rest);
      };
    })();
    """#

    private func triggerStoryRequests(in webView: WKWebView, username: String) async {
        let escapedUsername = username
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        let script = """
        (() => {
          const username = '\(escapedUsername)';
          window.__igSaveStoryRequestsFinished = false;
          const headers = {
            'Accept': '*/*',
            'X-IG-App-ID': '936619743392459',
            'X-Requested-With': 'XMLHttpRequest'
          };

          const loadStory = async () => {
            const profileResponse = await fetch(
              `/api/v1/users/web_profile_info/?username=${encodeURIComponent(username)}`,
              { credentials: 'include', headers }
            );
            const profileJSON = await profileResponse.clone().json();
            const userID = profileJSON?.data?.user?.id || profileJSON?.data?.user?.pk;
            if (!userID) return;

            const query = new URLSearchParams({ reel_ids: String(userID) });
            await Promise.allSettled([
              fetch(`/api/v1/feed/reels_media/?${query}`, { credentials: 'include', headers }),
              fetch(`/api/v1/feed/user/${encodeURIComponent(userID)}/story/`, { credentials: 'include', headers })
            ]);
          };

          loadStory()
            .catch(() => {})
            .finally(() => { window.__igSaveStoryRequestsFinished = true; });
        })();
        """
        _ = try? await evaluateJavaScript(script, in: webView)
    }

    private func storyRequestsFinished(in webView: WKWebView) async -> Bool {
        (try? await evaluateJavaScript(
            "window.__igSaveStoryRequestsFinished === true",
            in: webView
        ) as? Bool) == true
    }

    private func checkLoadedPage(in webView: WKWebView) async throws {
        guard let rawURL = try await evaluateJavaScript("location.href", in: webView) as? String else {
            throw MediaResolverError.invalidResponse
        }

        let lowercasedURL = rawURL.lowercased()
        if lowercasedURL.contains("/accounts/login") {
            throw MediaResolverError.storyLoginRequired
        }

        if lowercasedURL.contains("/challenge/") || lowercasedURL.contains("/accounts/suspended") {
            throw MediaResolverError.invalidResponse
        }
    }

    private func extractCandidates(
        from webView: WKWebView,
        storyID: String,
        username: String
    ) async throws -> [MediaCandidate] {
        let escapedStoryID = storyID
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        let escapedUsername = username
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        let script = """
        (() => {
          const targetStoryID = '\(escapedStoryID)';
          const targetUsername = '\(escapedUsername)'.toLowerCase();
          const items = [];
          const push = (url, kind, score, width, height, scoped = false) => {
            if (!url || typeof url !== 'string') return;
            items.push({ url, kind, score, width: width || 0, height: height || 0, scoped });
          };

          document.querySelectorAll('video').forEach((video) => {
            push(video.currentSrc || video.src, 'video', 120, video.videoWidth, video.videoHeight);
            video.querySelectorAll('source').forEach((source) => {
              push(source.src, 'video', 110, video.videoWidth, video.videoHeight);
            });
          });

          document.querySelectorAll('img').forEach((image) => {
            push(image.currentSrc || image.src, 'image', 90, image.naturalWidth, image.naturalHeight);
            if (image.srcset) {
              image.srcset.split(',').forEach((part) => {
                push(part.trim().split(' ')[0], 'image', 70, image.naturalWidth, image.naturalHeight);
              });
            }
          });

          document.querySelectorAll('*').forEach((element) => {
            const background = window.getComputedStyle(element).backgroundImage || '';
            const matches = [...background.matchAll(/url\\(["']?([^"')]+)["']?\\)/g)];
            matches.forEach((match) => {
              push(match[1], 'image', 45, element.clientWidth, element.clientHeight);
            });
          });

          performance.getEntriesByType('resource').forEach((entry) => {
            const url = entry.name || '';
            if (/\\.mp4(\\?|$)|video_versions|video/i.test(url)) {
              push(url, 'video', 60, 0, 0);
            } else if (/cdninstagram\\.com|fbcdn\\.net/i.test(url) && /\\.(jpg|jpeg|webp|heic)(\\?|$)/i.test(url)) {
              push(url, 'image', 35, 0, 0);
            }
          });

          const imageCandidates = (node) => {
            const candidates = node?.image_versions2?.candidates;
            if (Array.isArray(candidates) && candidates.length) {
              const best = candidates
                .filter((candidate) => candidate && typeof candidate.url === 'string')
                .sort((a, b) => ((b.width || 0) * (b.height || 0)) - ((a.width || 0) * (a.height || 0)))[0];
              push(best?.url, 'image', 900, best?.width, best?.height, true);
            } else {
              push(node?.display_url, 'image', 850, node?.original_width, node?.original_height, true);
            }
          };

          const storyMediaFromNode = (node, inheritedUsername = null) => {
            if (!node || typeof node !== 'object') return;
            const nodeUsername = node.user?.username || node.owner?.username ||
              (typeof node.username === 'string' ? node.username : null) || inheritedUsername;
            const rawID = node.pk || node.id;
            const nodeID = String(rawID || '').split('_')[0];

            if (nodeID === targetStoryID && (!nodeUsername || nodeUsername.toLowerCase() === targetUsername)) {
              const videos = node.video_versions;
              if (Array.isArray(videos) && videos.length) {
                const best = videos
                  .filter((video) => video && typeof video.url === 'string')
                  .sort((a, b) => ((b.width || 0) * (b.height || 0)) - ((a.width || 0) * (a.height || 0)))[0];
                push(best?.url, 'video', 1000, best?.width, best?.height, true);
              } else if (node.video_url) {
                push(node.video_url, 'video', 980, node.original_width, node.original_height, true);
              } else {
                imageCandidates(node);
              }
            }

            if (Array.isArray(node)) {
              node.forEach((child) => storyMediaFromNode(child, nodeUsername));
            } else {
              Object.values(node).forEach((child) => storyMediaFromNode(child, nodeUsername));
            }
          };

          const captured = Array.isArray(window.__igSaveStoryResponses)
            ? window.__igSaveStoryResponses
            : [];
          captured.forEach((entry) => {
            try { storyMediaFromNode(JSON.parse(entry.body || '')); } catch (_) {}
          });

          return JSON.stringify(items);
        })();
        """

        guard
            let jsonString = try await evaluateJavaScript(script, in: webView) as? String,
            let data = jsonString.data(using: .utf8),
            let objects = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            return []
        }

        let scopedObjects = objects.filter { ($0["scoped"] as? Bool) == true }
        return (scopedObjects.isEmpty ? objects : scopedObjects).compactMap(candidate(from:))
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

    private func candidate(from object: [String: Any]) -> MediaCandidate? {
        guard
            let rawURL = object["url"] as? String,
            let url = URL(string: rawURL),
            let kindValue = object["kind"] as? String
        else {
            return nil
        }

        let kind: MediaKind = kindValue == "video" ? .video : .image
        let width = intValue(object["width"]) ?? 0
        let height = intValue(object["height"]) ?? 0
        let score = intValue(object["score"]) ?? 0

        guard isLikelyStoryMedia(url: url, kind: kind, width: width, height: height) else {
            return nil
        }

        return MediaCandidate(sourceURL: url, kind: kind, priority: score + width * height)
    }

    private func isLikelyStoryMedia(url: URL, kind: MediaKind, width: Int, height: Int) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            return false
        }

        let urlString = url.absoluteString.lowercased()
        let host = url.host(percentEncoded: false)?.lowercased() ?? ""

        guard host.contains("cdninstagram.com") || host.contains("fbcdn.net") else {
            return false
        }

        if urlString.contains("profile_pic") ||
            urlString.contains("s150x150") ||
            urlString.contains("t51.2885-19") ||
            urlString.contains("static") {
            return false
        }

        if kind == .image, width > 0, height > 0 {
            return width >= 320 && height >= 320
        }

        return true
    }

    private func deduplicated(_ candidates: [MediaCandidate]) -> [MediaCandidate] {
        var bestByKey: [String: MediaCandidate] = [:]
        var order: [String] = []

        for candidate in candidates {
            let key = fingerprint(for: candidate)

            if let existing = bestByKey[key] {
                if candidate.priority > existing.priority {
                    bestByKey[key] = candidate
                }
            } else {
                bestByKey[key] = candidate
                order.append(key)
            }
        }

        return order.compactMap { bestByKey[$0] }
    }

    private func fingerprint(for candidate: MediaCandidate) -> String {
        var components = URLComponents(url: candidate.sourceURL, resolvingAgainstBaseURL: false)
        components?.query = nil
        components?.fragment = nil

        return "\(candidate.kind.rawValue):\(components?.url?.absoluteString.lowercased() ?? candidate.sourceURL.absoluteString.lowercased())"
    }

    private func firstURL(in text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)

        return detector?
            .matches(in: text, options: [], range: range)
            .compactMap(\.url)
            .first
    }

    private func isStoryURL(_ url: URL) -> Bool {
        let components = url.pathComponents.filter { $0 != "/" }

        return components.firstIndex(of: "stories") != nil
    }

    private func storyUsername(from url: URL) -> String? {
        let components = url.pathComponents.filter { $0 != "/" }

        guard
            let index = components.firstIndex(of: "stories"),
            components.indices.contains(index + 1)
        else {
            return nil
        }

        return components[index + 1]
    }

    private func storyID(from url: URL) -> String? {
        let components = url.pathComponents.filter { $0 != "/" }

        guard
            let index = components.firstIndex(of: "stories"),
            components.indices.contains(index + 2)
        else {
            return nil
        }

        return components[index + 2]
            .split(separator: "_")
            .first
            .map(String.init)
    }

    private func suggestedFilename(for url: URL, kind: MediaKind, index: Int) -> String {
        let originalExtension = url.pathExtension
        let fallbackExtension: String

        switch kind {
        case .image:
            fallbackExtension = "jpg"
        case .video:
            fallbackExtension = "mp4"
        case .unknown:
            fallbackExtension = "dat"
        }

        let ext = originalExtension.isEmpty ? fallbackExtension : originalExtension

        return "ig-story-\(index).\(ext)"
    }

    private func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int {
            return int
        }

        if let number = value as? NSNumber {
            return number.intValue
        }

        return nil
    }
}

@MainActor
private final class StoryLoadDelegate: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?
    private var timeoutTask: Task<Void, Never>?

    func waitForFinish(timeout seconds: Int) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                await MainActor.run {
                    self?.resume(throwing: MediaResolverError.invalidResponse)
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

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
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
