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

    /// First-month coached-set estimate derived from the user's experience level.
    /// Honest heuristic: avg sessions/week × sets/session × 4 weeks.
    /// - New to lifting: 2 sessions × 10 sets = 20/week → 80
    /// - Some experience: 3 × 14 = 42/week → 168
    /// - Experienced: 4 × 18 = 72/week → 288
    private var coachedSets: Int {
        switch coordinator.draft.experienceLevel {
        case .newToLifting:     return 80
        case .someExperience:   return 168
        case .experienced:      return 288
        case .none:             return 120
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

                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    OnboardingTypography.heroNumber("~\(coachedSets)")

                    Text("high-quality sets")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(OnboardingTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
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
        "You won't just work out; you'll train with intent."
    }

    private var supportingPoints: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What this means for you:")
                .font(.system(size: 13, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(OnboardingTheme.textSecondary)

            revealBullet(
                icon: "target",
                title: "Every rep counts",
                detail: "Form tracked and scored automatically — no wasted effort."
            )
            revealBullet(
                icon: "bolt.fill",
                title: "Fix mistakes instantly",
                detail: "Get real-time cues so you improve while you train."
            )
            revealBullet(
                icon: "lock.fill",
                title: "Train with confidence",
                detail: "Private, on-device coaching — no recordings, no uploads."
            )
        }
        .padding(.top, 4)
    }

    private func revealBullet(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(OnboardingTheme.accentGradient)
                .frame(width: 20)
                .padding(.top, 3)

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
