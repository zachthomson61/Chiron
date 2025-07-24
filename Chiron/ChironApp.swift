//
//  ChironApp.swift
//  Chiron
//
//  Created by Zach Thomson on 7/23/25.
//

import SwiftUI

@main
struct ChironApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
