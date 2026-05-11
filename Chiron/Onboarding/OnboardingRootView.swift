//
//  OnboardingRootView.swift
//  Chiron
//
//  Entry point for the onboarding flow. Embed at app launch when no
//  ChironUserProfile exists. Owns the ChironOnboardingCoordinator and routes each step.
//

import SwiftUI

/// Embed this view at app launch when `UserProfileStore.load()` returns nil.
///
/// The view owns its coordinator so there's no global state — tearing it down after
/// `onFinish` fires returns the app to a clean state.
struct OnboardingRootView: View {
    @State private var coordinator: ChironOnboardingCoordinator

    /// Fires once with the finalized profile after the user taps "Start My First Session".
    /// The caller typically swaps in the main app view and flips the `has_completed_onboarding` flag.
    let onFinish: (ChironUserProfile) -> Void

    init(
        store: UserProfileStore = UserDefaultsUserProfileStore(),
        onFinish: @escaping (ChironUserProfile) -> Void
    ) {
        let coord = ChironOnboardingCoordinator(store: store)
        coord.onFinish = onFinish
        _coordinator = State(initialValue: coord)
        self.onFinish = onFinish
    }

    var body: some View {
        ZStack {
            OnboardingTheme.canvas.ignoresSafeArea()

            // Horizontal slide + fade transition between every step.
            Group {
                switch coordinator.step {
                case .welcome:
                    WelcomeStepView(coordinator: coordinator)
                case .goal:
                    GoalStepView(coordinator: coordinator)
                case .experience:
                    ExperienceStepView(coordinator: coordinator)
                case .gender:
                    GenderStepView(coordinator: coordinator)
                case .age:
                    AgeStepView(coordinator: coordinator)
                case .heightWeight:
                    HeightWeightStepView(coordinator: coordinator)
                case .injuries:
                    InjuriesStepView(coordinator: coordinator)
                case .injuryLocation:
                    InjuryLocationStepView(coordinator: coordinator)
                case .movementLimitation:
                    MovementLimitationStepView(coordinator: coordinator)
                case .discomfortMovements:
                    DiscomfortMovementsStepView(coordinator: coordinator)
                case .coachInterstitial:
                    CoachInterstitialView(coordinator: coordinator)
                case .coachPersona:
                    CoachPersonaStepView(coordinator: coordinator)
                case .coachIntensity:
                    CoachIntensityStepView(coordinator: coordinator)
                case .calculating:
                    CalculatingLoaderView(coordinator: coordinator)
                case .reveal:
                    PersonalizedRevealView(coordinator: coordinator)
                case .helpImproveChiron:
                    HelpImproveChironPrimerView(coordinator: coordinator)
                case .notificationPrimer:
                    NotificationPrimerView(coordinator: coordinator)
                case .ready:
                    ReadyStepView(coordinator: coordinator)
                }
            }
            .id(coordinator.step)
            .transition(OnboardingTheme.screenTransition(
                forward: coordinator.lastDirection == .forward
            ))
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Preview

#Preview("Full Flow") {
    OnboardingRootView(store: InMemoryUserProfileStore()) { _ in }
}
