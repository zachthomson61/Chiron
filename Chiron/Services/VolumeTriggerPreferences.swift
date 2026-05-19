import Foundation

/// Opt-in toggle for starting/ending sets via the volume up/down buttons
/// (phone hardware buttons or the +/- buttons on connected headphones like
/// Powerbeats Pro). Defaults off. `VolumeTriggerCoordinator` observes
/// `isEnabled` and reacts live.
final class VolumeTriggerPreferences: ObservableObject {
    static let shared = VolumeTriggerPreferences()

    private static let isEnabledKey = "chiron.volume_trigger_enabled.v1"

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.isEnabledKey)
        }
    }

    private init() {
        if UserDefaults.standard.object(forKey: Self.isEnabledKey) == nil {
            self.isEnabled = false
        } else {
            self.isEnabled = UserDefaults.standard.bool(forKey: Self.isEnabledKey)
        }
    }
}
