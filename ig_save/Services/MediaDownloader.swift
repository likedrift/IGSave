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
    func download(_ asset: MediaAsset, allowsCellularAccess: Bool = true) async throws -> URL {
        var request = URLRequest(url: asset.sourceURL)
        request.timeoutInterval = 60
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.instagram.com/", forHTTPHeaderField: "Referer")

        if let cookieHeader = await InstagramSessionStore.cookieHeader(for: asset.sourceURL) {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }

        let configuration = URLSessionConfiguration.default
        configuration.allowsCellularAccess = allowsCellularAccess
        let session = URLSession(configuration: configuration)
        let (temporaryURL, response) = try await session.download(for: request)

        guard
            let httpResponse = response as? HTTPURLResponse,
            (200..<300).contains(httpResponse.statusCode)
        else {
            throw MediaDownloaderError.invalidResponse
        }

        let directory = try cacheDirectory()
        let destinationURL = directory.appendingPathComponent(uniqueFilename(asset.suggestedFilename))

        try? FileManager.default.removeItem(at: destinationURL)
        try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)

        return destinationURL
    }

    static func cleanCache(maximumAge: TimeInterval = 7 * 24 * 60 * 60, maximumBytes: Int64 = 500 * 1_024 * 1_024) {
        guard let directory = try? cacheDirectoryURL() else {
            return
        }

        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
        var files = ((try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: .skipsHiddenFiles
        )) ?? []).compactMap { url -> (URL, Date, Int64)? in
            guard let values = try? url.resourceValues(forKeys: keys) else {
                return nil
            }
            return (url, values.contentModificationDate ?? .distantPast, Int64(values.fileSize ?? 0))
        }

        let expirationDate = Date().addingTimeInterval(-maximumAge)
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

    private func cacheDirectory() throws -> URL {
        let directory = try Self.cacheDirectoryURL()

        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        return directory
    }

    private static func cacheDirectoryURL() throws -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DownloadedMedia", isDirectory: true)
    }

    private func uniqueFilename(_ filename: String) -> String {
        let name = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        let ext = URL(fileURLWithPath: filename).pathExtension
        let suffix = UUID().uuidString.prefix(8)

        if ext.isEmpty {
            return "\(name)-\(suffix)"
        }

        return "\(name)-\(suffix).\(ext)"
    }
}
