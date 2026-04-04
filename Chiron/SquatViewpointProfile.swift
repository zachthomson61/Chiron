//
//  SquatViewpointProfile.swift
//  Chiron
//
//  Viewpoint classification (camera height × view) and per-bucket rep-detection profiles
//  for bodyweight squats only. Deterministic heuristics — no ML.
//

import Foundation
import CoreGraphics
import simd

// MARK: - Viewpoint categories

enum CameraHeightCategory: String, Sendable {
    case floor
    case chest
    case head
    case unknown
}

enum CameraViewCategory: String, Sendable {
    case front
    case side
    case oblique
    case unknown
}

/// Nine recording buckets + unknown (falls back to chest_side profile).
enum SquatViewpointBucket: String, CaseIterable, Sendable {
    case floor_front
    case floor_side
    case floor_oblique
    case chest_front
    case chest_side
    case chest_oblique
    case head_front
    case head_side
    case head_oblique
    case unknown

    var cameraHeight: CameraHeightCategory {
        switch self {
        case .floor_front, .floor_side, .floor_oblique: return .floor
        case .chest_front, .chest_side, .chest_oblique: return .chest
        case .head_front, .head_side, .head_oblique: return .head
        case .unknown: return .unknown
        }
    }

    var cameraView: CameraViewCategory {
        switch self {
        case .floor_front, .chest_front, .head_front: return .front
        case .floor_side, .chest_side, .head_side: return .side
        case .floor_oblique, .chest_oblique, .head_oblique: return .oblique
        case .unknown: return .unknown
        }
    }

    static func bucket(height: CameraHeightCategory, view: CameraViewCategory) -> SquatViewpointBucket {
        switch (height, view) {
        case (.floor, .front): return .floor_front
        case (.floor, .side): return .floor_side
        case (.floor, .oblique): return .floor_oblique
        case (.chest, .front): return .chest_front
        case (.chest, .side): return .chest_side
        case (.chest, .oblique): return .chest_oblique
        case (.head, .front): return .head_front
        case (.head, .side): return .head_side
        case (.head, .oblique): return .head_oblique
        default: return .unknown
        }
    }
}

// MARK: - Per-frame extension (Up / Down / Neither)

enum SquatExtensionFrameState: String, Sendable {
    case up
    case down
    case neither
}

// MARK: - Rep reject reasons (debug)

enum SquatRepRejectReason: String, Sendable {
    case none
    case minRepInterval
    case minCycleDuration
    case maxCycleDuration
    case shallowBounceAborted
}

// MARK: - Vertical (shoulder-driven) rep phases (bodyweight)

enum BodyweightVerticalRepPhase: Sendable {
    case idleAtTop
    case descending
    case bottomReached
    case ascending
}

// MARK: - Rep detection profile

/// Thresholds tunable per viewpoint bucket. Vertical rep excursions are normalized by leg length (hip–ankle) in overlay Y.
struct SquatRepDetectionProfile: Sendable {
    var repTopLockToleranceNormalized: Float
    var repDescentExcursionNormalized: Float
    var repBottomExcursionNormalized: Float
    var repAscentRecoveryNormalized: Float
    var repReturnToTopToleranceNormalized: Float
    var framesForTopLock: Int
    var framesForBottomConfirm: Int
    var framesForTopReturnConfirm: Int

    var minRepInterval: TimeInterval
    var minRepCycleDuration: TimeInterval
    var maxRepCycleDuration: TimeInterval

    var repCountDepthThreshold: Float
    var repGoodDepthThreshold: Float
    var hipKneeDepthQualityToleranceNormalized: Float
    var repAccumulationStartDepth: Float

    // Shoulder Y EMA smoothing factor (0…1). Lower = heavier smoothing. 0.35 is a good default.
    var shoulderEMAAlpha: Float
    // Minimum smoothed velocity (per-frame delta / legSpan) to confirm descent direction.
    var velocityDescentConfirm: Float
    // Minimum smoothed velocity (negative = upward) to confirm ascent direction.
    var velocityAscentConfirm: Float

    // Per-frame extension state (hysteresis on hip depth 0…1) — UI / debug; not used to gate rep count.
    var extensionUpEnterMaxDepth: Float
    var extensionUpExitDepth: Float
    var extensionDownEnterDepth: Float
    var extensionDownExitDepth: Float

    // Form analysis influence (0…1, multiply effective weight / require stronger evidence)
    var formWeightDepth: Float
    var formWeightKneeTracking: Float
    var formWeightForwardLean: Float
    var formIssueEvidenceMultiplier: Float
}

// MARK: - Profile table

enum SquatRepProfileTable {
    /// Unknown or unclassified viewpoint uses chest_side-equivalent baseline.
    static func profile(for bucket: SquatViewpointBucket) -> SquatRepDetectionProfile {
        switch bucket {
        case .chest_side: return chestSideBaseline
        case .chest_front: return chestFront
        case .chest_oblique: return chestOblique
        case .floor_front: return floorFront
        case .floor_side: return floorSide
        case .floor_oblique: return floorOblique
        case .head_front: return headFront
        case .head_side: return headSide
        case .head_oblique: return headOblique
        case .unknown: return chestSideBaseline
        }
    }

    // MARK: Baseline: chest_side (reference)

    private static let chestSideBaseline = SquatRepDetectionProfile(
        repTopLockToleranceNormalized: 0.08,
        repDescentExcursionNormalized: 0.05,
        repBottomExcursionNormalized: 0.10,
        repAscentRecoveryNormalized: 0.05,
        repReturnToTopToleranceNormalized: 0.08,
        framesForTopLock: 2,
        framesForBottomConfirm: 2,
        framesForTopReturnConfirm: 2,
        minRepInterval: 0.35,
        minRepCycleDuration: 0.45,
        maxRepCycleDuration: 5.0,
        repCountDepthThreshold: 0.26,
        repGoodDepthThreshold: 0.40,
        hipKneeDepthQualityToleranceNormalized: 0.10,
        repAccumulationStartDepth: 0.18,
        shoulderEMAAlpha: 0.35,
        velocityDescentConfirm: 0.004,
        velocityAscentConfirm: -0.004,
        extensionUpEnterMaxDepth: 0.14,
        extensionUpExitDepth: 0.18,
        extensionDownEnterDepth: 0.30,
        extensionDownExitDepth: 0.26,
        formWeightDepth: 1.0,
        formWeightKneeTracking: 0.85,
        formWeightForwardLean: 1.0,
        formIssueEvidenceMultiplier: 1.0
    )

    // MARK: chest_front — depth less reliable in 3D; trust knees more in form weights

    private static let chestFront = SquatRepDetectionProfile(
        repTopLockToleranceNormalized: 0.09,
        repDescentExcursionNormalized: 0.045,
        repBottomExcursionNormalized: 0.09,
        repAscentRecoveryNormalized: 0.045,
        repReturnToTopToleranceNormalized: 0.09,
        framesForTopLock: 2,
        framesForBottomConfirm: 2,
        framesForTopReturnConfirm: 2,
        minRepInterval: 0.35,
        minRepCycleDuration: 0.5,
        maxRepCycleDuration: 5.0,
        repCountDepthThreshold: 0.22,
        repGoodDepthThreshold: 0.38,
        hipKneeDepthQualityToleranceNormalized: 0.11,
        repAccumulationStartDepth: 0.16,
        shoulderEMAAlpha: 0.33,
        velocityDescentConfirm: 0.003,
        velocityAscentConfirm: -0.003,
        extensionUpEnterMaxDepth: 0.16,
        extensionUpExitDepth: 0.20,
        extensionDownEnterDepth: 0.28,
        extensionDownExitDepth: 0.24,
        formWeightDepth: 0.65,
        formWeightKneeTracking: 1.15,
        formWeightForwardLean: 0.85,
        formIssueEvidenceMultiplier: 1.15
    )

    private static let chestOblique = SquatRepDetectionProfile(
        repTopLockToleranceNormalized: 0.085,
        repDescentExcursionNormalized: 0.048,
        repBottomExcursionNormalized: 0.095,
        repAscentRecoveryNormalized: 0.048,
        repReturnToTopToleranceNormalized: 0.085,
        framesForTopLock: 2,
        framesForBottomConfirm: 2,
        framesForTopReturnConfirm: 2,
        minRepInterval: 0.35,
        minRepCycleDuration: 0.48,
        maxRepCycleDuration: 5.0,
        repCountDepthThreshold: 0.24,
        repGoodDepthThreshold: 0.39,
        hipKneeDepthQualityToleranceNormalized: 0.105,
        repAccumulationStartDepth: 0.17,
        shoulderEMAAlpha: 0.34,
        velocityDescentConfirm: 0.0035,
        velocityAscentConfirm: -0.0035,
        extensionUpEnterMaxDepth: 0.15,
        extensionUpExitDepth: 0.19,
        extensionDownEnterDepth: 0.29,
        extensionDownExitDepth: 0.25,
        formWeightDepth: 0.8,
        formWeightKneeTracking: 0.95,
        formWeightForwardLean: 0.9,
        formIssueEvidenceMultiplier: 1.2
    )

    // MARK: floor_* — more tolerant vertical band; looser extension bands

    private static let floorFront = SquatRepDetectionProfile(
        repTopLockToleranceNormalized: 0.11,
        repDescentExcursionNormalized: 0.04,
        repBottomExcursionNormalized: 0.085,
        repAscentRecoveryNormalized: 0.04,
        repReturnToTopToleranceNormalized: 0.11,
        framesForTopLock: 2,
        framesForBottomConfirm: 2,
        framesForTopReturnConfirm: 2,
        minRepInterval: 0.32,
        minRepCycleDuration: 0.42,
        maxRepCycleDuration: 5.5,
        repCountDepthThreshold: 0.20,
        repGoodDepthThreshold: 0.36,
        hipKneeDepthQualityToleranceNormalized: 0.12,
        repAccumulationStartDepth: 0.15,
        shoulderEMAAlpha: 0.30,
        velocityDescentConfirm: 0.003,
        velocityAscentConfirm: -0.003,
        extensionUpEnterMaxDepth: 0.18,
        extensionUpExitDepth: 0.22,
        extensionDownEnterDepth: 0.27,
        extensionDownExitDepth: 0.23,
        formWeightDepth: 0.6,
        formWeightKneeTracking: 1.1,
        formWeightForwardLean: 0.8,
        formIssueEvidenceMultiplier: 1.2
    )

    private static let floorSide = SquatRepDetectionProfile(
        repTopLockToleranceNormalized: 0.10,
        repDescentExcursionNormalized: 0.042,
        repBottomExcursionNormalized: 0.09,
        repAscentRecoveryNormalized: 0.042,
        repReturnToTopToleranceNormalized: 0.10,
        framesForTopLock: 2,
        framesForBottomConfirm: 2,
        framesForTopReturnConfirm: 2,
        minRepInterval: 0.32,
        minRepCycleDuration: 0.4,
        maxRepCycleDuration: 5.5,
        repCountDepthThreshold: 0.22,
        repGoodDepthThreshold: 0.38,
        hipKneeDepthQualityToleranceNormalized: 0.11,
        repAccumulationStartDepth: 0.15,
        shoulderEMAAlpha: 0.32,
        velocityDescentConfirm: 0.0035,
        velocityAscentConfirm: -0.0035,
        extensionUpEnterMaxDepth: 0.17,
        extensionUpExitDepth: 0.21,
        extensionDownEnterDepth: 0.28,
        extensionDownExitDepth: 0.24,
        formWeightDepth: 1.05,
        formWeightKneeTracking: 0.75,
        formWeightForwardLean: 1.05,
        formIssueEvidenceMultiplier: 1.05
    )

    private static let floorOblique = SquatRepDetectionProfile(
        repTopLockToleranceNormalized: 0.105,
        repDescentExcursionNormalized: 0.041,
        repBottomExcursionNormalized: 0.088,
        repAscentRecoveryNormalized: 0.041,
        repReturnToTopToleranceNormalized: 0.105,
        framesForTopLock: 2,
        framesForBottomConfirm: 2,
        framesForTopReturnConfirm: 2,
        minRepInterval: 0.32,
        minRepCycleDuration: 0.43,
        maxRepCycleDuration: 5.5,
        repCountDepthThreshold: 0.21,
        repGoodDepthThreshold: 0.37,
        hipKneeDepthQualityToleranceNormalized: 0.115,
        repAccumulationStartDepth: 0.15,
        shoulderEMAAlpha: 0.30,
        velocityDescentConfirm: 0.003,
        velocityAscentConfirm: -0.003,
        extensionUpEnterMaxDepth: 0.175,
        extensionUpExitDepth: 0.215,
        extensionDownEnterDepth: 0.275,
        extensionDownExitDepth: 0.235,
        formWeightDepth: 0.75,
        formWeightKneeTracking: 0.9,
        formWeightForwardLean: 0.88,
        formIssueEvidenceMultiplier: 1.22
    )

    // MARK: head_* — compressed vertical; slightly tighter excursion, looser return

    private static let headFront = SquatRepDetectionProfile(
        repTopLockToleranceNormalized: 0.09,
        repDescentExcursionNormalized: 0.04,
        repBottomExcursionNormalized: 0.088,
        repAscentRecoveryNormalized: 0.04,
        repReturnToTopToleranceNormalized: 0.095,
        framesForTopLock: 2,
        framesForBottomConfirm: 2,
        framesForTopReturnConfirm: 3,
        minRepInterval: 0.36,
        minRepCycleDuration: 0.5,
        maxRepCycleDuration: 4.8,
        repCountDepthThreshold: 0.23,
        repGoodDepthThreshold: 0.39,
        hipKneeDepthQualityToleranceNormalized: 0.10,
        repAccumulationStartDepth: 0.17,
        shoulderEMAAlpha: 0.32,
        velocityDescentConfirm: 0.003,
        velocityAscentConfirm: -0.003,
        extensionUpEnterMaxDepth: 0.15,
        extensionUpExitDepth: 0.19,
        extensionDownEnterDepth: 0.29,
        extensionDownExitDepth: 0.25,
        formWeightDepth: 0.7,
        formWeightKneeTracking: 1.05,
        formWeightForwardLean: 0.9,
        formIssueEvidenceMultiplier: 1.12
    )

    private static let headSide = SquatRepDetectionProfile(
        repTopLockToleranceNormalized: 0.085,
        repDescentExcursionNormalized: 0.046,
        repBottomExcursionNormalized: 0.095,
        repAscentRecoveryNormalized: 0.046,
        repReturnToTopToleranceNormalized: 0.09,
        framesForTopLock: 2,
        framesForBottomConfirm: 2,
        framesForTopReturnConfirm: 3,
        minRepInterval: 0.36,
        minRepCycleDuration: 0.48,
        maxRepCycleDuration: 4.8,
        repCountDepthThreshold: 0.25,
        repGoodDepthThreshold: 0.40,
        hipKneeDepthQualityToleranceNormalized: 0.10,
        repAccumulationStartDepth: 0.18,
        shoulderEMAAlpha: 0.35,
        velocityDescentConfirm: 0.004,
        velocityAscentConfirm: -0.004,
        extensionUpEnterMaxDepth: 0.145,
        extensionUpExitDepth: 0.185,
        extensionDownEnterDepth: 0.305,
        extensionDownExitDepth: 0.265,
        formWeightDepth: 1.05,
        formWeightKneeTracking: 0.8,
        formWeightForwardLean: 1.0,
        formIssueEvidenceMultiplier: 1.05
    )

    private static let headOblique = SquatRepDetectionProfile(
        repTopLockToleranceNormalized: 0.088,
        repDescentExcursionNormalized: 0.044,
        repBottomExcursionNormalized: 0.092,
        repAscentRecoveryNormalized: 0.044,
        repReturnToTopToleranceNormalized: 0.092,
        framesForTopLock: 2,
        framesForBottomConfirm: 2,
        framesForTopReturnConfirm: 3,
        minRepInterval: 0.36,
        minRepCycleDuration: 0.49,
        maxRepCycleDuration: 4.8,
        repCountDepthThreshold: 0.24,
        repGoodDepthThreshold: 0.395,
        hipKneeDepthQualityToleranceNormalized: 0.102,
        repAccumulationStartDepth: 0.175,
        shoulderEMAAlpha: 0.32,
        velocityDescentConfirm: 0.0035,
        velocityAscentConfirm: -0.0035,
        extensionUpEnterMaxDepth: 0.148,
        extensionUpExitDepth: 0.188,
        extensionDownEnterDepth: 0.298,
        extensionDownExitDepth: 0.258,
        formWeightDepth: 0.85,
        formWeightKneeTracking: 0.92,
        formWeightForwardLean: 0.93,
        formIssueEvidenceMultiplier: 1.15
    )
}

// MARK: - Extension frame state (hysteresis)

enum SquatExtensionFrameClassifier {
    /// Update finite-state hysteresis: `up` = shallow depth, `down` = deep, `neither` = between bands.
    static func nextState(
        previous: SquatExtensionFrameState,
        hipDepth: Float,
        profile: SquatRepDetectionProfile
    ) -> SquatExtensionFrameState {
        let uEnter = profile.extensionUpEnterMaxDepth
        let uExit = profile.extensionUpExitDepth
        let dEnter = profile.extensionDownEnterDepth
        let dExit = profile.extensionDownExitDepth

        switch previous {
        case .up:
            if hipDepth >= dEnter { return .down }
            if hipDepth > uExit { return .neither }
            return .up
        case .down:
            if hipDepth <= uEnter { return .up }
            if hipDepth < dExit { return .neither }
            return .down
        case .neither:
            if hipDepth <= uEnter { return .up }
            if hipDepth >= dEnter { return .down }
            return .neither
        }
    }
}

// MARK: - Viewpoint classifiers (2D overlay + optional 3D)

struct SquatViewpointClassifier {

    struct HeightScores: Sendable {
        var floor: Float = 0
        var chest: Float = 0
        var head: Float = 0
    }

    struct ViewScores: Sendable {
        var front: Float = 0
        var side: Float = 0
        var oblique: Float = 0
    }

    private static let minWinMargin: Float = 0.06
    private static let minWinScore: Float = 0.22

    static func classifyCameraHeight(overlay: [String: CGPoint]) -> (CameraHeightCategory, HeightScores) {
        var s = HeightScores()
        guard
            let nose = overlay["nose"],
            let ls = overlay["leftShoulder"], let rs = overlay["rightShoulder"],
            let lh = overlay["leftHip"], let rh = overlay["rightHip"],
            let lk = overlay["leftKnee"], let rk = overlay["rightKnee"],
            let la = overlay["leftAnkle"], let ra = overlay["rightAnkle"]
        else {
            return (.unknown, s)
        }

        let shoulderY = (ls.y + rs.y) / 2
        let hipY = (lh.y + rh.y) / 2
        let kneeY = (lk.y + rk.y) / 2
        let ankleY = (la.y + ra.y) / 2

        // Lower camera (floor): ankles and knees relatively high in frame (small Y), nose high — looking up subject
        if ankleY < 0.72 { s.floor += 0.25 }
        if kneeY < hipY + 0.02, ankleY < kneeY + 0.05 { s.floor += 0.2 }
        // Torso vs leg span in Y (perspective cue)
        let torsoSpan = abs(shoulderY - hipY)
        let legSpan = abs(hipY - ankleY)
        if legSpan > 0.001 {
            let ratio = torsoSpan / legSpan
            if ratio < 0.52 { s.floor += 0.35 }
            else if ratio > 0.78 { s.head += 0.3 }
            else { s.chest += 0.35 }
        } else {
            s.chest += 0.2
        }

        if ankleY < 0.68 { s.floor += 0.15 }
        if shoulderY > 0.45 { s.head += 0.15 }
        if nose.y > 0.4 { s.head += 0.1 }

        let cat = pickHeightWinner(floor: s.floor, chest: s.chest, head: s.head)
        return (cat, s)
    }

    static func classifyCameraView(overlay: [String: CGPoint], confidence: [String: Float]) -> (CameraViewCategory, ViewScores) {
        var s = ViewScores()
        guard
            let ls = overlay["leftShoulder"], let rs = overlay["rightShoulder"],
            let lh = overlay["leftHip"], let rh = overlay["rightHip"],
            let lw = overlay["leftWrist"], let rw = overlay["rightWrist"],
            let la = overlay["leftAnkle"], let ra = overlay["rightAnkle"]
        else {
            return (.unknown, s)
        }

        let shoulderW = abs(rs.x - ls.x)
        let hipW = abs(rh.x - lh.x)
        let wristW = abs(rw.x - lw.x)
        let ankleW = abs(ra.x - la.x)

        let avgPairW = (shoulderW + hipW + wristW + ankleW) / 4

        if avgPairW > 0.14 { s.front += 0.35 }
        if avgPairW < 0.06 { s.side += 0.4 }
        if avgPairW >= 0.06, avgPairW <= 0.14 { s.oblique += 0.35 }

        if shoulderW > 0.12, hipW > 0.08 { s.front += 0.2 }
        if shoulderW < 0.05, hipW < 0.05 { s.side += 0.25 }

        let lc = confidence["leftKnee"] ?? 1
        let rc = confidence["rightKnee"] ?? 1
        if abs(lc - rc) > 0.25 { s.side += 0.12 }

        let cat = pickViewWinner(front: s.front, oblique: s.oblique, side: s.side)
        return (cat, s)
    }

    private static func pickHeightWinner(floor f: Float, chest c: Float, head h: Float) -> CameraHeightCategory {
        let pairs: [(CameraHeightCategory, Float)] = [(.floor, f), (.chest, c), (.head, h)]
        let sorted = pairs.sorted { $0.1 > $1.1 }
        let best = sorted[0].1
        let second = sorted[1].1
        guard best >= minWinScore, (best - second) >= minWinMargin else { return .unknown }
        return sorted[0].0
    }

    private static func pickViewWinner(front: Float, oblique: Float, side: Float) -> CameraViewCategory {
        let pairs: [(CameraViewCategory, Float)] = [(.front, front), (.oblique, oblique), (.side, side)]
        let sorted = pairs.sorted { $0.1 > $1.1 }
        let best = sorted[0].1
        let second = sorted[1].1
        guard best >= minWinScore, (best - second) >= minWinMargin else { return .unknown }
        return sorted[0].0
    }
}

// MARK: - Viewpoint promotion (temporal)

struct SquatViewpointSmoother {
    private var buffer: [SquatViewpointBucket] = []
    private let bufferSize: Int
    private let promoteCount: Int
    private(set) var activeBucket: SquatViewpointBucket

    init(bufferSize: Int = 10, promoteCount: Int = 7, initial: SquatViewpointBucket = .chest_side) {
        self.bufferSize = bufferSize
        self.promoteCount = promoteCount
        self.activeBucket = initial
    }

    /// Returns `true` if `activeBucket` changed after this frame.
    @discardableResult
    mutating func push(candidate raw: SquatViewpointBucket) -> Bool {
        let candidate = raw == .unknown ? SquatViewpointBucket.chest_side : raw
        buffer.append(candidate)
        if buffer.count > bufferSize { buffer.removeFirst() }

        guard buffer.count >= promoteCount else { return false }

        let tail = Array(buffer.suffix(promoteCount))
        let first = tail[0]
        let allSame = tail.allSatisfy { $0 == first }
        if allSame, first != activeBucket {
            activeBucket = first
            return true
        }
        return false
    }

    mutating func reset(keepBucket: SquatViewpointBucket = .chest_side) {
        buffer.removeAll()
        activeBucket = keepBucket
    }
}
