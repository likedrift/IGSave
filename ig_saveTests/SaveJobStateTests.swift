import Foundation
import Testing
@testable import IGSave

struct SaveJobStateTests {
    @Test("完成状态会准确区分成功、部分成功与失败")
    func completionStatus() {
        #expect(SaveCompletion.status(saved: 3, failed: 0, message: "") == .saved(count: 3))
        #expect(
            SaveCompletion.status(saved: 2, failed: 1, message: "网络超时") ==
                .partiallySaved(saved: 2, failed: 1, message: "网络超时")
        )
        #expect(SaveCompletion.status(saved: 0, failed: 2, message: "网络超时") == .failed("网络超时"))
    }

    @Test("重启后运行中任务回到队列且保留逐项进度")
    func restoresInterruptedJob() throws {
        let attemptID = UUID()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let pending = SaveAssetDescriptor(
            sourceURLString: "https://example.com/second.jpg",
            kind: .image,
            suggestedFilename: "second.jpg"
        )
        let stored = SaveJob(
            input: "https://instagram.com/p/example",
            status: .saving(current: 2, total: 3),
            attemptID: attemptID,
            pendingAssets: [pending],
            successfulAssetCount: 1
        )

        let restored = try #require(SaveJobStore.restored([stored], now: now).first)

        #expect(restored.status == .queued)
        #expect(restored.attemptID == nil)
        #expect(restored.pendingAssets == [pending])
        #expect(restored.successfulAssetCount == 1)
        #expect(restored.updatedAt == now)
    }

    @Test("恢复时移除已完成任务但保留部分成功任务")
    func keepsActionableTerminalJobs() {
        let completed = SaveJob(input: "completed", status: .saved(count: 1))
        let partial = SaveJob(
            input: "partial",
            status: .partiallySaved(saved: 1, failed: 1, message: "超时")
        )

        let restored = SaveJobStore.restored([completed, partial])

        #expect(restored.map(\.id) == [partial.id])
    }

    @Test("新增恢复字段支持编码往返")
    func persistenceRoundTrip() throws {
        let descriptor = SaveAssetDescriptor(
            sourceURLString: "https://example.com/video.mp4",
            kind: .video,
            suggestedFilename: "video.mp4"
        )
        let original = SaveJob(
            input: "https://instagram.com/reel/example",
            status: .partiallySaved(saved: 1, failed: 1, message: "超时"),
            pendingAssets: [],
            failedAssets: [descriptor],
            successfulAssetCount: 1,
            failedAssetCount: 1,
            lastErrorMessage: "超时",
            lastErrorCategory: .network,
            lastErrorCode: "network.timeout",
            recentSaveID: UUID()
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SaveJob.self, from: data)

        #expect(decoded == original)
    }

    @Test("部分成功重试只保留未完成资源")
    func retriesOnlyUnfinishedAssets() {
        let failed = SaveAssetDescriptor(
            sourceURLString: "https://example.com/failed.jpg",
            kind: .image,
            suggestedFilename: "failed.jpg"
        )
        let pending = SaveAssetDescriptor(
            sourceURLString: "https://example.com/pending.mp4",
            kind: .video,
            suggestedFilename: "pending.mp4"
        )
        let now = Date(timeIntervalSince1970: 1_700_000_100)
        var job = SaveJob(
            input: "https://instagram.com/p/example",
            status: .partiallySaved(saved: 2, failed: 1, message: "超时"),
            attemptID: UUID(),
            pendingAssets: [pending],
            failedAssets: [failed, pending],
            successfulAssetCount: 2,
            failedAssetCount: 1,
            lastErrorMessage: "超时",
            lastErrorCategory: .network,
            lastErrorCode: "network.timeout",
            recentSaveID: UUID()
        )

        job.prepareForRetry(now: now)

        #expect(job.status == .queued)
        #expect(job.pendingAssets == [failed, pending])
        #expect(job.failedAssets == [])
        #expect(job.successfulAssetCount == 2)
        #expect(job.failedAssetCount == 0)
        #expect(job.lastErrorMessage == nil)
        #expect(job.lastErrorCategory == nil)
        #expect(job.lastErrorCode == nil)
        #expect(job.attemptID == nil)
        #expect(job.allowsDuplicate)
        #expect(job.updatedAt == now)
    }

    @Test("重新解析后只选择尚未保存的媒体并保持任务顺序")
    func matchesRefreshedPendingAssets() throws {
        let first = MediaAsset(
            sourceURL: try #require(URL(string: "https://cdn.example.com/new-first.jpg")),
            kind: .image,
            suggestedFilename: "ig-save-1.jpg"
        )
        let second = MediaAsset(
            sourceURL: try #require(URL(string: "https://cdn.example.com/new-second.jpg")),
            kind: .image,
            suggestedFilename: "ig-save-2.jpg"
        )
        let third = MediaAsset(
            sourceURL: try #require(URL(string: "https://cdn.example.com/new-third.mp4")),
            kind: .video,
            suggestedFilename: "ig-save-3.mp4"
        )
        let descriptors = [SaveAssetDescriptor(asset: third), SaveAssetDescriptor(asset: second)]

        let matches = DownloadViewModel.assetsMatchingPendingDescriptors(
            descriptors,
            in: [first, second, third]
        )

        #expect(matches?.map(\.suggestedFilename) == ["ig-save-3.mp4", "ig-save-2.jpg"])
        #expect(matches?.map(\.sourceURL) == [third.sourceURL, second.sourceURL])
    }
}
