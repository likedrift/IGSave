//
//  ig_saveApp.swift
//  ig_save
//
//  Created by yank on 2026/5/4.
//

import SwiftUI
import UIKit

final class IGSaveAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == BackgroundDownloadCoordinator.sessionIdentifier else {
            completionHandler()
            return
        }

        BackgroundDownloadCoordinator.shared.setBackgroundEventsCompletionHandler(completionHandler)
    }
}

@main
struct IGSaveApp: App {
    @UIApplicationDelegateAdaptor(IGSaveAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
