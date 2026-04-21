//
//  HeightWeightStepView.swift
//  Chiron
//
//  Step 5 — height and weight dual wheel pickers with an Imperial/Metric toggle.
//  Metric is the internal source of truth; imperial is a display projection.
//

import SwiftUI

struct HeightWeightStepView: View {
    @Bindable var coordinator: ChironOnboardingCoordinator

    // Imperial-side state (display only). Metric values on the draft are authoritative.
    @State private var feet: Int = 5
    @State private var inches: Int = 10
    @State private var pounds: Int = 175

    // Metric-side state.
    @State private var cm: Int = 178
    @State private var kg: Int = 80

    @State private var didBootstrap = false

    private var ctaEnabled: Bool {
        coordinator.draft.heightCm != nil && coordinator.draft.weightKg != nil
    }

    var body: some View {
        OnboardingScreenScaffold(
            title: "Height and weight",
            subtitle: "Used for baseline volume recommendations. Stored privately on your device.",
            ctaTitle: "Continue",
            ctaEnabled: ctaEnabled,
            currentStep: coordinator.progressStepIndex,
            totalSteps: coordinator.totalProgressSteps,
            onContinue: { coordinator.advance() },
            onBack: { coordinator.goBack() },
            // Wheel pickers own the vertical drag on this screen — don't let
            // the scaffold's ScrollView compete for it.
            scrollable: false
        ) {
            pickerStack
        }
    }

    // MARK: - Body subviews
    //
    // Broken out from `body` to keep the type-checker happy — the chained onChange
    // modifiers on a deeply-nested ViewBuilder can otherwise time out.

    @ViewBuilder
    private var pickerStack: some View {
        VStack(spacing: 24) {
            unitToggle

            HStack(spacing: 16) {
                heightPicker
                weightPicker
            }
            .frame(height: 220)
        }
        .onAppear(perform: bootstrap)
        .onChange(of: coordinator.draft.preferredUnits) { _, _ in syncImperialFromMetric() }
        .onChange(of: feet) { _, _ in commitImperialHeight() }
        .onChange(of: inches) { _, _ in commitImperialHeight() }
        .onChange(of: pounds) { _, _ in commitImperialWeight() }
        .onChange(of: cm) { _, new in coordinator.draft.heightCm = Double(new) }
        .onChange(of: kg) { _, new in coordinator.draft.weightKg = Double(new) }
    }

    // MARK: - Unit Toggle

    private var unitToggle: some View {
        HStack(spacing: 0) {
            ForEach(UnitSystem.allCases) { system in
                unitToggleOption(system)
            }
        }
        .padding(4)
        .background(Capsule().fill(OnboardingTheme.surface))
        .overlay(Capsule().stroke(OnboardingTheme.stroke, lineWidth: 1))
    }

    @ViewBuilder
    private func unitToggleOption(_ system: UnitSystem) -> some View {
        let isActive = coordinator.draft.preferredUnits == system

        Button {
            withAnimation(OnboardingTheme.selectionSpring) {
                coordinator.draft.preferredUnits = system
            }
        } label: {
            Text(system.displayName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isActive ? Color.black : OnboardingTheme.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(unitToggleBackground(isActive: isActive))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func unitToggleBackground(isActive: Bool) -> some View {
        if isActive {
            Capsule().fill(Color.white)
        } else {
            Color.clear
        }
    }

    // MARK: - Pickers

    @ViewBuilder
    private var heightPicker: some View {
        VStack(spacing: 8) {
            Text("Height")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(OnboardingTheme.textSecondary)

            if coordinator.draft.preferredUnits == .imperial {
                HStack(spacing: 0) {
                    WheelColumn(label: "ft", range: Array(3...7), selection: $feet)
                    WheelColumn(label: "in", range: Array(0...11), selection: $inches)
                }
            } else {
                WheelColumn(label: "cm", range: Array(120...220), selection: $cm)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var weightPicker: some View {
        VStack(spacing: 8) {
            Text("Weight")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(OnboardingTheme.textSecondary)

            if coordinator.draft.preferredUnits == .imperial {
                WheelColumn(label: "lb", range: Array(80...400), selection: $pounds)
            } else {
                WheelColumn(label: "kg", range: Array(35...200), selection: $kg)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Conversion

    /// Seed initial state once. If metric values already exist on the draft (user came
    /// back to this screen), rehydrate them; otherwise use plausible defaults.
    private func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true

        if let h = coordinator.draft.heightCm { cm = Int(h.rounded()) }
        if let w = coordinator.draft.weightKg { kg = Int(w.rounded()) }

        syncImperialFromMetric()

        if coordinator.draft.heightCm == nil {
            coordinator.draft.heightCm = Double(cm)
        }
        if coordinator.draft.weightKg == nil {
            coordinator.draft.weightKg = Double(kg)
        }
    }

    private func syncImperialFromMetric() {
        let totalInches = Double(cm) / 2.54
        feet = Int(totalInches / 12)
        inches = Int(totalInches.truncatingRemainder(dividingBy: 12).rounded())
        if inches == 12 { feet += 1; inches = 0 }
        pounds = Int((Double(kg) * 2.2046226218).rounded())
    }

    private func commitImperialHeight() {
        guard coordinator.draft.preferredUnits == .imperial else { return }
        let totalInches = Double(feet) * 12 + Double(inches)
        let newCm = totalInches * 2.54
        cm = Int(newCm.rounded())
        coordinator.draft.heightCm = newCm
    }

    private func commitImperialWeight() {
        guard coordinator.draft.preferredUnits == .imperial else { return }
        let newKg = Double(pounds) / 2.2046226218
        kg = Int(newKg.rounded())
        coordinator.draft.weightKg = newKg
    }
}

// MARK: - Wheel Column

private struct WheelColumn: View {
    let label: String
    let range: [Int]
    @Binding var selection: Int

    var body: some View {
        Picker(label, selection: $selection) {
            ForEach(range, id: \.self) { value in
                Text("\(value) \(label)")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(OnboardingTheme.textPrimary)
                    .tag(value)
            }
        }
        .pickerStyle(.wheel)
        .frame(height: 180)
        .clipped()
    }
}

#Preview("Imperial") {
    HeightWeightStepView(coordinator: ChironOnboardingCoordinator(store: InMemoryUserProfileStore()))
}

#Preview("Metric") {
    let coordinator: ChironOnboardingCoordinator = {
        let c = ChironOnboardingCoordinator(store: InMemoryUserProfileStore())
        c.draft.preferredUnits = .metric
        c.draft.heightCm = 180
        c.draft.weightKg = 82
        return c
    }()
    HeightWeightStepView(coordinator: coordinator)
}
