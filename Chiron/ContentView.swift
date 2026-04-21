import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var userProfile: ChironUserProfile? = UserDefaultsUserProfileStore().load()

    var body: some View {
        if userProfile != nil {
            RootTabView()
                .environmentObject(appState.planStore)
                .modelContainer(appState.modelContainer)
                #if DEBUG
                .overlay(debugResetButton, alignment: .topTrailing)
                #endif
        } else {
            OnboardingRootView(store: UserDefaultsUserProfileStore()) { profile in
                userProfile = profile
            }
        }
    }

    #if DEBUG
    private var debugResetButton: some View {
        Button(action: resetOnboarding) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.red)
                .padding(12)
                .background(Color.black.opacity(0.6))
                .clipShape(Circle())
        }
        .padding(12)
    }

    private func resetOnboarding() {
        UserDefaultsUserProfileStore().clear()
        userProfile = nil
    }
    #endif
}

#Preview {
    let appState = AppState()
    ContentView()
        .environmentObject(appState)
        .modelContainer(appState.modelContainer)
}
