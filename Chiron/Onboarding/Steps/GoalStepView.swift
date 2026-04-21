//
//  GoalStepView.swift
//  Chiron
//
//  Step 2 — top fitness goal (single-select with icons).
//

import SwiftUI

struct GoalStepView: View {
    @Bindable var coordinator: ChironOnboardingCoordinator

    var body: some View {
        OnboardingScreenScaffold(
            title: "What's your top goal?",
            subtitle: "We'll shape your coaching around this — you can change it later.",
            ctaTitle: "Continue",
            ctaEnabled: coordinator.canAdvance,
            currentStep: coordinator.progressStepIndex,
            totalSteps: coordinator.totalProgressSteps,
            onContinue: { coordinator.advance() },
            onBack: { coordinator.goBack() }
        ) {
            VStack(spacing: 10) {
                ForEach(FitnessGoal.allCases) { goal in
                    OnboardingOptionRow(
                        title: goal.displayName,
                        icon: goal.iconName,
                        isSelected: coordinator.draft.topGoal == goal
                    ) {
                        coordinator.draft.topGoal = goal
                    }
                }
            }
        }
    }
}

#Preview("Empty") {
    GoalStepView(coordinator: ChironOnboardingCoordinator(store: InMemoryUserProfileStore()))
}

#Preview("Selected") {
    let coordinator: ChironOnboardingCoordinator = {
        let c = ChironOnboardingCoordinator(store: InMemoryUserProfileStore())
        c.draft.topGoal = .getStronger
        c.step = .goal
        return c
    }()
    GoalStepView(coordinator: coordinator)
}
