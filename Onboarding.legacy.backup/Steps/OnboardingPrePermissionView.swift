import SwiftUI

// MARK: - Screen 14: Pre-Permission

struct OnboardingPrePermissionView: View, OnboardingScreen {
    let screenId = "screen_14"
    @ObservedObject var coordinator: OnboardingCoordinator

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Spacer().frame(height: 24)

                    Text("Your plan is almost ready")
                        .font(.neueMontrealBold(size: 28))
                        .foregroundColor(Color.pureWhite)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 16)

                    Text("One thing left to unlock. Chiron coaches you by watching your form through your camera -- in real time, on every rep.")
                        .font(.neueMontrealRegular(size: 17))
                        .foregroundColor(Color.textSecondary)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 16)

                    Spacer()
                }
            }

            OnboardingCTAButton(title: "Unlock my AI coach") {
                coordinator.showAffirmationToast("Here we go.", forScreen: screenId)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    coordinator.completeScreen(screenId)
                }
            }
            .padding(.bottom, 16)
        }
        .accessibilityHint("Your plan is nearly complete. The AI Coach field remains locked. Tap 'Unlock my AI coach' to proceed to camera access.")
    }
}
