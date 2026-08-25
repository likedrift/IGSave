import Foundation

struct FavoriteProfile: Identifiable, Codable, Equatable, Sendable {
    var id: String { username.lowercased() }
    let username: String
    let addedAt: Date
    var lastKnownPostIDs: Set<String>

    init(username: String, addedAt: Date = Date(), lastKnownPostIDs: Set<String> = []) {
        self.username = username
        self.addedAt = addedAt
        self.lastKnownPostIDs = lastKnownPostIDs
    }
}
