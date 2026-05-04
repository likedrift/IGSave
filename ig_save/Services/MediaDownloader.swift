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
    func download(_ asset: MediaAsset) async throws -> URL {
        var request = URLRequest(url: asset.sourceURL)
        request.timeoutInterval = 60
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")

        let (temporaryURL, response) = try await URLSession.shared.download(for: request)

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

    private func cacheDirectory() throws -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("DownloadedMedia", isDirectory: true)

        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        return directory
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
