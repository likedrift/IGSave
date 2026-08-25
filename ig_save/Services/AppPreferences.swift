import Foundation

enum AppPreferences {
    static let dedicatedAlbumKey = "save-to-dedicated-album"
    static let dedicatedAlbumName = "IG Save"

    static var usesDedicatedAlbum: Bool {
        UserDefaults.standard.bool(forKey: dedicatedAlbumKey)
    }
}
