import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var userProfile: ChironUserProfile? = UserDefaultsUserProfileStore().load()

    var body: some View {
        if userProfile != nil {
            RootTabView()
                .modelContainer(appState.modelContainer)
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
        // Onboarding completion unlocks the "Profile Complete" badge — fired
        // here so the celebration lands on the very first screen the user
        // sees after finishing the flow.
        BadgeCenter.shared.markProfileComplete()
    }

}

#Preview {
    let appState = AppState()
    ContentView()
        .environmentObject(appState)
        .modelContainer(appState.modelContainer)
}
