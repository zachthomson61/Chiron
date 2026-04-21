//
//  CoachIntensityStepView.swift
//  Chiron
//
//  Step 9 — coaching intensity slider (1...5). Live-updating label and example cue
//  text that cross-fades as the user drags. This is the single most engagement-worthy
//  interaction in the flow — the copy sells the product in one gesture.
//

import SwiftUI
import UIKit

struct CoachIntensityStepView: View {
    @Bindable var coordinator: ChironOnboardingCoordinator

    @State private var sliderValue: Double = 3.0
    @State private var lastHapticStep: Int = 3

    private var currentLevel: CoachIntensityLevel {
        CoachIntensityLevel.from(clamped: Int(sliderValue.rounded()))
    }

    var body: some View {
        OnboardingScreenScaffold(
            title: "How intense should your coach be?",
            subtitle: "Drag the slider. The example cue below will shift as you go.",
            ctaTitle: "Continue",
            ctaEnabled: true,
            currentStep: coordinator.progressStepIndex,
            totalSteps: coordinator.totalProgressSteps,
            onContinue: { coordinator.advance() },
            onBack: { coordinator.goBack() }
        ) {
            VStack(spacing: 32) {
                cuePreview
                    .padding(.top, 8)

                intensityControl
                    .padding(.horizontal, 4)

                levelLabels
                    .padding(.horizontal, 4)
            }
            .onAppear {
                sliderValue = Double(coordinator.draft.coachIntensity)
                lastHapticStep = Int(sliderValue.rounded())
            }
            .onChange(of: sliderValue) { _, new in
                let step = Int(new.rounded())
                if step != lastHapticStep {
                    lastHapticStep = step
                    coordinator.draft.coachIntensity = step
                    UISelectionFeedbackGenerator().selectionChanged()
                }
            }
        }
    }

    // MARK: - Live Cue Preview

    /// Card showing the current level's label + example cue text. Cue text cross-fades
    /// on change — the animation is the feature.
    private var cuePreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(OnboardingTheme.accentGradient)
                    .frame(width: 8, height: 8)
                Text(currentLevel.label.uppercased())
                    .font(.system(size: 12, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(OnboardingTheme.accentGradient)
            }

            Text("\u{201C}\(currentLevel.exampleCue)\u{201D}")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(OnboardingTheme.textPrimary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(currentLevel) // re-identifies the text view so the transition fires
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .animation(.easeInOut(duration: 0.25), value: currentLevel)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: OnboardingTheme.cornerRadiusLarge, style: .continuous)
                .fill(OnboardingTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OnboardingTheme.cornerRadiusLarge, style: .continuous)
                .strokeBorder(OnboardingTheme.stroke, lineWidth: 1)
        )
    }

    // MARK: - Slider

    /// Custom gradient slider. Uses a SwiftUI Slider under the hood for gesture fidelity
    /// but renders its own track + thumb so the gradient and tick marks stay on-brand.
    private var intensityControl: some View {
        GeometryReader { proxy in
            let trackHeight: CGFloat = 6
            let thumbSize: CGFloat = 28
            let usableWidth = proxy.size.width - thumbSize
            let normalized = (sliderValue - 1.0) / 4.0
            let thumbX = CGFloat(normalized) * usableWidth

            ZStack(alignment: .leading) {
                // Base track
                Capsule()
                    .fill(OnboardingTheme.stroke)
                    .frame(height: trackHeight)

                // Filled gradient portion
                Capsule()
                    .fill(OnboardingTheme.accentGradient)
                    .frame(width: thumbX + thumbSize / 2, height: trackHeight)

                // Tick marks for each step
                HStack(spacing: 0) {
                    ForEach(0..<5) { index in
                        Circle()
                            .fill(Color.white.opacity(0.35))
                            .frame(width: 4, height: 4)
                        if index < 4 { Spacer() }
                    }
                }
                .frame(width: usableWidth)
                .offset(x: thumbSize / 2)

                // Thumb
                Circle()
                    .fill(Color.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: Color.black.opacity(0.4), radius: 6, y: 2)
                    .offset(x: thumbX)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let clamped = min(max(value.location.x - thumbSize / 2, 0), usableWidth)
                                let pct = clamped / usableWidth
                                sliderValue = 1.0 + Double(pct) * 4.0
                            }
                            .onEnded { _ in
                                // Snap to nearest integer rung.
                                withAnimation(OnboardingTheme.selectionSpring) {
                                    sliderValue = sliderValue.rounded()
                                }
                            }
                    )
            }
            .frame(height: thumbSize)
        }
        .frame(height: 28)
    }

    // MARK: - Level labels

    private var levelLabels: some View {
        HStack {
            ForEach(CoachIntensityLevel.allCases) { level in
                Text(level.label)
                    .font(.system(size: 11, weight: currentLevel == level ? .semibold : .regular))
                    .foregroundStyle(
                        currentLevel == level
                        ? AnyShapeStyle(OnboardingTheme.accentGradient)
                        : AnyShapeStyle(OnboardingTheme.textTertiary)
                    )
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

#Preview("Default (3)") {
    CoachIntensityStepView(coordinator: ChironOnboardingCoordinator(store: InMemoryUserProfileStore()))
}

#Preview("Relentless (5)") {
    let coordinator: ChironOnboardingCoordinator = {
        let c = ChironOnboardingCoordinator(store: InMemoryUserProfileStore())
        c.draft.coachIntensity = 5
        return c
    }()
    CoachIntensityStepView(coordinator: coordinator)
}
