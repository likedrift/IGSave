import Foundation

enum AppPreferences {
    static let dedicatedAlbumKey = "save-to-dedicated-album"
    static let previewBeforeSavingKey = "preview-before-saving"
    static let duplicateProtectionKey = "duplicate-protection"
    static let cellularDownloadsKey = "allow-cellular-downloads"
    static let completionNotificationsKey = "completion-notifications"
    static let dedicatedAlbumName = "IGSave"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            previewBeforeSavingKey: true,
            duplicateProtectionKey: true,
            cellularDownloadsKey: true,
            completionNotificationsKey: true
        ])
    }

    static var usesDedicatedAlbum: Bool {
        UserDefaults.standard.bool(forKey: dedicatedAlbumKey)
    }

    static var previewsBeforeSaving: Bool {
        UserDefaults.standard.bool(forKey: previewBeforeSavingKey)
    }

    static var protectsAgainstDuplicates: Bool {
        UserDefaults.standard.bool(forKey: duplicateProtectionKey)
    }

    static var allowsCellularDownloads: Bool {
        UserDefaults.standard.bool(forKey: cellularDownloadsKey)
    }

    static var sendsCompletionNotifications: Bool {
        UserDefaults.standard.bool(forKey: completionNotificationsKey)
    }
}
