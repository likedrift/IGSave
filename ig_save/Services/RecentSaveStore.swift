//
//  RecentSaveStore.swift
//  ig_save
//

import Foundation

enum RecentSaveStore {
    private static let storageKey = "recent-saves-v1"
    private static let maxCount = 2_000

    static func load() -> [RecentSave] {
        if let data = try? Data(contentsOf: storageURL()),
           let saves = try? JSONDecoder().decode([RecentSave].self, from: data) {
            return Array(saves.prefix(maxCount))
        }

        guard
            let data = UserDefaults.standard.data(forKey: storageKey),
            let saves = try? JSONDecoder().decode([RecentSave].self, from: data)
        else {
            return []
        }

        let migrated = Array(saves.prefix(maxCount))
        persist(migrated)
        UserDefaults.standard.removeObject(forKey: storageKey)
        return migrated
    }

    static func add(_ save: RecentSave, to saves: [RecentSave]) -> [RecentSave] {
        let nextSaves = Array(([save] + saves).prefix(maxCount))
        persist(nextSaves)
        pruneThumbnails(keeping: nextSaves)

        return nextSaves
    }

    static func upsert(_ save: RecentSave, in saves: [RecentSave]) -> [RecentSave] {
        var nextSaves = saves.filter { $0.id != save.id }
        nextSaves.insert(save, at: 0)
        nextSaves = Array(nextSaves.prefix(maxCount))
        persist(nextSaves)
        pruneThumbnails(keeping: nextSaves)
        return nextSaves
    }

    static func previousSave(for sourceURL: String) -> RecentSave? {
        let key = normalizedSourceURL(sourceURL)
        return load().first { normalizedSourceURL($0.sourceURL) == key }
    }

    static func remove(_ save: RecentSave, from saves: [RecentSave]) -> [RecentSave] {
        let nextSaves = saves.filter { $0.id != save.id }
        persist(nextSaves)
        pruneThumbnails(keeping: nextSaves)
        return nextSaves
    }

    static func remove(ids: Set<UUID>, from saves: [RecentSave]) -> [RecentSave] {
        guard !ids.isEmpty else { return saves }
        let nextSaves = saves.filter { !ids.contains($0.id) }
        persist(nextSaves)
        pruneThumbnails(keeping: nextSaves)
        return nextSaves
    }

    static func removeAll(from saves: [RecentSave]) -> [RecentSave] {
        persist([])
        pruneThumbnails(keeping: [])
        return []
    }

    static func updateMetadata(
        for saveID: UUID,
        isFavorite: Bool,
        collectionIDs: [UUID],
        tags: [String],
        note: String?,
        in saves: [RecentSave],
        now: Date = Date()
    ) -> [RecentSave] {
        guard let index = saves.firstIndex(where: { $0.id == saveID }) else { return saves }

        var updated = saves
        updated[index].isFavorite = isFavorite
        var seenCollectionIDs: Set<UUID> = []
        updated[index].collectionIDs = collectionIDs.filter { seenCollectionIDs.insert($0).inserted }
        updated[index].tags = normalizedTags(tags)
        updated[index].note = normalizedNote(note)
        updated[index].metadataUpdatedAt = now
        persist(updated)
        return updated
    }

    static func removeCollection(_ collectionID: UUID, from saves: [RecentSave]) -> [RecentSave] {
        var updated = saves
        var didChange = false

        for index in updated.indices where updated[index].collectionIDs.contains(collectionID) {
            updated[index].collectionIDs.removeAll { $0 == collectionID }
            updated[index].metadataUpdatedAt = Date()
            didChange = true
        }

        if didChange {
            persist(updated)
        }
        return updated
    }

    static func setFavorite(
        _ isFavorite: Bool,
        for saveIDs: Set<UUID>,
        in saves: [RecentSave],
        now: Date = Date()
    ) -> [RecentSave] {
        guard !saveIDs.isEmpty else { return saves }
        var updated = saves
        var didChange = false

        for index in updated.indices
        where saveIDs.contains(updated[index].id) && updated[index].isFavorite != isFavorite {
            updated[index].isFavorite = isFavorite
            updated[index].metadataUpdatedAt = now
            didChange = true
        }

        if didChange {
            persist(updated)
        }
        return updated
    }

    static func addToCollection(
        _ collectionID: UUID,
        saveIDs: Set<UUID>,
        in saves: [RecentSave],
        now: Date = Date()
    ) -> [RecentSave] {
        guard !saveIDs.isEmpty else { return saves }
        var updated = saves
        var didChange = false

        for index in updated.indices
        where saveIDs.contains(updated[index].id) && !updated[index].collectionIDs.contains(collectionID) {
            updated[index].collectionIDs.append(collectionID)
            updated[index].metadataUpdatedAt = now
            didChange = true
        }

        if didChange {
            persist(updated)
        }
        return updated
    }

    static func normalizedTags(_ rawTags: [String]) -> [String] {
        var normalized: [String] = []
        var normalizedKeys: Set<String> = []
        let trimmingCharacters = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: "#"))

        for rawTag in rawTags {
            let tag = String(
                rawTag
                    .trimmingCharacters(in: trimmingCharacters)
                    .prefix(20)
            )
            let key = tag.lowercased()
            guard !tag.isEmpty, normalizedKeys.insert(key).inserted else { continue }
            normalized.append(tag)
            if normalized.count == 10 { break }
        }
        return normalized
    }

    static func previewURL(for filename: String?) -> URL? {
        guard let filename else {
            return nil
        }

        return try? previewsDirectory().appendingPathComponent(filename)
    }

    static func previewsDirectory() throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("RecentPreviews", isDirectory: true)

        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        return directory
    }

    private static func persist(_ saves: [RecentSave]) {
        guard let data = try? JSONEncoder().encode(saves) else {
            return
        }

        let url = storageURL()
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    private static func pruneThumbnails(keeping saves: [RecentSave]) {
        guard let directory = try? previewsDirectory() else {
            return
        }

        let keepFilenames = Set(saves.compactMap(\.previewFilename))
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []

        for file in files where !keepFilenames.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private static func normalizedSourceURL(_ rawValue: String) -> String {
        guard var components = URLComponents(string: rawValue) else {
            return rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }

        components.query = nil
        components.fragment = nil
        var value = components.string?.lowercased() ?? rawValue.lowercased()
        while value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }

    private static func normalizedNote(_ rawNote: String?) -> String? {
        guard let rawNote else { return nil }
        let note = String(rawNote.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
        return note.isEmpty ? nil : note
    }

    private static func storageURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("History", isDirectory: true)
            .appendingPathComponent("recent-saves-v2.json")
    }
}
