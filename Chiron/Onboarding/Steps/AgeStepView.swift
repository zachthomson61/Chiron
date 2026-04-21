//
//  AgeStepView.swift
//  Chiron
//
//  Step 4 — birth year wheel picker (Cal AI style).
//

import SwiftUI

struct AgeStepView: View {
    @Bindable var coordinator: ChironOnboardingCoordinator

    /// Range of years shown in the wheel. Clamp to plausible human ages so
    /// the picker doesn't scroll through a century of empty noise.
    private let years: [Int] = {
        let currentYear = Calendar.current.component(.year, from: Date())
        return Array((currentYear - 90)...(currentYear - 13)).reversed()
    }()

    private var selectedYear: Binding<Int> {
        Binding(
            get: { coordinator.draft.birthYear ?? defaultYear },
            set: { coordinator.draft.birthYear = $0 }
        )
    }

    /// Default to age 25 so the wheel opens at a plausible middle.
    private var defaultYear: Int {
        Calendar.current.component(.year, from: Date()) - 25
    }

    var body: some View {
        OnboardingScreenScaffold(
            title: "When were you born?",
            subtitle: "Age affects recovery recommendations and realistic progression.",
            ctaTitle: "Continue",
            ctaEnabled: coordinator.draft.birthYear != nil,
            currentStep: coordinator.progressStepIndex,
            totalSteps: coordinator.totalProgressSteps,
            onContinue: { coordinator.advance() },
            onBack: { coordinator.goBack() },
            // The wheel picker owns the vertical drag on this screen — don't
            // let the scaffold's ScrollView compete for it.
            scrollable: false
        ) {
            VStack(spacing: 0) {
                Picker("Birth year", selection: selectedYear) {
                    ForEach(years, id: \.self) { year in
                        Text(String(year))
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(OnboardingTheme.textPrimary)
                            .tag(year)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 220)
                .onAppear {
                    if coordinator.draft.birthYear == nil {
                        coordinator.draft.birthYear = defaultYear
                    }
                }
            }
            .padding(.top, 20)
            .frame(maxWidth: .infinity)
        }
    }
}

#Preview {
    AgeStepView(coordinator: ChironOnboardingCoordinator(store: InMemoryUserProfileStore()))
}
