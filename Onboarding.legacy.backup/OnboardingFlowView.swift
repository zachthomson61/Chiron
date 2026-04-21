import SwiftUI

// MARK: - Onboarding Flow View (Router / Container)

struct OnboardingFlowView: View {
    @StateObject private var coordinator = OnboardingCoordinator()
    @State private var showExitConfirmation = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Background
            Color.softBlack
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress bar
                progressBar

                // Navigation header
                navigationHeader

                // Screen content
                screenContent

                // Plan reveal card (visible from screen_04 onward)
                if coordinator.isPlanCardVisible {
                    PlanRevealCardView(
                        revealProgress: coordinator.planRevealProgress,
                        fields: coordinator.planFields,
                        isComplete: coordinator.planRevealProgress >= 1.0
                    )
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .move(edge: .bottom).combined(with: .opacity)
                    )
                    .padding(.bottom, 16)
                }
            }

            // Affirmation toast overlay
            VStack {
                AffirmationToastView(
                    text: coordinator.affirmationText,
                    isVisible: $coordinator.showAffirmation
                )
                .padding(.top, 8)
                Spacer()
            }
            .animation(
                reduceMotion ? .none : .easeOut(duration: 0.15),
                value: coordinator.showAffirmation
            )
        }
        .alert("Leave onboarding?", isPresented: $showExitConfirmation) {
            Button("Stay", role: .cancel) { }
            Button("Leave", role: .destructive) {
                // Mark as completed without full setup
                UserDefaults.standard.set(true, forKey: "has_completed_onboarding")
            }
        } message: {
            Text("Your progress will be saved. You can restart onboarding from settings.")
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 2)

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.primaryPurple, Color.secondaryPurple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(
                        width: geometry.size.width * coordinator.progress,
                        height: 2
                    )
                    .animation(
                        reduceMotion ? .none : .easeInOut(duration: 0.28),
                        value: coordinator.progress
                    )
            }
        }
        .frame(height: 2)
        .accessibilityElement()
        .accessibilityLabel("Onboarding progress")
        .accessibilityValue("\(Int(coordinator.progress * 100)) percent")
    }

    // MARK: - Navigation Header

    private var navigationHeader: some View {
        HStack {
            // Back button
            Button(action: {
                withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.28)) {
                    coordinator.goBack()
                }
            }) {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .foregroundColor(Color.pureWhite)
                    .frame(width: 44, height: 44)
            }
            .disabled(!coordinator.canGoBack)
            .opacity(coordinator.canGoBack ? 1.0 : 0.3)
            .accessibilityLabel("Go back")
            .accessibilityHint("Return to the previous screen")

            Spacer()

            // Exit button
            Button(action: {
                showExitConfirmation = true
            }) {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundColor(Color.pureWhite)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Exit onboarding")
            .accessibilityHint("Leave the onboarding flow")
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }

    // MARK: - Screen Content

    @ViewBuilder
    private var screenContent: some View {
        let transition: AnyTransition = {
            if reduceMotion {
                return .opacity
            }
            if coordinator.isTransitioningForward {
                return .opacity.combined(with: .move(edge: .trailing))
            } else {
                return .opacity.combined(with: .move(edge: .leading))
            }
        }()

        Group {
            switch coordinator.currentScreen {
            case .screen_01:
                OnboardingIdentityHookView(coordinator: coordinator)
            case .screen_02:
                OnboardingExperienceGateView(coordinator: coordinator)
            case .screen_03:
                OnboardingActivityFrequencyView(coordinator: coordinator)
            case .screen_04:
                OnboardingPlanRevealIntroView(coordinator: coordinator)
            case .screen_05:
                OnboardingGoalSelectView(coordinator: coordinator)
            case .screen_06:
                OnboardingGoalOverflowView(coordinator: coordinator)
            case .screen_07:
                OnboardingTrainingDurationView(coordinator: coordinator)
            case .screen_08:
                OnboardingTrainingEnvironmentView(coordinator: coordinator)
            case .screen_09:
                OnboardingLiteracyCalibrationView(coordinator: coordinator)
            case .screen_10:
                OnboardingSquatExperienceView(coordinator: coordinator)
            case .screen_11:
                OnboardingMotivationView(coordinator: coordinator)
            case .screen_12:
                OnboardingBarrierView(coordinator: coordinator)
            case .screen_13:
                OnboardingInjuryConcernView(coordinator: coordinator)
            case .screen_14:
                OnboardingPrePermissionView(coordinator: coordinator)
            case .screen_15:
                OnboardingCameraPermissionView(coordinator: coordinator)
            case .screen_16:
                OnboardingCompletionView(coordinator: coordinator)
            }
        }
        .transition(transition)
        .animation(
            reduceMotion ? .none : .easeInOut(duration: 0.28),
            value: coordinator.currentScreenIndex
        )
        .id(coordinator.currentScreen)
    }
}

// MARK: - Shared Option Card

struct OnboardingOptionCard: View {
    let text: String
    let isSelected: Bool
    let isDimmed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(text)
                    .font(.neueMontrealRegular(size: 17))
                    .foregroundColor(Color.pureWhite)
                    .multilineTextAlignment(.leading)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Color.primaryPurple)
                        .font(.system(size: 20))
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(
                isSelected
                    ? Color.primaryPurple.opacity(0.1)
                    : Color.white.opacity(0.06)
            )
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isSelected ? Color.primaryPurple : Color.clear,
                        lineWidth: 2
                    )
            )
            .opacity(isDimmed ? 0.5 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(text)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Shared Option Card with Helper Text

struct OnboardingOptionCardWithHelper: View {
    let text: String
    let helper: String
    let isSelected: Bool
    let isDimmed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(text)
                        .font(.neueMontrealRegular(size: 17))
                        .foregroundColor(Color.pureWhite)
                    Text(helper)
                        .font(.neueMontrealRegular(size: 13))
                        .foregroundColor(Color.textSecondary)
                }
                .multilineTextAlignment(.leading)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Color.primaryPurple)
                        .font(.system(size: 20))
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .background(
                isSelected
                    ? Color.primaryPurple.opacity(0.1)
                    : Color.white.opacity(0.06)
            )
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isSelected ? Color.primaryPurple : Color.clear,
                        lineWidth: 2
                    )
            )
            .opacity(isDimmed ? 0.5 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel("\(text). \(helper)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Shared CTA Button

struct OnboardingCTAButton: View {
    let title: String
    let action: () -> Void
    let isEnabled: Bool

    init(title: String, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.isEnabled = isEnabled
        self.action = action
    }

    var body: some View {
        Button(action: {
            guard isEnabled else { return }
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            action()
        }) {
            Text(title)
                .font(.neueMontrealSemiBold(size: 17))
                .foregroundColor(Color.pureWhite)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    LinearGradient(
                        colors: [Color.primaryPurple, Color.secondaryPurple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(28)
                .opacity(isEnabled ? 1.0 : 0.5)
        }
        .disabled(!isEnabled)
        .padding(.horizontal, 16)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Preview

#if DEBUG
struct OnboardingFlowView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingFlowView()
    }
}
#endif
