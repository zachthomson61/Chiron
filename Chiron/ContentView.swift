import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var userProfile: ChironUserProfile? = UserDefaultsUserProfileStore().load()

    var body: some View {
        if userProfile != nil {
            RootTabView()
                .modelContainer(appState.modelContainer)
                #if DEBUG
                .overlay(debugResetButton, alignment: .topTrailing)
                #endif
        } else {
            OnboardingRootView(store: UserDefaultsUserProfileStore()) { profile in
                userProfile = profile
                applyOnboardingProfile(profile)
            }
        }
    }

    /// Fans the just-finished onboarding profile out to the rest of the app:
    /// the home-screen primary-goal card reads from `UserPreferencesManager`,
    /// and the coaching manager caches a copy of the profile so its next
    /// `analyzeAndGetNaturalFeedback` call picks up the new values.
    private func applyOnboardingProfile(_ profile: ChironUserProfile) {
        UserPreferencesManager.shared.primaryGoal = profile.topGoal.asPrimaryGoal
        OpenAICoachingManager.shared.refreshProfile()
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
        AccountStore.shared.clear()
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
