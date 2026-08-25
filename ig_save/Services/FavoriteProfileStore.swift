import Foundation

enum FavoriteProfileStore {
    static func load() -> [FavoriteProfile] {
        guard
            let data = try? Data(contentsOf: storageURL()),
            let profiles = try? JSONDecoder().decode([FavoriteProfile].self, from: data)
        else {
            return []
        }
        return profiles.sorted { $0.addedAt < $1.addedAt }
    }

    static func persist(_ profiles: [FavoriteProfile]) {
        guard let data = try? JSONEncoder().encode(profiles) else {
            return
        }
        let url = storageURL()
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }

    private static func storageURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Profiles", isDirectory: true)
            .appendingPathComponent("favorite-profiles-v1.json")
    }
}
