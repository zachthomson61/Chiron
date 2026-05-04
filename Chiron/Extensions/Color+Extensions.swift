import SwiftUI
#if os(iOS)
import UIKit

extension Color {
    // MARK: - Brand colors

    /// Primary purple (#7B61FF) — matches the onboarding accent start.
    static let primaryPurple = Color(red: 0x7B/255, green: 0x61/255, blue: 0xFF/255)

    /// Secondary purple - Amethyst (#A855F7)
    static let secondaryPurple = Color(red: 168/255, green: 85/255, blue: 247/255)

    /// Warm off-black canvas (#0E0E10) — matches onboarding `canvas`.
    static let softBlack = Color(red: 0x0E/255, green: 0x0E/255, blue: 0x10/255)

    /// Pure White (#FFFFFF)
    static let pureWhite = Color(red: 255/255, green: 255/255, blue: 255/255)

    // MARK: - Surfaces

    /// Card / option-row surface (#1A1A1D).
    static let surface = Color(red: 0x1A/255, green: 0x1A/255, blue: 0x1D/255)

    /// Slight elevation over the canvas (#222226) for nested cards.
    static let surfaceElevated = Color(red: 0x22/255, green: 0x22/255, blue: 0x26/255)

    /// 1pt stroke for unselected surfaces (#2A2A2F).
    static let stroke = Color(red: 0x2A/255, green: 0x2A/255, blue: 0x2F/255)

    // MARK: - Semantic colors

    /// Primary accent color (using primary purple)
    static let accent = primaryPurple

    /// Background color (using soft black)
    static let background = softBlack

    /// Text color (using pure white)
    static let textPrimary = pureWhite

    /// Secondary text (#9A9AA2) — tuned for dark surfaces.
    static let textSecondary = Color(red: 0x9A/255, green: 0x9A/255, blue: 0xA2/255)

    // MARK: - Accent gradient

    /// Blue end of the brand gradient (#4FA8FF).
    static let accentBlue = Color(red: 0x4F/255, green: 0xA8/255, blue: 0xFF/255)

    /// Signature purple→blue gradient. Use for hero CTAs and progress rings.
    static let accentGradient = LinearGradient(
        colors: [primaryPurple, accentBlue],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Accent color used for pills and badges in the exercise library.
    static var brandAccentPurple: Color {
        #if os(iOS)
        if let uiColor = UIColor(named: "AccentPurple") {
            return Color(uiColor)
        }
        return Color(red: 91/255, green: 70/255, blue: 242/255)
        #endif
    }

    /// Yellow/amber color for intermediate difficulty badges.
    /// Complements the purple palette and provides visual distinction for intermediate exercises.
    /// Color: #EAB308 (warm yellow/amber)
    static var intermediateYellow: Color {
        Color(red: 234/255, green: 179/255, blue: 8/255)
    }

    // MARK: - Difficulty Badge Colors

    /// Red color for expert difficulty badges in the exercise library.
    /// Complements the purple palette and provides visual distinction for expert exercises.
    /// Color: #DC2626 (deep red/crimson) - chosen to match the app's color palette.
    static var expertRed: Color {
        Color(red: 220/255, green: 38/255, blue: 38/255)
    }

    /// Green color for beginner difficulty badges in the exercise library.
    /// Color: #22C55E — matches the saturation of intermediateYellow/expertRed.
    static var beginnerGreen: Color {
        Color(red: 34/255, green: 197/255, blue: 94/255)
    }

    /// Bright secondary accent used for the Volume series in progression
    /// charts — bar overlay, trailing y-axis numbers, and legend dot all use
    /// this color so the two series (purple = strength, cyan = volume) are
    /// instantly distinguishable.
    /// Color: #22D3EE (cyan-400) — saturated enough to read on dark bg
    /// without competing visually with the primary purple.
    static var volumeAccent: Color {
        Color(red: 34/255, green: 211/255, blue: 238/255)
    }
}
#endif
