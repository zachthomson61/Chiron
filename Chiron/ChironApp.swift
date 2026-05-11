//
//  ChironApp.swift
//  Chiron
//
//  Created by Zach Thomson on 7/23/25.
//

import SwiftUI
import SwiftData
import FirebaseCore
import UIKit

/// Entry point for the iOS app. Keeps startup work minimal so the first screen appears quickly.
@main
struct ChironApp: App {
    @UIApplicationDelegateAdaptor(ChironAppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
    }
}

/// Hosts UIApplication callbacks that SwiftUI's lifecycle doesn't expose:
/// the launch-time telemetry resume/cleanup pass and the background
/// URLSession completion-handler bridge. Kept minimal — anything that can
/// live in `AppState` should live there.
final class ChironAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Re-enqueue any orphaned files from a prior crash, and prune
        // Uploaded/* older than 7 days.
        TelemetryUploader.shared.resumePendingUploads()
        TelemetryUploader.shared.cleanupOldUploaded()

        // Foreground hook: when the user comes back from background — typically
        // after walking out of the gym onto Wi-Fi at home — re-enqueue any
        // Pending/ orphans whose retry timers were lost during suspend. Cold
        // launch already covers itself above; this catches warm relaunches.
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { _ in
            TelemetryUploader.shared.resumePendingUploads()
        }

        return true
    }

    /// iOS calls this when a background URLSession has events to deliver
    /// after the app was relaunched. Forwarding the completion handler lets
    /// the system know when we're done so it can suspend us again.
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        TelemetryUploader.shared.setBackgroundEventsCompletion(completionHandler)
    }
}

/// Central app state for data dependencies. Heavy services are lazily created on demand.
@MainActor
class AppState: ObservableObject {
    lazy var modelContainer: ModelContainer = {
        do {
            return try ModelContainer(for: Exercise.self)
        } catch {
            fatalError("Failed to initialize ModelContainer: \(error)")
        }
    }()
    
    init() {
        // Configure audio session at startup to allow background audio (e.g., Spotify)
        // to continue playing when navigating through the app
        _ = AudioSessionManager.shared
    }
}
