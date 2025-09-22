//
//  ChironApp.swift
//  Chiron
//
//  Created by Zach Thomson on 7/23/25.
//

import SwiftUI
import FirebaseCore

@main
struct ChironApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var planStore = PlanStore()
    
    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(planStore)
        }
    }
}
