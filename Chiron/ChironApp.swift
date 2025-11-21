//
//  ChironApp.swift
//  Chiron
//
//  Created by Zach Thomson on 7/23/25.
//

import SwiftUI
import SwiftData

/// Entry point for the iOS app. Keeps startup work minimal so the first screen appears quickly.
@main
struct ChironApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
    }
}

/// Central app state for data dependencies. Heavy services are lazily created on demand.
@MainActor
class AppState: ObservableObject {
    lazy var planStore = PlanStore()
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
