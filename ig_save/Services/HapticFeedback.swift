import Foundation

#if canImport(UIKit)
import UIKit
#endif

enum HapticFeedback {
    static func selection() {
        #if canImport(UIKit)
        guard AppPreferences.usesHapticFeedback else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }

    static func success() {
        #if canImport(UIKit)
        guard AppPreferences.usesHapticFeedback else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    static func warning() {
        #if canImport(UIKit)
        guard AppPreferences.usesHapticFeedback else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }
}
