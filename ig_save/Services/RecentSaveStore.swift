//
//  RecentSaveStore.swift
//  ig_save
//

import Foundation

enum RecentSaveStore {
    private static let storageKey = "recent-saves-v1"
    private static let maxCount = 5

    static func load() -> [RecentSave] {
        guard
            let data = UserDefaults.standard.data(forKey: storageKey),
            let saves = try? JSONDecoder().decode([RecentSave].self, from: data)
        else {
            return []
        }

        return Array(saves.prefix(maxCount))
    }

    static func add(_ save: RecentSave, to saves: [RecentSave]) -> [RecentSave] {
        let nextSaves = Array(([save] + saves).prefix(maxCount))
        persist(nextSaves)
        pruneThumbnails(keeping: nextSaves)

        return nextSaves
    }

    static func previousSave(for sourceURL: String) -> RecentSave? {
        let key = normalizedSourceURL(sourceURL)
        return load().first { normalizedSourceURL($0.sourceURL) == key }
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

        UserDefaults.standard.set(data, forKey: storageKey)
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
}
