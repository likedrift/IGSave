//
//  MediaDownloader.swift
//  ig_save
//

import Foundation

enum MediaDownloaderError: LocalizedError, Sendable {
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "媒体下载响应无效。"
        }
    }
}

struct MediaDownloader: Sendable {
    func download(
        _ asset: MediaAsset,
        jobID: UUID,
        allowsCellularAccess: Bool = true
    ) async throws -> URL {
        var request = URLRequest(url: asset.sourceURL)
        request.timeoutInterval = 90
        request.allowsCellularAccess = allowsCellularAccess
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.instagram.com/", forHTTPHeaderField: "Referer")

        if let cookieHeader = await InstagramSessionStore.cookieHeader(for: asset.sourceURL) {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }

        do {
            return try await BackgroundDownloadCoordinator.shared.download(
                request: request,
                identifier: Self.transferIdentifier(jobID: jobID, asset: asset),
                fileExtension: Self.preferredFileExtension(for: asset)
            )
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        }
    }

    static func cleanCache(maximumAge: TimeInterval = 7 * 24 * 60 * 60, maximumBytes: Int64 = 500 * 1_024 * 1_024) {
        cleanDirectories(cacheDirectories(), maximumAge: maximumAge, maximumBytes: maximumBytes)
    }

    static func cacheUsageBytes() -> Int64 {
        files(in: cacheDirectories()).reduce(Int64(0)) { $0 + $1.size }
    }

    static func clearCache() {
        removeContents(of: cacheDirectories())
    }

    static func removeContents(of directories: [URL]) {
        for file in files(in: directories) {
            try? FileManager.default.removeItem(at: file.url)
        }
    }

    static func cleanDirectories(
        _ directories: [URL],
        maximumAge: TimeInterval,
        maximumBytes: Int64,
        now: Date = Date()
    ) {
        var files = files(in: directories)

        let expirationDate = now.addingTimeInterval(-maximumAge)
        for file in files where file.modifiedAt < expirationDate {
            try? FileManager.default.removeItem(at: file.url)
        }

        files.removeAll { !FileManager.default.fileExists(atPath: $0.url.path) }
        var totalBytes = files.reduce(Int64(0)) { $0 + $1.size }

        for file in files.sorted(by: { $0.modifiedAt < $1.modifiedAt }) where totalBytes > maximumBytes {
            try? FileManager.default.removeItem(at: file.url)
            totalBytes -= file.size
        }
    }

    static func transferIdentifier(jobID: UUID, asset: MediaAsset) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        let identity = [
            asset.sourceURL.absoluteString,
            asset.kind.rawValue,
            asset.suggestedFilename
        ].joined(separator: "|")
        for byte in identity.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return "\(jobID.uuidString.lowercased())-\(String(hash, radix: 16))"
    }

    private static func preferredFileExtension(for asset: MediaAsset) -> String {
        let suggestedExtension = URL(fileURLWithPath: asset.suggestedFilename).pathExtension.lowercased()
        let sourceExtension = asset.sourceURL.pathExtension.lowercased()
        let candidate = suggestedExtension.isEmpty ? sourceExtension : suggestedExtension
        let sanitized = candidate.filter { $0.isLetter || $0.isNumber }
        if !sanitized.isEmpty {
            return String(sanitized.prefix(10))
        }

        switch asset.kind {
        case .image: return "jpg"
        case .video: return "mp4"
        case .unknown: return "media"
        }
    }

    private static func legacyCacheDirectoryURL() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DownloadedMedia", isDirectory: true)
    }

    private static func cacheDirectories() -> [URL] {
        [legacyCacheDirectoryURL(), try? BackgroundDownloadCoordinator.cacheDirectoryURL()]
            .compactMap { $0 }
    }

    private static func files(in directories: [URL]) -> [(url: URL, modifiedAt: Date, size: Int64)] {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
        return directories.flatMap { directory in
            (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: Array(keys),
                options: .skipsHiddenFiles
            )) ?? []
        }.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
            return (url, values.contentModificationDate ?? .distantPast, Int64(values.fileSize ?? 0))
        }
    }
}
