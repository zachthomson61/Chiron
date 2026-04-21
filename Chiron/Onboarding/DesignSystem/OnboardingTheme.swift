//
//  OnboardingTheme.swift
//  Chiron
//
//  Dark-first onboarding theme. Warm off-black canvas with a purple→blue accent
//  gradient used on hero numbers, progress bars, and highlighted CTAs.
//

import SwiftUI

enum OnboardingTheme {

    // MARK: - Surfaces

    /// Warm off-black canvas. Softer than pure black, matches Opal.
    static let canvas = Color(red: 0x0E / 255, green: 0x0E / 255, blue: 0x10 / 255)

    /// Option row / card surface.
    static let surface = Color(red: 0x1A / 255, green: 0x1A / 255, blue: 0x1D / 255)

    /// Slight elevation over the canvas for inner cards.
    static let surfaceElevated = Color(red: 0x22 / 255, green: 0x22 / 255, blue: 0x26 / 255)

    // MARK: - Text

    /// White primary text.
    static let textPrimary = Color.white

    /// #9A9AA2 — secondary text for subtitles, captions.
    static let textSecondary = Color(red: 0x9A / 255, green: 0x9A / 255, blue: 0xA2 / 255)

    /// Muted tertiary for inactive markers.
    static let textTertiary = Color(red: 0x5E / 255, green: 0x5E / 255, blue: 0x66 / 255)

    // MARK: - Strokes

    /// #2A2A2F — 1pt stroke for unselected option rows.
    static let stroke = Color(red: 0x2A / 255, green: 0x2A / 255, blue: 0x2F / 255)

    // MARK: - Accent

    /// Purple start for the brand gradient.
    static let accentStart = Color(red: 0x7B / 255, green: 0x61 / 255, blue: 0xFF / 255)

    /// Blue end for the brand gradient.
    static let accentEnd = Color(red: 0x4F / 255, green: 0xA8 / 255, blue: 0xFF / 255)

    /// The signature purple→blue accent gradient.
    static let accentGradient = LinearGradient(
        colors: [accentStart, accentEnd],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Low-opacity wash of the accent gradient, used for selected-state inner glow.
    static let accentGlow = LinearGradient(
        colors: [accentStart.opacity(0.18), accentEnd.opacity(0.10)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Motion

    /// Spring used for selection animations across the flow.
    static let selectionSpring = Animation.spring(response: 0.35, dampingFraction: 0.75)

    /// Horizontal slide+fade transition between screens. Kept for callers that
    /// don't have directional context; prefer `screenTransition(forward:)` when
    /// the navigation direction is known.
    static let screenTransition: AnyTransition = screenTransition(forward: true)

    /// Direction-aware slide+fade. Forward navigation: new screen slides in from
    /// the trailing edge; old screen slides off to leading. Backward navigation
    /// mirrors it so the motion matches user intent.
    static func screenTransition(forward: Bool) -> AnyTransition {
        let incomingEdge: Edge = forward ? .trailing : .leading
        let outgoingEdge: Edge = forward ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: incomingEdge).combined(with: .opacity),
            removal: .move(edge: outgoingEdge).combined(with: .opacity)
        )
    }

    // MARK: - Metrics

    static let screenHorizontalPadding: CGFloat = 24
    static let optionRowHeight: CGFloat = 64
    static let ctaHeight: CGFloat = 56
    static let cornerRadiusLarge: CGFloat = 20
    static let cornerRadiusPill: CGFloat = 32
}
