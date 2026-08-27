import Foundation

extension Notification.Name {
    nonisolated static let igSavePendingImport = Notification.Name("ig-save-pending-import")
}

enum PendingImportStore {
    private nonisolated static let appGroupIdentifier = "group.com.haru.ig-save"
    private nonisolated static let key = "pending-import-links-v1"

    private nonisolated static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }

    nonisolated static func add(_ link: String) {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var links = sharedDefaults.stringArray(forKey: key) ?? []
        links.append(trimmed)
        sharedDefaults.set(Array(links.suffix(20)), forKey: key)
        NotificationCenter.default.post(name: .igSavePendingImport, object: nil)
    }

    nonisolated static func consumeAll() -> [String] {
        let sharedLinks = sharedDefaults.stringArray(forKey: key) ?? []
        let legacyLinks = UserDefaults.standard.stringArray(forKey: key) ?? []
        sharedDefaults.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: key)
        return sharedLinks + legacyLinks
    }
}
