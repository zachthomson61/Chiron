import Foundation
import AVFoundation
import MediaPlayer
import UIKit
import Combine

/// Observes the system output volume so a volume up/down press (hardware
/// buttons on the phone, or the +/- buttons on connected headphones like
/// Powerbeats Pro) can start or end a set without touching the screen.
///
/// Unlike the headset Play button — which iOS routes exclusively to the
/// Now Playing app and therefore can't be intercepted without pausing the
/// user's music — the volume buttons are a separate input that fires
/// alongside whatever audio is playing. Music keeps going.
///
/// To avoid actually moving the system volume each press, we restore the
/// previous value through an off-screen `MPVolumeView`'s slider immediately
/// after detecting the change. There's still a momentary blip, but it
/// settles back to where the user left it.
///
/// Gated by `VolumeTriggerPreferences.shared.isEnabled`, which is off by
/// default. Flipping the toggle live takes effect without leaving the tab.
final class VolumeTriggerCoordinator: ObservableObject {
    static let shared = VolumeTriggerCoordinator()

    /// Increments each time a volume-button press fires while the
    /// coordinator is active. TrackView observes this and routes it to
    /// `handlePrimaryAction()`.
    @Published var actionRequestCounter: Int = 0

    private let session = AVAudioSession.sharedInstance()
    private var observation: NSKeyValueObservation?
    private var isActive = false
    private var didInstall = false
    private var prefSubscription: AnyCancellable?
    private var savedVolume: Float = 0
    private var ignoreUntil: Date = .distantPast
    private var volumeView: MPVolumeView?
    private weak var volumeSlider: UISlider?

    private init() {}

    /// Wires up the preference subscription. Call once from
    /// `AppState.init()`.
    func install() {
        guard !didInstall else { return }
        didInstall = true

        prefSubscription = VolumeTriggerPreferences.shared.$isEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                guard let self = self else { return }
                if !enabled {
                    self.stopObserving()
                } else if self.isActive {
                    self.startObserving()
                }
            }
    }

    /// Called by TrackView when `trackViewState` transitions in or out of
    /// `.idle`. When `.armed` or `.tracking` AND the user has opted in,
    /// we begin watching the output volume.
    func setActive(_ active: Bool) {
        isActive = active
        if active, VolumeTriggerPreferences.shared.isEnabled {
            startObserving()
        } else {
            stopObserving()
        }
    }

    private func startObserving() {
        installVolumeViewIfNeeded()
        do {
            try session.setActive(true)
        } catch {
            return
        }
        savedVolume = session.outputVolume
        observation = session.observe(\.outputVolume, options: [.new]) { [weak self] _, change in
            guard let self = self, let new = change.newValue else { return }
            self.handleVolumeChange(new)
        }
    }

    private func stopObserving() {
        observation = nil
    }

    private func handleVolumeChange(_ newValue: Float) {
        // The slider-set we issue to restore volume also fires this KVO.
        // Window it out so a single button press fires exactly one trigger.
        if Date() < ignoreUntil { return }
        if abs(newValue - savedVolume) < 0.001 { return }

        ignoreUntil = Date().addingTimeInterval(0.6)
        let restore = savedVolume
        let slider = volumeSlider

        // Restore volume as fast as possible. KVO for outputVolume is
        // delivered on the main thread on modern iOS, so an immediate
        // setValue trims the blip to roughly a single render frame.
        let snapBack = {
            slider?.setValue(restore, animated: false)
            slider?.sendActions(for: .valueChanged)
        }
        if Thread.isMainThread {
            snapBack()
        } else {
            DispatchQueue.main.async(execute: snapBack)
        }

        DispatchQueue.main.async { [weak self] in
            self?.actionRequestCounter &+= 1
        }
    }

    private func installVolumeViewIfNeeded() {
        if volumeView != nil { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.volumeView == nil else { return }
            // A "real-sized," visible MPVolumeView in the window hierarchy
            // is what convinces iOS to suppress its own volume HUD on every
            // press. Tiny (1x1) or alpha-0 views are sometimes treated as
            // "not really visible" and the HUD pops anyway, so we use a
            // reasonable frame placed well off-screen with a barely-visible
            // alpha.
            let view = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 80, height: 80))
            view.alpha = 0.02
            view.isHidden = false
            if let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first,
               let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first {
                window.addSubview(view)
            }
            self.volumeView = view
            self.volumeSlider = view.subviews.compactMap { $0 as? UISlider }.first
        }
    }
}
