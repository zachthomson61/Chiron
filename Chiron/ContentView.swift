import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        // Inject only the dependencies the tabs actually use to avoid unnecessary initialization.
        RootTabView()
            .environmentObject(appState.planStore)
            .modelContainer(appState.modelContainer)
    }
}

#Preview {
    let appState = AppState()
    return ContentView()
        .environmentObject(appState)
        .modelContainer(appState.modelContainer)
}
