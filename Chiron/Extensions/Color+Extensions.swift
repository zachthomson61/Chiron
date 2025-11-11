import SwiftUI
#if os(iOS)
import UIKit
#endif

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
        #endif
        return Color(red: 91/255, green: 70/255, blue: 242/255)
    }
} 