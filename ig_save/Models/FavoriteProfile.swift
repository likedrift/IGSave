import Foundation

struct FavoriteProfile: Identifiable, Codable, Equatable, Sendable {
    var id: String { username.lowercased() }
    let username: String
    let addedAt: Date
    var lastKnownPostIDs: Set<String>
    var unseenPostIDs: Set<String>
    var lastCheckedAt: Date?

    init(
        username: String,
        addedAt: Date = Date(),
        lastKnownPostIDs: Set<String> = [],
        unseenPostIDs: Set<String> = [],
        lastCheckedAt: Date? = nil
    ) {
        self.username = username
        self.addedAt = addedAt
        self.lastKnownPostIDs = lastKnownPostIDs
        self.unseenPostIDs = unseenPostIDs
        self.lastCheckedAt = lastCheckedAt
    }

    private enum CodingKeys: String, CodingKey {
        case username
        case addedAt
        case lastKnownPostIDs
        case unseenPostIDs
        case lastCheckedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        username = try container.decode(String.self, forKey: .username)
        addedAt = try container.decode(Date.self, forKey: .addedAt)
        lastKnownPostIDs = try container.decodeIfPresent(Set<String>.self, forKey: .lastKnownPostIDs) ?? []
        unseenPostIDs = try container.decodeIfPresent(Set<String>.self, forKey: .unseenPostIDs) ?? []
        lastCheckedAt = try container.decodeIfPresent(Date.self, forKey: .lastCheckedAt)
    }
}
