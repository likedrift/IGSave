import Foundation

extension Notification.Name {
    nonisolated static let igSavePendingImport = Notification.Name("ig-save-pending-import")
}

enum PendingImportStore {
    private nonisolated static let key = "pending-import-links-v1"

    nonisolated static func add(_ link: String) {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var links = UserDefaults.standard.stringArray(forKey: key) ?? []
        links.append(trimmed)
        UserDefaults.standard.set(Array(links.suffix(20)), forKey: key)
        NotificationCenter.default.post(name: .igSavePendingImport, object: nil)
    }

    nonisolated static func consumeAll() -> [String] {
        let links = UserDefaults.standard.stringArray(forKey: key) ?? []
        UserDefaults.standard.removeObject(forKey: key)
        return links
    }
}
