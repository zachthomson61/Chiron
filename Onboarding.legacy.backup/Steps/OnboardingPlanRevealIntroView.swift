import SwiftUI

// MARK: - Screen 04: Plan Reveal Intro

struct OnboardingPlanRevealIntroView: View, OnboardingScreen {
    let screenId = "screen_04"
    @ObservedObject var coordinator: OnboardingCoordinator

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Spacer().frame(height: 24)

                    Text("Your plan is taking shape")
                        .font(.neueMontrealBold(size: 28))
                        .foregroundColor(Color.pureWhite)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 16)

                    Text("We're building this as you go. Every answer sharpens what we create for you.")
                        .font(.neueMontrealRegular(size: 17))
                        .foregroundColor(Color.textSecondary)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 16)

                    Spacer()
                }
            }

            OnboardingCTAButton(title: "Keep building") {
                coordinator.showAffirmationToast("You're already ahead.", forScreen: screenId)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    coordinator.completeScreen(screenId)
                }
            }
            .padding(.bottom, 16)
        }
        .accessibilityHint("Your personalized plan card is now visible. All fields are blurred and will fill in as you answer more questions. Tap 'Keep building' to continue.")
    }
}
