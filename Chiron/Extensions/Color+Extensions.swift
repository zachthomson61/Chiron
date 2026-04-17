import SwiftUI
#if os(iOS)
import UIKit

extension Color {
    // MARK: - Custom Purple Color Palette
    
    /// Primary Purple - Deep Purple (#6B46C1)
    static let primaryPurple = Color(red: 107/255, green: 70/255, blue: 193/255)
    
    /// Secondary Purple - Amethyst (#A855F7)
    static let secondaryPurple = Color(red: 168/255, green: 85/255, blue: 247/255)
    
    /// Soft Black (#1F2937)
    static let softBlack = Color(red: 31/255, green: 41/255, blue: 55/255)
    
    /// Pure White (#FFFFFF)
    static let pureWhite = Color(red: 255/255, green: 255/255, blue: 255/255)
    
    // MARK: - Semantic Colors
    
    /// Primary accent color (using primary purple)
    static let accent = primaryPurple
    
    /// Background color (using soft black)
    static let background = softBlack
    
    /// Text color (using pure white)
    static let textPrimary = pureWhite
    
    /// Secondary text color (using gray)
    static let textSecondary = Color.gray
    
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