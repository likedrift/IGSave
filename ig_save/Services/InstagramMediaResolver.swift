//
//  InstagramMediaResolver.swift
//  ig_save
//

import Foundation

enum MediaResolverError: LocalizedError, Sendable {
    case noURL
    case unsupportedHost
    case invalidResponse
    case httpStatus(Int)
    case noMediaFound
    case storyLoginRequired
    case storyMediaUnavailable

    var errorDescription: String? {
        switch self {
        case .noURL:
            "没有识别到有效链接。"
        case .unsupportedHost:
            "目前只支持 Instagram 链接或直接图片/视频链接。"
        case .invalidResponse:
            "页面响应无效。"
        case let .httpStatus(statusCode):
            "Instagram 页面请求失败（HTTP \(statusCode)）。"
        case .noMediaFound:
            "没有找到可保存的媒体。请确认链接仍然有效，并且当前 Instagram 账号有查看权限。"
        case .storyLoginRequired:
            "快拍需要先在 App 内登录 Instagram。登录后会使用你自己的本地会话解析可访问的快拍媒体。"
        case .storyMediaUnavailable:
            "没有找到这条快拍。它可能已经过期、被删除，或当前 Instagram 账号没有查看权限。"
        }
    }
}

actor InstagramMediaResolver {
    private struct HTMLDocument: Sendable {
        let html: String
        let finalURL: URL
    }

    private let session: URLSession
    private let retryPolicy: NetworkRetryPolicy

    init(
        session: URLSession = .shared,
        retryPolicy: NetworkRetryPolicy = NetworkRetryPolicy()
    ) {
        self.session = session
        self.retryPolicy = retryPolicy
    }

    private enum InstagramTarget: Sendable {
        case post(shortcode: String, kind: InstagramContentKind)
        case story(username: String, id: String)
        case unknown

        var scopedToken: String? {
            switch self {
            case let .post(shortcode, _):
                shortcode
            case let .story(_, id):
                id
            case .unknown:
                nil
            }
        }

        var allowsOpenGraphFallback: Bool {
            switch self {
            case .post, .unknown:
                true
            case .story:
                false
            }
        }

        var contentKind: InstagramContentKind {
            switch self {
            case let .post(_, kind):
                kind
            case .story:
                .story
            case .unknown:
                .unknown
            }
        }

        var usernameFromPath: String? {
            switch self {
            case let .story(username, _):
                username
            case .post, .unknown:
                nil
            }
        }
    }

    func resolve(_ rawInput: String) async throws -> MediaResolution {
        guard let url = firstURL(in: rawInput) else {
            throw MediaResolverError.noURL
        }

        let directKind = MediaKind.infer(from: url)
        if directKind != .unknown {
            let asset = MediaAsset(
                sourceURL: url,
                kind: directKind,
                suggestedFilename: suggestedFilename(for: url, kind: directKind, index: 1)
            )

            return MediaResolution(
                assets: [asset],
                username: nil,
                contentKind: .direct,
                sourceURL: url
            )
        }

        guard isInstagramURL(url) else {
            throw MediaResolverError.unsupportedHost
        }

        let document = try await fetchHTML(from: url)
        let resolvedURL = isInstagramURL(document.finalURL) ? document.finalURL : url
        let target = instagramTarget(from: resolvedURL)
        let jsonObjects = applicationJSONObjects(from: document.html)
        let assets = extractMediaAssets(
            from: document.html,
            target: target,
            jsonObjects: jsonObjects
        )

        guard !assets.isEmpty else {
            throw MediaResolverError.noMediaFound
        }

        return MediaResolution(
            assets: assets,
            username: username(from: document.html, target: target, jsonObjects: jsonObjects),
            contentKind: target.contentKind,
            sourceURL: resolvedURL
        )
    }

    private func firstURL(in text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)

        return detector?
            .matches(in: text, options: [], range: range)
            .compactMap(\.url)
            .first
    }

    private func isInstagramURL(_ url: URL) -> Bool {
        guard let host = url.host(percentEncoded: false)?.lowercased() else {
            return false
        }

        return host == "instagram.com" || host == "www.instagram.com" || host.hasSuffix(".instagram.com")
    }

    private func instagramTarget(from url: URL) -> InstagramTarget {
        let components = url.pathComponents.filter { $0 != "/" }

        for prefix in ["p", "reel", "tv"] {
            guard
                let index = components.firstIndex(of: prefix),
                components.indices.contains(index + 1)
            else {
                continue
            }

            let kind: InstagramContentKind = prefix == "reel" ? .reel : .post

            return .post(shortcode: components[index + 1], kind: kind)
        }

        if
            let index = components.firstIndex(of: "stories"),
            components.indices.contains(index + 2)
        {
            return .story(username: components[index + 1], id: components[index + 2])
        }

        return .unknown
    }

    private func fetchHTML(from url: URL) async throws -> HTMLDocument {
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("https://www.instagram.com/", forHTTPHeaderField: "Referer")

        if let cookieHeader = await InstagramSessionStore.cookieHeader(for: url) {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }

        for attempt in 1...retryPolicy.maximumAttempts {
            do {
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw MediaResolverError.invalidResponse
                }

                guard (200..<300).contains(httpResponse.statusCode) else {
                    if retryPolicy.shouldRetry(statusCode: httpResponse.statusCode, afterAttempt: attempt) {
                        try await retryPolicy.wait(
                            afterAttempt: attempt,
                            retryAfter: httpResponse.value(forHTTPHeaderField: "Retry-After")
                        )
                        continue
                    }
                    throw MediaResolverError.httpStatus(httpResponse.statusCode)
                }

                guard !data.isEmpty, data.count <= 20 * 1_024 * 1_024,
                      let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
                else {
                    throw MediaResolverError.invalidResponse
                }

                return HTMLDocument(html: html, finalURL: httpResponse.url ?? url)
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as URLError where error.code == .cancelled {
                throw CancellationError()
            } catch {
                if retryPolicy.shouldRetry(error: error, afterAttempt: attempt) {
                    try await retryPolicy.wait(afterAttempt: attempt)
                    continue
                }
                throw error
            }
        }

        throw MediaResolverError.invalidResponse
    }

    private func extractMediaAssets(
        from html: String,
        target: InstagramTarget,
        jsonObjects: [Any]
    ) -> [MediaAsset] {
        var resolved: [MediaCandidate] = []
        let structuredAssets = extractStructuredJSONAssets(from: jsonObjects, target: target)
        let embeddedAssets = extractEmbeddedJSONAssets(from: html, target: target)

        resolved.append(contentsOf: structuredAssets)

        if !structuredAssets.contains(where: { $0.kind == .image }) {
            resolved.append(contentsOf: embeddedAssets.filter { $0.kind == .image })
        }

        if !structuredAssets.contains(where: { $0.kind == .video }) {
            resolved.append(contentsOf: embeddedAssets.filter { $0.kind == .video })
        }

        if resolved.isEmpty && target.allowsOpenGraphFallback {
            resolved.append(contentsOf: extractOpenGraphAssets(from: html))
        }

        let uniqueCandidates = deduplicatedCandidates(resolved)

        return uniqueCandidates.enumerated().map { offset, candidate in
            let finalKind = candidate.kind == .unknown ? MediaKind.infer(from: candidate.sourceURL) : candidate.kind

            return MediaAsset(
                sourceURL: candidate.sourceURL,
                kind: finalKind,
                suggestedFilename: suggestedFilename(for: candidate.sourceURL, kind: finalKind, index: offset + 1)
            )
        }
    }

    private func extractOpenGraphAssets(from html: String) -> [MediaCandidate] {
        let tags = matches(pattern: #"<meta\b[^>]*>"#, in: html)

        return tags.compactMap { tag in
            let attributes = attributes(from: tag)
            let property = attributes["property"] ?? attributes["name"]
            let content = attributes["content"]

            guard
                let property = property?.lowercased(),
                let content,
                let url = URL(string: decodeHTMLEntities(content))
            else {
                return nil
            }

            if property.hasPrefix("og:image") {
                return MediaCandidate(sourceURL: url, kind: .image, priority: 10)
            }

            if property.hasPrefix("og:video") {
                return MediaCandidate(sourceURL: url, kind: .video, priority: 10)
            }

            return nil
        }
    }

    private func extractEmbeddedJSONAssets(from html: String, target: InstagramTarget) -> [MediaCandidate] {
        let source = regexSource(from: html, target: target)
        let imagePatterns = [
            #""image_versions2"\s*:\s*\{\s*"candidates"\s*:\s*\[\s*\{[^{}]*"url"\s*:\s*"([^"]+)""#,
            #""display_url"\s*:\s*"([^"]+)""#
        ]
        let videoPatterns = [
            #""video_url"\s*:\s*"([^"]+)""#,
            #""video_versions"\s*:\s*\[\s*\{[^{}]*"url"\s*:\s*"([^"]+)""#
        ]

        let images = imagePatterns.flatMap { pattern in
            captureGroupMatches(pattern: pattern, in: source).compactMap { fragment -> MediaCandidate? in
                guard let url = URL(string: decodeJSONStringFragment(fragment)) else {
                    return nil
                }

                return MediaCandidate(sourceURL: url, kind: .image, priority: 30)
            }
        }

        let videos = videoPatterns.flatMap { pattern in
            captureGroupMatches(pattern: pattern, in: source).compactMap { fragment -> MediaCandidate? in
                guard let url = URL(string: decodeJSONStringFragment(fragment)) else {
                    return nil
                }

                return MediaCandidate(sourceURL: url, kind: .video, priority: 20)
            }
        }

        return images + videos
    }

    private func regexSource(from html: String, target: InstagramTarget) -> String {
        guard let token = target.scopedToken else {
            return html
        }

        let scriptBodies = captureGroupMatches(
            pattern: #"<script\b[^>]*>(.*?)</script>"#,
            in: html,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
        let matchingScripts = scriptBodies.filter { $0.contains(token) }

        if matchingScripts.isEmpty {
            return target.allowsOpenGraphFallback ? html : ""
        }

        return matchingScripts.joined(separator: "\n")
    }

    private func extractStructuredJSONAssets(from jsonObjects: [Any], target: InstagramTarget) -> [MediaCandidate] {
        guard !jsonObjects.isEmpty else {
            return []
        }

        switch target {
        case let .post(shortcode, _):
            let matchingNodes = jsonObjects.flatMap { findMediaNodes(matchingShortcode: shortcode, in: $0) }
            let candidates = matchingNodes.flatMap { collectMediaCandidates(from: $0) }

            if !candidates.isEmpty {
                return candidates
            }
        case let .story(_, id):
            let matchingNodes = jsonObjects.flatMap { findMediaNodes(matchingStoryID: id, in: $0) }
            let candidates = matchingNodes.flatMap { collectMediaCandidates(from: $0) }

            if !candidates.isEmpty {
                return candidates
            }
        case .unknown:
            return []
        }

        return []
    }

    private func applicationJSONObjects(from html: String) -> [Any] {
        let scriptBodies = captureGroupMatches(
            pattern: #"<script\b[^>]*type=["']application/json["'][^>]*>(.*?)</script>"#,
            in: html,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
        return scriptBodies.compactMap { body -> Any? in
            let decodedBody = decodeHTMLEntities(body)

            guard let data = decodedBody.data(using: .utf8) else {
                return nil
            }

            return try? JSONSerialization.jsonObject(with: data)
        }
    }

    private func username(from html: String, target: InstagramTarget, jsonObjects: [Any]) -> String? {
        if let username = target.usernameFromPath {
            return username
        }

        guard case let .post(shortcode, _) = target else {
            return nil
        }

        let matchingNodes = jsonObjects.flatMap { findMediaNodes(matchingShortcode: shortcode, in: $0) }

        for node in matchingNodes {
            if let username = username(fromMediaNode: node) {
                return username
            }
        }

        return captureGroupMatches(pattern: #""username"\s*:\s*"([^"]+)""#, in: regexSource(from: html, target: target))
            .map(decodeJSONStringFragment)
            .first
    }

    private func username(fromMediaNode dictionary: [String: Any]) -> String? {
        if
            let owner = dictionary["owner"] as? [String: Any],
            let username = stringValue(owner["username"])
        {
            return username
        }

        if
            let user = dictionary["user"] as? [String: Any],
            let username = stringValue(user["username"])
        {
            return username
        }

        if let username = stringValue(dictionary["username"]) {
            return username
        }

        var foundUsername: String?
        walkJSON(dictionary) { child in
            guard foundUsername == nil else {
                return
            }

            if
                (child["profile_pic_url"] != nil || child["full_name"] != nil),
                let username = stringValue(child["username"])
            {
                foundUsername = username
            }
        }

        return foundUsername
    }

    private func findMediaNodes(matchingShortcode shortcode: String, in value: Any) -> [[String: Any]] {
        var matches: [[String: Any]] = []
        walkJSON(value) { dictionary in
            if stringValue(dictionary["shortcode"]) == shortcode || stringValue(dictionary["code"]) == shortcode {
                matches.append(dictionary)
            }
        }

        return matches
    }

    private func findMediaNodes(matchingStoryID storyID: String, in value: Any) -> [[String: Any]] {
        var matches: [[String: Any]] = []
        walkJSON(value) { dictionary in
            let ids = [
                stringValue(dictionary["id"]),
                stringValue(dictionary["pk"]),
                stringValue(dictionary["media_id"]),
                stringValue(dictionary["organic_tracking_token"])
            ]

            if ids.contains(where: { $0 == storyID || $0?.hasPrefix("\(storyID)_") == true }) {
                matches.append(dictionary)
            }
        }

        return matches
    }

    private func collectMediaCandidates(from value: Any) -> [MediaCandidate] {
        var candidates: [MediaCandidate] = []

        walkJSON(value) { dictionary in
            candidates.append(contentsOf: mediaCandidates(from: dictionary))
        }

        return candidates
    }

    private func mediaCandidates(from dictionary: [String: Any]) -> [MediaCandidate] {
        if hasCarouselChildren(dictionary) {
            return []
        }

        let isVideo = boolValue(dictionary["is_video"]) == true ||
            intValue(dictionary["media_type"]) == 2 ||
            dictionary["video_url"] != nil ||
            dictionary["video_versions"] != nil
        var candidates: [MediaCandidate] = []

        if let videoURL = urlValue(dictionary["video_url"]) {
            candidates.append(MediaCandidate(sourceURL: videoURL, kind: .video, priority: 50))
        }

        if let videoURL = bestVideoURL(fromVideoVersions: dictionary["video_versions"]) {
            candidates.append(MediaCandidate(sourceURL: videoURL, kind: .video, priority: 50))
        }

        if !isVideo, let imageURL = bestImageURL(fromImageVersions: dictionary["image_versions2"]) {
            candidates.append(MediaCandidate(sourceURL: imageURL, kind: .image, priority: 50))
        }

        if !isVideo, let displayURL = urlValue(dictionary["display_url"]) {
            candidates.append(MediaCandidate(sourceURL: displayURL, kind: .image, priority: 40))
        }

        return candidates
    }

    private func hasCarouselChildren(_ dictionary: [String: Any]) -> Bool {
        dictionary["edge_sidecar_to_children"] != nil ||
            dictionary["carousel_media"] != nil ||
            dictionary["carousel_media_count"] != nil
    }

    private func bestImageURL(fromImageVersions value: Any?) -> URL? {
        guard
            let imageVersions = value as? [String: Any],
            let candidates = imageVersions["candidates"] as? [[String: Any]]
        else {
            return nil
        }

        return candidates
            .compactMap { candidate -> (url: URL, area: Int)? in
                guard let url = urlValue(candidate["url"]) else {
                    return nil
                }

                let width = intValue(candidate["width"]) ?? 0
                let height = intValue(candidate["height"]) ?? 0

                return (url, width * height)
            }
            .max { lhs, rhs in lhs.area < rhs.area }?
            .url
    }

    private func bestVideoURL(fromVideoVersions value: Any?) -> URL? {
        guard let candidates = value as? [[String: Any]] else {
            return nil
        }

        return candidates
            .compactMap { candidate -> (url: URL, area: Int)? in
                guard let url = urlValue(candidate["url"]) else {
                    return nil
                }

                let width = intValue(candidate["width"]) ?? 0
                let height = intValue(candidate["height"]) ?? 0

                return (url, width * height)
            }
            .max { lhs, rhs in lhs.area < rhs.area }?
            .url
    }

    private func walkJSON(_ value: Any, visit: ([String: Any]) -> Void) {
        if let dictionary = value as? [String: Any] {
            visit(dictionary)

            for child in dictionary.values {
                walkJSON(child, visit: visit)
            }
        } else if let array = value as? [Any] {
            for child in array {
                walkJSON(child, visit: visit)
            }
        }
    }

    private func deduplicatedCandidates(_ candidates: [MediaCandidate]) -> [MediaCandidate] {
        var bestByKey: [String: MediaCandidate] = [:]
        var insertionOrder: [String] = []

        for candidate in candidates {
            let key = mediaFingerprint(for: candidate)

            if let existing = bestByKey[key] {
                if candidate.priority > existing.priority || isBetterVariant(candidate.sourceURL, than: existing.sourceURL) {
                    bestByKey[key] = candidate
                }
            } else {
                bestByKey[key] = candidate
                insertionOrder.append(key)
            }
        }

        return insertionOrder.compactMap { bestByKey[$0] }
    }

    private func mediaFingerprint(for candidate: MediaCandidate) -> String {
        let url = candidate.sourceURL
        let kind = candidate.kind == .unknown ? MediaKind.infer(from: url) : candidate.kind
        let kindPrefix = kind.rawValue
        let host = url.host(percentEncoded: false)?.lowercased() ?? ""

        if isInstagramCDNHost(host) {
            return "\(kindPrefix):ig-cdn:\(host)\(url.path.lowercased())"
        }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.query = nil
        components?.fragment = nil

        return "\(kindPrefix):\(components?.url?.absoluteString.lowercased() ?? url.absoluteString.lowercased())"
    }

    private func isInstagramCDNHost(_ host: String) -> Bool {
        host.contains("cdninstagram.com") || host.contains("fbcdn.net")
    }

    private func isBetterVariant(_ url: URL, than otherURL: URL) -> Bool {
        let score = variantScore(for: url)
        let otherScore = variantScore(for: otherURL)

        if score != otherScore {
            return score > otherScore
        }

        return url.absoluteString.count > otherURL.absoluteString.count
    }

    private func variantScore(for url: URL) -> Int {
        let string = url.absoluteString.lowercased()
        var score = 0

        if string.contains("dst-jpg") || string.contains("dst-webp") {
            score += 3
        }

        if string.contains("_e35") {
            score += 2
        }

        if string.contains("_nc_ht") {
            score += 1
        }

        return score
    }

    private func attributes(from tag: String) -> [String: String] {
        let pairs = captureGroupPairMatches(pattern: #"([\w:-]+)\s*=\s*["']([^"']+)["']"#, in: tag)

        return Dictionary(uniqueKeysWithValues: pairs.map { pair in
            (pair.0.lowercased(), pair.1)
        })
    }

    private func matches(pattern: String, in string: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let nsString = string as NSString
        let range = NSRange(location: 0, length: nsString.length)

        return regex.matches(in: string, options: [], range: range).map {
            nsString.substring(with: $0.range)
        }
    }

    private func captureGroupMatches(pattern: String, in string: String) -> [String] {
        captureGroupMatches(pattern: pattern, in: string, options: [.caseInsensitive])
    }

    private func captureGroupMatches(pattern: String, in string: String, options: NSRegularExpression.Options) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return []
        }

        let nsString = string as NSString
        let range = NSRange(location: 0, length: nsString.length)

        return regex.matches(in: string, options: [], range: range).compactMap { result in
            guard result.numberOfRanges > 1 else {
                return nil
            }

            return nsString.substring(with: result.range(at: 1))
        }
    }

    private func urlValue(_ value: Any?) -> URL? {
        guard let string = stringValue(value) else {
            return nil
        }

        return URL(string: decodeJSONStringFragment(string))
    }

    private func stringValue(_ value: Any?) -> String? {
        if let string = value as? String {
            return string
        }

        if let number = value as? NSNumber {
            return number.stringValue
        }

        return nil
    }

    private func boolValue(_ value: Any?) -> Bool? {
        if let bool = value as? Bool {
            return bool
        }

        if let number = value as? NSNumber {
            return number.boolValue
        }

        return nil
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

    private func captureGroupPairMatches(pattern: String, in string: String) -> [(String, String)] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let nsString = string as NSString
        let range = NSRange(location: 0, length: nsString.length)

        return regex.matches(in: string, options: [], range: range).compactMap { result in
            guard result.numberOfRanges > 2 else {
                return nil
            }

            return (nsString.substring(with: result.range(at: 1)), nsString.substring(with: result.range(at: 2)))
        }
    }

    private func decodeJSONStringFragment(_ fragment: String) -> String {
        let wrapped = "\"\(fragment)\""

        guard
            let data = wrapped.data(using: .utf8),
            let decoded = try? JSONSerialization.jsonObject(with: data) as? String
        else {
            return decodeHTMLEntities(fragment)
                .replacingOccurrences(of: #"\/"#, with: "/")
                .replacingOccurrences(of: #"\\u0026"#, with: "&")
        }

        return decodeHTMLEntities(decoded)
    }

    private func decodeHTMLEntities(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
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

        return "ig-save-\(index).\(ext)"
    }
}
