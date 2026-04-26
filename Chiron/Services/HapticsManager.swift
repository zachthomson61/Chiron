import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// User-facing haptic feedback toggle. The `Haptics` namespace below routes all
/// in-app feedback through this manager, so flipping `isEnabled` silences every
/// site that uses the helpers.
final class HapticsManager: ObservableObject {
    static let shared = HapticsManager()

    private static let isEnabledKey = "chiron.haptics_enabled.v1"

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.isEnabledKey)
        }
    }

    private init() {
        if UserDefaults.standard.object(forKey: Self.isEnabledKey) == nil {
            self.isEnabled = true
        } else {
            self.isEnabled = UserDefaults.standard.bool(forKey: Self.isEnabledKey)
        }
    }
}

/// Static helpers that fire UIKit haptics only when `HapticsManager.shared.isEnabled`
/// is true. Use these instead of constructing feedback generators directly so the
/// settings toggle has real effect.
enum Haptics {
    #if canImport(UIKit)
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard HapticsManager.shared.isEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard HapticsManager.shared.isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }

    static func selection() {
        guard HapticsManager.shared.isEnabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }
    #else
    static func impact(_ style: Int) {}
    static func notification(_ type: Int) {}
    static func selection() {}
    #endif
}
