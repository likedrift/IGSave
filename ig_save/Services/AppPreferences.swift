import Foundation

enum AppPreferences {
    nonisolated static let currentOnboardingVersion = 1
    static let dedicatedAlbumKey = "save-to-dedicated-album"
    static let previewBeforeSavingKey = "preview-before-saving"
    static let duplicateProtectionKey = "duplicate-protection"
    static let cellularDownloadsKey = "allow-cellular-downloads"
    static let completionNotificationsKey = "completion-notifications"
    static let hapticFeedbackKey = "haptic-feedback"
    static let onboardingVersionKey = "onboarding-version"
    static let dedicatedAlbumName = "IGSave"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            previewBeforeSavingKey: true,
            duplicateProtectionKey: true,
            cellularDownloadsKey: true,
            completionNotificationsKey: true,
            hapticFeedbackKey: true
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

    static var usesHapticFeedback: Bool {
        UserDefaults.standard.bool(forKey: hapticFeedbackKey)
    }

    nonisolated static func shouldPresentOnboarding(
        storedVersion: Int,
        hasExistingContent: Bool
    ) -> Bool {
        storedVersion < currentOnboardingVersion && !hasExistingContent
    }
}
