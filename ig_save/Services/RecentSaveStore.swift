//
//  RecentSaveStore.swift
//  ig_save
//

import Foundation

enum RecentSaveStore {
    private static let storageKey = "recent-saves-v1"
    private static let maxCount = 500

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

    static func removeAll(from saves: [RecentSave]) -> [RecentSave] {
        persist([])
        pruneThumbnails(keeping: [])
        return []
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
        try? data.write(to: url, options: .atomic)
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

    private static func storageURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("History", isDirectory: true)
            .appendingPathComponent("recent-saves-v2.json")
    }
}
