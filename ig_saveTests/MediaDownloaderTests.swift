import Foundation
import Testing
@testable import IGSave

struct MediaDownloaderTests {
    @Test("后台传输标识在重启后保持稳定")
    func stableTransferIdentifier() throws {
        let jobID = try #require(UUID(uuidString: "A73C4B1B-9F71-4E61-9348-5D2C54DB7F82"))
        let asset = MediaAsset(
            sourceURL: try #require(URL(string: "https://cdn.example.com/video.mp4?token=abc")),
            kind: .video,
            suggestedFilename: "reel.mp4"
        )
        let equivalentAsset = MediaAsset(
            sourceURL: try #require(URL(string: "https://cdn.example.com/video.mp4?token=abc")),
            kind: .video,
            suggestedFilename: "reel.mp4"
        )

        let first = MediaDownloader.transferIdentifier(jobID: jobID, asset: asset)
        let second = MediaDownloader.transferIdentifier(jobID: jobID, asset: equivalentAsset)

        #expect(first == second)
        #expect(first.hasPrefix(jobID.uuidString.lowercased()))
    }

    @Test("不同任务不会复用同一后台文件")
    func separatesJobs() throws {
        let asset = MediaAsset(
            sourceURL: try #require(URL(string: "https://cdn.example.com/image.jpg")),
            kind: .image,
            suggestedFilename: "post.jpg"
        )

        let first = MediaDownloader.transferIdentifier(jobID: UUID(), asset: asset)
        let second = MediaDownloader.transferIdentifier(jobID: UUID(), asset: asset)

        #expect(first != second)
    }

    @Test("缓存清理同时遵循有效期和总容量")
    func cacheCleanup() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("igsave-cache-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let expired = directory.appendingPathComponent("expired.media")
        let oversized = directory.appendingPathComponent("oversized.media")
        let fresh = directory.appendingPathComponent("fresh.media")
        try Data(repeating: 1, count: 4).write(to: expired)
        try Data(repeating: 2, count: 10).write(to: oversized)
        try Data(repeating: 3, count: 4).write(to: fresh)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-2_000)], ofItemAtPath: expired.path)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-100)], ofItemAtPath: oversized.path)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-10)], ofItemAtPath: fresh.path)

        MediaDownloader.cleanDirectories(
            [directory],
            maximumAge: 1_000,
            maximumBytes: 8,
            now: now
        )

        #expect(!FileManager.default.fileExists(atPath: expired.path))
        #expect(!FileManager.default.fileExists(atPath: oversized.path))
        #expect(FileManager.default.fileExists(atPath: fresh.path))
    }
}
