import Foundation
import Testing
@testable import IGSave

struct MediaLibraryTests {
    @Test("旧版历史记录会获得安全的整理字段默认值")
    func decodesLegacyRecentSave() throws {
        let legacy = LegacyRecentSave(
            id: UUID(),
            username: "@example",
            savedAt: Date(timeIntervalSinceReferenceDate: 123),
            itemCount: 2,
            contentKind: .post,
            sourceURL: "https://instagram.com/p/example",
            previewFilename: "preview.jpg"
        )

        let data = try JSONEncoder().encode(legacy)
        let decoded = try JSONDecoder().decode(RecentSave.self, from: data)

        #expect(!decoded.isFavorite)
        #expect(decoded.collectionIDs.isEmpty)
        #expect(decoded.tags.isEmpty)
        #expect(decoded.note == nil)
        #expect(decoded.metadataUpdatedAt == nil)
    }

    @Test("整理信息更新保持原顺序并规范化标签")
    func updatesLibraryMetadata() throws {
        let first = RecentSave(
            username: "@first",
            itemCount: 1,
            contentKind: .post,
            sourceURL: "https://instagram.com/p/first",
            previewFilename: nil
        )
        let second = RecentSave(
            username: "@second",
            itemCount: 1,
            contentKind: .reel,
            sourceURL: "https://instagram.com/reel/second",
            previewFilename: nil
        )
        let collectionID = UUID()
        let now = Date(timeIntervalSinceReferenceDate: 456)

        let updated = RecentSaveStore.updateMetadata(
            for: second.id,
            isFavorite: true,
            collectionIDs: [collectionID, collectionID],
            tags: ["#旅行", "旅行", "  灵感  ", ""],
            note: "  稍后整理  ",
            in: [first, second],
            now: now
        )
        let saved = try #require(updated.last)

        #expect(updated.map(\.id) == [first.id, second.id])
        #expect(saved.isFavorite)
        #expect(saved.collectionIDs == [collectionID])
        #expect(saved.tags == ["旅行", "灵感"])
        #expect(saved.note == "稍后整理")
        #expect(saved.metadataUpdatedAt == now)
    }

    @Test("删除收藏夹只移除分类关系")
    func removesCollectionReference() throws {
        let removedID = UUID()
        let retainedID = UUID()
        let save = RecentSave(
            username: "@example",
            itemCount: 1,
            contentKind: .story,
            sourceURL: "https://instagram.com/stories/example/1",
            previewFilename: nil,
            isFavorite: true,
            collectionIDs: [removedID, retainedID],
            tags: ["灵感"],
            note: "保留这条备注"
        )

        let updated = try #require(RecentSaveStore.removeCollection(removedID, from: [save]).first)

        #expect(updated.collectionIDs == [retainedID])
        #expect(updated.isFavorite)
        #expect(updated.tags == ["灵感"])
        #expect(updated.note == "保留这条备注")
    }

    @Test("收藏夹名称会去重并限制长度")
    func validatesCollectionNames() throws {
        let created = MediaCollectionStore.create(named: "  旅行灵感  ", in: [])
        let collection = try #require(created.first)
        let duplicate = MediaCollectionStore.create(named: "旅行灵感", in: created)
        let renamed = MediaCollectionStore.rename(
            collection,
            to: String(repeating: "灵", count: 40),
            in: created
        )

        #expect(collection.name == "旅行灵感")
        #expect(duplicate == created)
        #expect(renamed.first?.name.count == 30)

        _ = MediaCollectionStore.remove(collection, from: renamed)
    }
}

private struct LegacyRecentSave: Encodable {
    let id: UUID
    let username: String
    let savedAt: Date
    let itemCount: Int
    let contentKind: InstagramContentKind
    let sourceURL: String
    let previewFilename: String?
}
