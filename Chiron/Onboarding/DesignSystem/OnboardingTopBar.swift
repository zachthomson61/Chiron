//
//  OnboardingTopBar.swift
//  Chiron
//
//  Back chevron + segmented progress bar. Derived from coordinator state, so
//  the bar stays in sync without the steps knowing each other exist.
//

import SwiftUI

struct OnboardingTopBar: View {
    let currentStep: Int
    let totalSteps: Int
    let canGoBack: Bool
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            backButton
                .opacity(canGoBack ? 1 : 0)
                .allowsHitTesting(canGoBack)

            segmentedProgress

            // Invisible balancer so the progress bar stays centered.
            backButton
                .opacity(0)
                .allowsHitTesting(false)
        }
        .padding(.horizontal, OnboardingTheme.screenHorizontalPadding)
        .padding(.top, 8)
    }

    private var backButton: some View {
        Button(action: onBack) {
            ZStack {
                Circle()
                    .fill(OnboardingTheme.surface)
                    .frame(width: 36, height: 36)
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.textPrimary)
            }
        }
        .buttonStyle(.plain)
    }

    private var segmentedProgress: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 4
            let totalSpacing = spacing * CGFloat(max(totalSteps - 1, 0))
            let segmentWidth = max(0, (proxy.size.width - totalSpacing) / CGFloat(max(totalSteps, 1)))

            HStack(spacing: spacing) {
                ForEach(0..<max(totalSteps, 1), id: \.self) { index in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(OnboardingTheme.stroke)

                        if index < currentStep {
                            Capsule()
                                .fill(OnboardingTheme.accentGradient)
                        }
                    }
                    .frame(width: segmentWidth, height: 4)
                }
            }
            .animation(OnboardingTheme.selectionSpring, value: currentStep)
        }
        .frame(height: 4)
    }
}

#Preview {
    ZStack {
        OnboardingTheme.canvas.ignoresSafeArea()
        VStack {
            OnboardingTopBar(currentStep: 3, totalSteps: 13, canGoBack: true) {}
            Spacer()
        }
    }
}
