//
//  DiscomfortMovementsStepView.swift
//  Chiron
//
//  Step 6d — which movement patterns cause discomfort. Multi-select. Feeds the
//  coaching layer's cue-suppression list.
//

import SwiftUI

struct DiscomfortMovementsStepView: View {
    @Bindable var coordinator: ChironOnboardingCoordinator

    var body: some View {
        OnboardingScreenScaffold(
            title: "Which movements cause discomfort?",
            subtitle: "Select every pattern that's affected. We'll avoid pushing you on those cues during your first month.",
            ctaTitle: "Continue",
            ctaEnabled: !coordinator.draft.discomfortMovements.isEmpty,
            currentStep: coordinator.progressStepIndex,
            totalSteps: coordinator.totalProgressSteps,
            onContinue: { coordinator.advance() },
            onBack: { coordinator.goBack() }
        ) {
            VStack(spacing: 10) {
                ForEach(DiscomfortMovement.allCases) { movement in
                    OnboardingOptionRow(
                        title: movement.displayName,
                        icon: movement.iconName,
                        isMultiSelect: true,
                        isSelected: coordinator.draft.discomfortMovements.contains(movement)
                    ) {
                        toggle(movement)
                    }
                }
            }
        }
    }

    private func toggle(_ movement: DiscomfortMovement) {
        var set = coordinator.draft.discomfortMovements
        if set.contains(movement) {
            set.remove(movement)
        } else {
            set.insert(movement)
        }
        coordinator.draft.discomfortMovements = set
    }
}

#Preview {
    let coordinator: ChironOnboardingCoordinator = {
        let c = ChironOnboardingCoordinator(store: InMemoryUserProfileStore())
        c.draft.hasInjuryConcerns = true
        c.draft.discomfortMovements = [.squatting, .hinging]
        return c
    }()
    DiscomfortMovementsStepView(coordinator: coordinator)
}
