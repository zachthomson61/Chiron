//
//  OnboardingTypography.swift
//  Chiron
//
//  Reusable text styles for the onboarding flow. SF Pro for body copy,
//  New York (serif) for the single hero reveal number.
//

import SwiftUI

enum OnboardingTypography {

    /// 30pt semibold SF Pro. Used for the question title on every step.
    static func questionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 30, weight: .semibold, design: .default))
            .lineSpacing(36 - 30)
            .foregroundStyle(OnboardingTheme.textPrimary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// 16pt regular SF Pro, secondary color. Subtitle under the question.
    static func subtitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 16, weight: .regular))
            .foregroundStyle(OnboardingTheme.textSecondary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Option row label.
    static func optionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(OnboardingTheme.textPrimary)
    }

    /// Option row secondary descriptor (used on coach persona cards).
    static func optionDescriptor(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(OnboardingTheme.textSecondary)
    }

    /// CTA label — 17pt semibold, tight.
    static func ctaLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 17, weight: .semibold))
    }

    /// ~72pt New York serif with the accent gradient as foreground.
    /// Use for the single hero reveal number only.
    static func heroNumber(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 72, weight: .semibold, design: .serif))
            .foregroundStyle(OnboardingTheme.accentGradient)
    }
}
