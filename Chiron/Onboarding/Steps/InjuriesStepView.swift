//
//  InjuriesStepView.swift
//  Chiron
//
//  Step 6 — binary gate. "Do you have any joint or injury concerns?" Yes branches
//  into three follow-up screens (location, limitation, movements); No skips them.
//

import SwiftUI

struct InjuriesStepView: View {
    @Bindable var coordinator: ChironOnboardingCoordinator

    var body: some View {
        OnboardingScreenScaffold(
            title: "Any injuries or joint concerns?",
            subtitle: "We'll hold back cues that could push a flagged joint or aggravate a known issue.",
            ctaTitle: "Continue",
            ctaEnabled: coordinator.draft.hasInjuryConcerns != nil,
            currentStep: coordinator.progressStepIndex,
            totalSteps: coordinator.totalProgressSteps,
            onContinue: { coordinator.advance() },
            onBack: { coordinator.goBack() }
        ) {
            VStack(spacing: 12) {
                OnboardingOptionRow(
                    title: "Yes",
                    icon: "exclamationmark.triangle.fill",
                    isSelected: coordinator.draft.hasInjuryConcerns == true
                ) {
                    coordinator.draft.hasInjuryConcerns = true
                }

                OnboardingOptionRow(
                    title: "No",
                    icon: "checkmark.seal.fill",
                    isSelected: coordinator.draft.hasInjuryConcerns == false
                ) {
                    coordinator.draft.hasInjuryConcerns = false
                    // Clear any previously-set injury detail so "No" means no.
                    coordinator.draft.injuryFlags = []
                    coordinator.draft.injuryOtherDescription = ""
                    coordinator.draft.movementLimitation = nil
                    coordinator.draft.discomfortMovements = []
                }
            }
        }
    }
}

#Preview("Empty") {
    InjuriesStepView(coordinator: ChironOnboardingCoordinator(store: InMemoryUserProfileStore()))
}

#Preview("Yes selected") {
    let coordinator: ChironOnboardingCoordinator = {
        let c = ChironOnboardingCoordinator(store: InMemoryUserProfileStore())
        c.draft.hasInjuryConcerns = true
        return c
    }()
    InjuriesStepView(coordinator: coordinator)
}
