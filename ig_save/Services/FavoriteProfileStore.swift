import Foundation

enum FavoriteProfileStore {
    static let maximumCount = 30

    static func load() -> [FavoriteProfile] {
        guard
            let data = try? Data(contentsOf: storageURL()),
            let profiles = try? JSONDecoder().decode([FavoriteProfile].self, from: data)
        else {
            return []
        }
        return Array(profiles.sorted { $0.addedAt < $1.addedAt }.prefix(maximumCount))
    }

    static func persist(_ profiles: [FavoriteProfile]) {
        guard let data = try? JSONEncoder().encode(Array(profiles.prefix(maximumCount))) else {
            return
        }
        let url = storageURL()
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    static func applyingSnapshot(
        username: String,
        currentPostIDs: Set<String>,
        to profiles: [FavoriteProfile],
        now: Date = Date()
    ) -> FavoriteProfileSnapshotResult {
        guard let index = profiles.firstIndex(where: {
            $0.username.caseInsensitiveCompare(username) == .orderedSame
        }) else {
            return FavoriteProfileSnapshotResult(profiles: profiles, newContentIDs: [])
        }

        var updated = profiles
        let previousIDs = updated[index].lastKnownPostIDs
        let newContentIDs = previousIDs.isEmpty ? [] : currentPostIDs.subtracting(previousIDs)
        updated[index].lastKnownPostIDs = currentPostIDs
        updated[index].unseenPostIDs.formUnion(newContentIDs)
        updated[index].lastCheckedAt = now

        return FavoriteProfileSnapshotResult(
            profiles: updated,
            newContentIDs: newContentIDs
        )
    }

    static func markingSeen(
        username: String,
        postIDs: Set<String>? = nil,
        in profiles: [FavoriteProfile]
    ) -> [FavoriteProfile] {
        guard let index = profiles.firstIndex(where: {
            $0.username.caseInsensitiveCompare(username) == .orderedSame
        }) else {
            return profiles
        }

        var updated = profiles
        if let postIDs {
            updated[index].unseenPostIDs.subtract(postIDs)
        } else {
            updated[index].unseenPostIDs.removeAll()
        }
        return updated
    }

    private static func storageURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Profiles", isDirectory: true)
            .appendingPathComponent("favorite-profiles-v1.json")
    }
}

struct FavoriteProfileSnapshotResult: Equatable, Sendable {
    let profiles: [FavoriteProfile]
    let newContentIDs: Set<String>
}
