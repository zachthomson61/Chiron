import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("has_completed_onboarding") private var hasCompletedOnboarding = false

    var body: some View {
        if hasCompletedOnboarding {
            // Inject only the dependencies the tabs actually use to avoid unnecessary initialization.
            RootTabView()
                .environmentObject(appState.planStore)
                .modelContainer(appState.modelContainer)
        } else {
            OnboardingFlowView()
        }
    }
}

#Preview {
    let appState = AppState()
    return ContentView()
        .environmentObject(appState)
        .modelContainer(appState.modelContainer)
}
