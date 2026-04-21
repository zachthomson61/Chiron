//
//  PrimaryCTAButton.swift
//  Chiron
//
//  White pill CTA that lives pinned to the bottom safe area of every onboarding screen.
//  Press-in scale animation, .success haptic on tap, 30% opacity when disabled.
//

import SwiftUI
import UIKit

struct PrimaryCTAButton: View {
    let title: String
    var isEnabled: Bool = true
    var useAccentGradientText: Bool = false
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: fire) {
            ZStack {
                Capsule()
                    .fill(Color.white)

                labelView
            }
            .frame(height: OnboardingTheme.ctaHeight)
            .frame(maxWidth: .infinity)
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .opacity(isEnabled ? 1.0 : 0.3)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressed)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .simultaneousGesture(pressGesture)
    }

    @ViewBuilder
    private var labelView: some View {
        if useAccentGradientText {
            OnboardingTypography.ctaLabel(title)
                .foregroundStyle(OnboardingTheme.accentGradient)
        } else {
            OnboardingTypography.ctaLabel(title)
                .foregroundStyle(Color.black)
        }
    }

    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                if !isPressed { isPressed = true }
            }
            .onEnded { _ in
                isPressed = false
            }
    }

    private func fire() {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        action()
    }
}

#Preview {
    ZStack {
        OnboardingTheme.canvas.ignoresSafeArea()
        VStack(spacing: 16) {
            PrimaryCTAButton(title: "Get Started") {}
            PrimaryCTAButton(title: "Continue", useAccentGradientText: true) {}
            PrimaryCTAButton(title: "Disabled", isEnabled: false) {}
        }
        .padding(.horizontal, 24)
    }
}
