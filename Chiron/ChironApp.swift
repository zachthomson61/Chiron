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
    
    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
