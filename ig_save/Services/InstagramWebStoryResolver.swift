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
        let loadDelegate = StoryLoadDelegate()
        webView.navigationDelegate = loadDelegate

        var request = URLRequest(url: url)
        request.timeoutInterval = 35
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")

        let loadTask = Task {
            try await loadDelegate.waitForFinish(timeout: 24)
        }

        webView.load(request)
        try await loadTask.value
        try await Task.sleep(for: .seconds(3))

        let candidates = try await extractCandidates(from: webView)
        let uniqueCandidates = deduplicated(candidates)

        guard !uniqueCandidates.isEmpty else {
            throw MediaResolverError.noMediaFound
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
            username: storyUsername(from: url),
            contentKind: .story,
            sourceURL: url
        )
    }

    private func configuration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        #if os(iOS)
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        #endif

        return configuration
    }

    private func extractCandidates(from webView: WKWebView) async throws -> [MediaCandidate] {
        let script = """
        (() => {
          const items = [];
          const push = (url, kind, score, width, height) => {
            if (!url || typeof url !== 'string') return;
            items.push({ url, kind, score, width: width || 0, height: height || 0 });
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

        return objects.compactMap(candidate(from:))
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
