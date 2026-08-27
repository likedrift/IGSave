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
        let directories = [legacyCacheDirectoryURL(), try? BackgroundDownloadCoordinator.cacheDirectoryURL()]
            .compactMap { $0 }
        cleanDirectories(directories, maximumAge: maximumAge, maximumBytes: maximumBytes)
    }

    static func cleanDirectories(
        _ directories: [URL],
        maximumAge: TimeInterval,
        maximumBytes: Int64,
        now: Date = Date()
    ) {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
        var files = directories.flatMap { directory in
            (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: Array(keys),
                options: .skipsHiddenFiles
            )) ?? []
        }.compactMap { url -> (URL, Date, Int64)? in
            guard let values = try? url.resourceValues(forKeys: keys) else {
                return nil
            }
            return (url, values.contentModificationDate ?? .distantPast, Int64(values.fileSize ?? 0))
        }

        let expirationDate = now.addingTimeInterval(-maximumAge)
        for file in files where file.1 < expirationDate {
            try? FileManager.default.removeItem(at: file.0)
        }

        files.removeAll { !FileManager.default.fileExists(atPath: $0.0.path) }
        var totalBytes = files.reduce(Int64(0)) { $0 + $1.2 }

        for file in files.sorted(by: { $0.1 < $1.1 }) where totalBytes > maximumBytes {
            try? FileManager.default.removeItem(at: file.0)
            totalBytes -= file.2
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
}
