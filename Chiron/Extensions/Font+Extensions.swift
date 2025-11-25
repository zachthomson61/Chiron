import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Font extension providing Neue Montreal typeface throughout the app.
/// 
/// This extension provides three font weights:
/// - Bold: For headers, titles, and emphasis
/// - SemiBold: For buttons and important interactive elements
/// - Regular: For body text, captions, and general content
///
/// All methods automatically fall back to system fonts if the custom fonts are not available,
/// ensuring the app works even before font files are added to the project.
extension Font {
    // MARK: - Neue Montreal Font Helpers
    
    /// Returns Neue Montreal Bold font at the specified size.
    /// Falls back to system bold font if custom font is not available.
    /// 
    /// - Parameter size: The font size in points
    /// - Returns: A Font using Neue Montreal Bold, or system bold as fallback
    static func neueMontrealBold(size: CGFloat) -> Font {
        #if os(iOS)
        // Try common font naming conventions
        if UIFont(name: "NeueMontreal-Bold", size: size) != nil {
            return .custom("NeueMontreal-Bold", size: size)
        }
        if UIFont(name: "Neue Montreal Bold", size: size) != nil {
            return .custom("Neue Montreal Bold", size: size)
        }
        #endif
        return .system(size: size, weight: .bold, design: .default)
    }
    
    /// Returns Neue Montreal SemiBold font at the specified size.
    /// Falls back to system semibold font if custom font is not available.
    /// 
    /// - Parameter size: The font size in points
    /// - Returns: A Font using Neue Montreal SemiBold, or system semibold as fallback
    static func neueMontrealSemiBold(size: CGFloat) -> Font {
        #if os(iOS)
        // Try common font naming conventions
        if UIFont(name: "NeueMontreal-SemiBold", size: size) != nil {
            return .custom("NeueMontreal-SemiBold", size: size)
        }
        if UIFont(name: "Neue Montreal SemiBold", size: size) != nil {
            return .custom("Neue Montreal SemiBold", size: size)
        }
        #endif
        return .system(size: size, weight: .semibold, design: .default)
    }
    
    /// Returns Neue Montreal Regular font at the specified size.
    /// Falls back to system regular font if custom font is not available.
    /// 
    /// - Parameter size: The font size in points
    /// - Returns: A Font using Neue Montreal Regular, or system regular as fallback
    static func neueMontrealRegular(size: CGFloat) -> Font {
        #if os(iOS)
        // Try common font naming conventions
        if UIFont(name: "NeueMontreal-Regular", size: size) != nil {
            return .custom("NeueMontreal-Regular", size: size)
        }
        if UIFont(name: "Neue Montreal Regular", size: size) != nil {
            return .custom("Neue Montreal Regular", size: size)
        }
        #endif
        return .system(size: size, weight: .regular, design: .default)
    }
}
