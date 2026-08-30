import Foundation

enum MediaCollectionStore {
    static let maximumCount = 50

    static func load() -> [MediaCollection] {
        guard let collections = DurableJSONStore.load([MediaCollection].self, from: storageURL()) else {
            return []
        }
        return Array(collections.prefix(maximumCount))
    }

    static func create(named rawName: String, in collections: [MediaCollection]) -> [MediaCollection] {
        let name = normalizedName(rawName)
        guard !name.isEmpty,
              !collections.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            return collections
        }

        var updated = collections
        updated.append(MediaCollection(name: name))
        updated = Array(updated.prefix(maximumCount))
        persist(updated)
        return updated
    }

    static func rename(_ collection: MediaCollection, to rawName: String, in collections: [MediaCollection]) -> [MediaCollection] {
        let name = normalizedName(rawName)
        guard !name.isEmpty,
              !collections.contains(where: { $0.id != collection.id && $0.name.caseInsensitiveCompare(name) == .orderedSame }),
              let index = collections.firstIndex(where: { $0.id == collection.id }) else {
            return collections
        }

        var updated = collections
        updated[index].name = name
        updated[index].updatedAt = Date()
        persist(updated)
        return updated
    }

    static func remove(_ collection: MediaCollection, from collections: [MediaCollection]) -> [MediaCollection] {
        let updated = collections.filter { $0.id != collection.id }
        persist(updated)
        return updated
    }

    static func normalizedName(_ rawName: String) -> String {
        String(rawName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(30))
    }

    private static func persist(_ collections: [MediaCollection]) {
        DurableJSONStore.persist(Array(collections.prefix(maximumCount)), to: storageURL())
    }

    private static func storageURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("collections-v1.json")
    }
}
