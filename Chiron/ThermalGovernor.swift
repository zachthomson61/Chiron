//
//  ThermalGovernor.swift
//  Chiron
//
//  Central adaptive-performance policy for the camera/pose pipeline. Extended workouts
//  were overheating phones: the full MediaPipe model ran on every 30 fps camera frame
//  for as long as the Track tab (or a coached workout) was open — through rest periods,
//  framing, and idle browsing — with no reaction to device heat or Low Power Mode.
//
//  The governor maps ProcessInfo.thermalState + Low Power Mode to a PerformanceTier,
//  and the tier + pipeline activity to a minimum interval between pose inferences.
//  SharedCameraSessionManager.captureOutput consults it per frame (cheap reads, no
//  locking: `tier` is written on the main queue and read from the video queue — the
//  same benign cross-queue enum idiom used for OnDevicePoseManager.workoutState).
//
//  Policy summary:
//  - Active set (workoutState == .exercising or an explicit Track set): full frame
//    rate while the device is cool; ~20 fps under sustained heat / Low Power Mode;
//    ~12 fps at critical. Rep validators gate on wall-clock time and multi-second
//    rep durations, so they tolerate these rates; tempo phases are stamped with
//    CACurrentMediaTime so durations stay correct at any frame rate.
//  - Idle tracking (framing, rest periods, waiting between sets): ~12 fps while cool,
//    less under heat. This keeps the skeleton overlay live and auto set-start
//    detection working while cutting the majority-of-wall-clock inference load.
//  - Screen recording (ReplayKit set replay capture) is disallowed once the device
//    reports sustained thermal pressure.
//

import Foundation

/// Coarse performance tier derived from thermal + power state.
enum PerformanceTier {
    /// Device is cool (thermal nominal/fair) and not in Low Power Mode.
    case full
    /// Sustained thermal pressure (.serious) or Low Power Mode.
    case reduced
    /// Thermal .critical — shed as much load as possible while staying functional.
    case minimal
}

final class ThermalGovernor: ObservableObject {
    static let shared = ThermalGovernor()

    /// Current tier. Written on the main queue from notification handlers; read
    /// cross-queue from the capture pipeline (benign enum read, codebase idiom).
    @Published private(set) var tier: PerformanceTier = .full

    private init() {
        recomputeTier()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(stateDidChange),
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(stateDidChange),
            name: .NSProcessInfoPowerStateDidChange,
            object: nil
        )
    }

    @objc private func stateDidChange() {
        // Both notifications can arrive on arbitrary threads; tier is @Published.
        DispatchQueue.main.async { [weak self] in
            self?.recomputeTier()
        }
    }

    private func recomputeTier() {
        let thermal = ProcessInfo.processInfo.thermalState
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let newTier: PerformanceTier
        switch thermal {
        case .critical:
            newTier = .minimal
        case .serious:
            newTier = .reduced
        default:
            newTier = lowPower ? .reduced : .full
        }
        if newTier != tier {
            tier = newTier
        }
    }

    /// Minimum seconds between pose inferences for the given pipeline activity.
    /// 0 means "run on every delivered camera frame".
    func minInferenceInterval(activeSet: Bool) -> CFTimeInterval {
        switch (tier, activeSet) {
        case (.full, true):     return 0            // every frame (~30 fps)
        case (.reduced, true):  return 1.0 / 20.0
        case (.minimal, true):  return 1.0 / 12.0
        case (.full, false):    return 1.0 / 12.0
        case (.reduced, false): return 1.0 / 8.0
        case (.minimal, false): return 1.0 / 5.0
        }
    }

    /// Whether starting a ReplayKit set recording is acceptable right now.
    /// Hardware video encode on top of camera + inference is the first load to shed.
    var allowsScreenRecording: Bool {
        tier == .full
    }
}
