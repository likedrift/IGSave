import Foundation
import Testing
@testable import IGSave

struct CreatorWorkflowTests {
    @Test("旧版关注账号会获得安全的更新字段默认值")
    func decodesLegacyFavoriteProfile() throws {
        let legacy = LegacyFavoriteProfile(
            username: "example",
            addedAt: Date(timeIntervalSinceReferenceDate: 100),
            lastKnownPostIDs: ["post-a"]
        )

        let data = try JSONEncoder().encode(legacy)
        let decoded = try JSONDecoder().decode(FavoriteProfile.self, from: data)

        #expect(decoded.username == "example")
        #expect(decoded.lastKnownPostIDs == ["post-a"])
        #expect(decoded.unseenPostIDs.isEmpty)
        #expect(decoded.lastCheckedAt == nil)
    }

    @Test("检查账号会合并新增内容并保留未处理状态")
    func appliesCreatorSnapshot() throws {
        let checkedAt = Date(timeIntervalSinceReferenceDate: 200)
        let profile = FavoriteProfile(
            username: "example",
            lastKnownPostIDs: ["post-a", "post-b"],
            unseenPostIDs: ["older-unseen"]
        )

        let result = FavoriteProfileStore.applyingSnapshot(
            username: "EXAMPLE",
            currentPostIDs: ["post-b", "post-c"],
            to: [profile],
            now: checkedAt
        )
        let updated = try #require(result.profiles.first)

        #expect(result.newContentIDs == ["post-c"])
        #expect(updated.lastKnownPostIDs == ["post-b", "post-c"])
        #expect(updated.unseenPostIDs == ["older-unseen", "post-c"])
        #expect(updated.lastCheckedAt == checkedAt)
    }

    @Test("首次检查不会把现有内容全部误报为新增")
    func establishesInitialCreatorSnapshot() throws {
        let result = FavoriteProfileStore.applyingSnapshot(
            username: "example",
            currentPostIDs: ["post-a", "post-b"],
            to: [FavoriteProfile(username: "example")]
        )
        let updated = try #require(result.profiles.first)

        #expect(result.newContentIDs.isEmpty)
        #expect(updated.unseenPostIDs.isEmpty)
        #expect(updated.lastKnownPostIDs == ["post-a", "post-b"])
    }

    @Test("保存部分新增内容只清除对应未读项")
    func marksSelectedCreatorContentSeen() throws {
        let profile = FavoriteProfile(
            username: "example",
            unseenPostIDs: ["post-a", "post-b", "post-c"]
        )

        let partiallyUpdated = FavoriteProfileStore.markingSeen(
            username: "example",
            postIDs: ["post-a", "post-c"],
            in: [profile]
        )
        let partial = try #require(partiallyUpdated.first)
        #expect(partial.unseenPostIDs == ["post-b"])

        let fullyUpdated = FavoriteProfileStore.markingSeen(
            username: "example",
            in: partiallyUpdated
        )
        #expect(fullyUpdated.first?.unseenPostIDs.isEmpty == true)
    }
}

private struct LegacyFavoriteProfile: Encodable {
    let username: String
    let addedAt: Date
    let lastKnownPostIDs: Set<String>
}
