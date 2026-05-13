//
//  PersonalizedRevealView.swift
//  Chiron
//
//  Step 11 — gradient hero reveal. One number, huge. Everything else recedes.
//  The number is derived from the user's inputs, not fabricated.
//

import SwiftUI

struct PersonalizedRevealView: View {
    @Bindable var coordinator: ChironOnboardingCoordinator

    @State private var appeared = false

    /// Weekly minutes lost to bad-form sets, derived from experience level.
    /// Heuristic: sets/week × 20% junk rate × ~2.5 min/set (work + rest).
    /// - New to lifting: 20/week × 0.2 × 2.5 ≈ 10 min
    /// - Some experience: 42/week × 0.2 × 2.5 ≈ 20 min
    /// - Experienced: 72/week × 0.2 × 2.5 ≈ 35 min
    private var minutesLost: Int {
        switch coordinator.draft.experienceLevel {
        case .newToLifting:     return 10
        case .someExperience:   return 20
        case .experienced:      return 35
        case .none:             return 15
        }
    }

    private var personaName: String {
        coordinator.draft.coachPersona?.displayName ?? "your coach"
    }

    var body: some View {
        OnboardingScreenScaffold(
            ctaTitle: "Looks good",
            ctaEnabled: true,
            currentStep: coordinator.progressStepIndex,
            totalSteps: coordinator.totalProgressSteps,
            onContinue: { coordinator.advance() },
            // Intentionally no back arrow — the reveal follows the loader and
            // the user shouldn't be able to bounce back into the calculating
            // screen (which auto-advances on appear).
            onBack: nil
        ) {
            VStack(alignment: .leading, spacing: 32) {
                Spacer(minLength: 20)

                Text("YOUR FIRST MONTH")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(3)
                    .foregroundStyle(OnboardingTheme.textSecondary)
                    .opacity(appeared ? 1 : 0)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Stop losing")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(OnboardingTheme.textPrimary)

                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        OnboardingTypography.heroNumber("~\(minutesLost)")

                        Text("min/week")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(OnboardingTheme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .scaleEffect(appeared ? 1 : 0.85, anchor: .leading)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1), value: appeared)

                VStack(alignment: .leading, spacing: 20) {
                    narrative
                    supportingPoints
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
                .animation(.easeOut(duration: 0.5).delay(0.35), value: appeared)

                Spacer(minLength: 40)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) {
                appeared = true
            }
        }
    }

    private var narrative: some View {
        Text(narrativeText)
            .font(.system(size: 17, weight: .regular))
            .lineSpacing(4)
            .foregroundStyle(OnboardingTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var narrativeText: String {
        "The average lifter wastes 1 in 5 sets to bad form. You won't."
    }

    private var supportingPoints: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What this means for you:")
                .font(.system(size: 13, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(OnboardingTheme.textSecondary)

            revealBullet(
                emoji: "🎯",
                title: "No junk volume",
                detail: "Every rep is form-scored, in real time."
            )
            revealBullet(
                emoji: "⚡",
                title: "Catch mistakes early",
                detail: "Cues the moment your form breaks down."
            )
            revealBullet(
                emoji: "🔒",
                title: "Private training",
                detail: "On-device only. Nothing uploaded, ever."
            )
        }
        .padding(.top, 4)
    }

    private func revealBullet(emoji: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(emoji)
                .font(.system(size: 18))
                .frame(width: 24, alignment: .leading)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.textPrimary)
                Text(detail)
                    .font(.system(size: 14, weight: .regular))
                    .lineSpacing(2)
                    .foregroundStyle(OnboardingTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    let coordinator: ChironOnboardingCoordinator = {
        let c = ChironOnboardingCoordinator(store: InMemoryUserProfileStore())
        c.draft.topGoal = .buildMuscle
        c.draft.experienceLevel = .someExperience
        c.draft.coachPersona = .technician
        c.draft.coachIntensity = 4
        return c
    }()
    PersonalizedRevealView(coordinator: coordinator)
}
