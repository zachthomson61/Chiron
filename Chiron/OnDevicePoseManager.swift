//
//  OnDevicePoseManager.swift
//  Chiron
//
//  On-device pose pipeline: MediaPipe Pose Landmarker (live stream) → MediaPipePoseAdapter
//  → Skeleton3D + overlay landmarks → form analysis, rep counting, and UI updates.
//

import Foundation
import AVFoundation
import CoreML
import UIKit
import MediaPipeTasksVision

// MARK: - Pose Landmark Structure
struct PoseLandmark {
    let type: PoseLandmarkType
    let x: Float
    let y: Float
    let confidence: Float
    
    init(type: PoseLandmarkType, point: CGPoint, confidence: Float) {
        self.type = type
        self.x = Float(point.x)
        self.y = Float(point.y)
        self.confidence = confidence
    }
    
    enum PoseLandmarkType {
        case leftShoulder, rightShoulder
        case leftHip, rightHip
        case leftKnee, rightKnee
        case leftAnkle, rightAnkle
        case leftElbow, rightElbow
        case leftWrist, rightWrist
        case nose, leftEye, rightEye
        case leftEar, rightEar
    }
}

// MARK: - Form Analysis Results
struct FormAnalysis {
    let depth: Float // 0.0 = shallow, 1.0 = deep
    let backAngle: Float // degrees (0-180)
    let kneeAlignment: Float // -1.0 = knees caving in, 0.0 = aligned, 1.0 = knees bowing out
    let overallScore: Float // 0.0-1.0
    let issues: [IssueCode]
    let summary: String
    let repCount: Int // Current rep count
    // Average tempo metrics for current set (milliseconds)
    let avgEccentricMs: Float?  // Time going down
    let avgPauseMs: Float?      // Time at bottom
    let avgConcentricMs: Float? // Time coming up
    // ROM metrics for current set
    let avgBottomDepth: Float?
    let deepRepRatio: Float?
}

// MARK: - Bodyweight Squat Rep-Level Metrics (phase-relevant, for set aggregation)

/// Per-rep metrics for bodyweight squats. Used for set-level aggregation; invalid reps are discarded.
struct BodyweightRepMetrics {
    let depthAtBottom: Float
    let backAngleMax: Float
    let kneeAlignmentWorstNearBottom: Float
    let shallowDepth: Bool
    let excessiveForwardLean: Bool
    let kneeValgus: Bool
    /// True if hip–knee relationship met parallel-depth quality (secondary; does not gate counting).
    let hipKneeDepthQualityMet: Bool
    let valid: Bool
    let timestamp: TimeInterval
}

/// Bodyweight-only: gates frame accumulation for per-rep metrics (independent of squat rep counter phase names).
enum RepPhase {
    case idle
    case accumulating
}

/// Barbell/benchPress squat rep phases: hip-depth hysteresis. Bodyweight squats use `BodyweightVerticalRepPhase` (shoulder Y) instead.
enum SquatRepPhase {
    case idleAtTop
    case descending
    case bottomReached
    case ascending
}

/// Snapshot of hip-vs-knee vertical relationship (secondary quality tag only).
struct SquatRepFrame {
    let avgHipY: Float
    let avgKneeY: Float
    let legLength: Float
    let normalizedHipKneeDelta: Float   // (avgHipY - avgKneeY) / legLength; ≤0 means hips at or below knees
}

/// Current-frame metrics used as fallback when no valid rep history exists.
struct FrameMetrics {
    let depth: Float
    let backAngle: Float
    let kneeAlignment: Float
}

// MARK: - Workout State Management
enum WorkoutState {
    case waiting        // Waiting for user to start exercising
    case exercising     // Actively performing reps in a set
    case resting        // Rest period between sets
    case finished       // Workout completed
}

// MARK: - Tracked Exercise Type

/// Exercise type identifier for pose detection and form analysis.
/// Maps the user-selected exercise into a pose-analysis category.
enum TrackedExerciseType {
    case bodyweight           // Bodyweight squat exercises
    case barbell              // Barbell back squat exercises
    case benchPress           // Regular bench press
    case closeGripBenchPress  // Close-grip bench press exercises
}

// MARK: - Inactivity Detection
class InactivityDetector {
    private var lastRepTime: Date?
    private var lastValidPoseTime: Date?
    private let inactivityThreshold: TimeInterval = 4.0
    private let poseThreshold: TimeInterval = 5.0
    
    func checkInactivity() -> Bool {
        let now = Date()
        
        // Check if no reps detected for inactivity threshold
        if let lastRep = lastRepTime {
            if now.timeIntervalSince(lastRep) > inactivityThreshold {
                return true
            }
        }
        
        // Check if no valid pose detected for pose threshold
        if let lastPose = lastValidPoseTime {
            if now.timeIntervalSince(lastPose) > poseThreshold {
                return true
            }
        }
        
        return false
    }
    
    func resetTimer() {
        lastRepTime = Date()
        lastValidPoseTime = Date()
    }
    
    func updateLastActivity() {
        lastValidPoseTime = Date()
    }
    
    func updateLastRep() {
        lastRepTime = Date()
    }
    
    func getTimeSinceLastRep() -> TimeInterval {
        guard let lastRep = lastRepTime else { return 0 }
        return Date().timeIntervalSince(lastRep)
    }
    
    func getTimeSinceLastPose() -> TimeInterval {
        guard let lastPose = lastValidPoseTime else { return 0 }
        return Date().timeIntervalSince(lastPose)
    }
}

// MARK: - On-Device Pose Manager
class OnDevicePoseManager: NSObject, ObservableObject {
    static let shared = OnDevicePoseManager()
    
    // MARK: - Pose Detection Properties
    @Published var poseDetected = false
    @Published var currentFormAnalysis: FormAnalysis?
    @Published var repCount: Int = 0
    @Published var workoutState: WorkoutState = .waiting
    @Published var currentSet: Int = 0
    @Published var trackedExerciseType: TrackedExerciseType = .bodyweight
    
    /// Stores form analysis at rep completion for score calculation.
    /// 
    /// **Purpose:** Ensures form score can be calculated even if pose detection is temporarily lost
    /// immediately after rep completion. The view layer uses this as a fallback when `currentFormAnalysis`
    /// is unavailable during score calculation.
    @Published var lastRepFormAnalysis: FormAnalysis?
    
    /// Latest pose landmarks in normalised coordinates (0–1).
    /// Populated by MediaPipePoseAdapter from PoseLandmarkerResult.landmarks.
    @Published var currentNormalizedLandmarks: [String: CGPoint]?
    
    /// Camera view type for close-grip bench press exercises.
    /// Used to adjust form analysis calculations based on camera angle:
    /// - `.rack`: Top-down view (high, angled down)
    /// - `.floor`: Bottom-up view (low, angled up)
    /// - `.tripod`: Side view (bar level, slight angle)
    /// Set by WorkoutActiveView when starting a close-grip bench press exercise.
    var benchPressViewType: BenchPressViewType = .tripod

    // MARK: - Bodyweight squat viewpoint (auto-classified, debuggable)
    @Published var currentCameraHeightCategory: CameraHeightCategory = .unknown
    @Published var currentCameraViewCategory: CameraViewCategory = .unknown
    @Published var currentSquatViewpointBucket: SquatViewpointBucket = .chest_side
    @Published var currentSquatProfileName: String = SquatViewpointBucket.chest_side.rawValue
    @Published var currentSquatExtensionFrameState: SquatExtensionFrameState = .neither

    private var viewpointSmoother = SquatViewpointSmoother()
    private var squatExtensionFrameStateInternal: SquatExtensionFrameState = .neither
    /// Active rep-detection profile for bodyweight (updated each frame from smoothed viewpoint).
    private var activeBodyweightRepProfile: SquatRepDetectionProfile = SquatRepProfileTable.profile(for: .chest_side)

    // MARK: - Bodyweight shoulder-vertical rep state
    private var bwShoulderPhase: BodyweightVerticalRepPhase = .idleAtTop
    private var bwTopRefShoulderY: Float?
    private var bwCycleExtremeShoulderY: Float?
    private var bwTopLocked: Bool = false
    private var bwShoulderConsecutive: Int = 0
    private var bwRepCycleStartTime: Date?
    /// Consecutive frames near top while descending (abandon shallow bounce).
    private var bwEarlyTopReturnFrames: Int = 0
    /// EMA-smoothed shoulder Y (overlay coords). Reduces MediaPipe jitter.
    private var bwSmoothedShoulderY: Float?
    /// Previous frame's smoothed shoulder Y, used to compute velocity.
    private var bwPrevSmoothedShoulderY: Float?
    /// Smoothed frame-to-frame velocity (positive = downward in overlay coords).
    private var bwShoulderVelocity: Float = 0
    
    // MARK: - Automatic Set Detection Properties
    private var inactivityDetector = InactivityDetector()
    private var consecutiveGoodReps = 0
    private var lastRepTime: Date?
    private var setStartTime: Date?
    private var restStartTime: Date?
    private let restPeriodDuration: TimeInterval = 60.0 // 60 seconds rest
    // Allow set-start after first detected rep to avoid deadlocking analysis
    // when cadence/filtering drops the second early rep.
    private let minRepsForSetStart = 1
    private let minTimeBetweenReps: TimeInterval = 0.8  // Minimum 0.8 seconds between reps (MORE SENSITIVE)
    
    // MARK: - Rep Validation Properties
    private var lastRepValidationTime: Date?
    private var repValidationThreshold: TimeInterval = 0.5
    private var movementThreshold: Float = 0.05  // Very sensitive to movement
    private var poseConfidenceThreshold: Float = 0.15  // Even lower confidence threshold for better detection (MORE SENSITIVE)
    /// Require this many consecutive frames in deep/shallow before rep-state transition (reduces false reps).
    /// Shared by bench press.
    private let consistentFramesForRepTransition: Int = 3

    // MARK: - Squat rep counting (hip depth hysteresis, tunable)
    /// Normalized hip depth: shallow / standing band for “top”.
    private let repTopThreshold: Float = 0.14
    /// Depth at or above this leaves top and starts descent.
    private let repStartThreshold: Float = 0.20
    /// Depth at or above this (confirmed) marks bottom for counting.
    private let repBottomThreshold: Float = 0.34
    private let framesForBottomConfirmation: Int = 2
    private let framesForTopConfirmation: Int = 2
    /// Secondary: barbell / bench squat rep quality tag (does not gate rep counting).
    private let hipKneeBottomToleranceNormalizedBarbell: Float = 0.06

    // MARK: - Squat rep depth state machine
    private var squatRepPhase: SquatRepPhase = .idleAtTop
    private var squatRepTopHoldFrames: Int = 0
    private var squatRepBottomHoldFrames: Int = 0
    /// Max hip depth seen during the current squat rep cycle (for analysis / debug).
    private var squatRepMaxDepthThisCycle: Float = 0
    /// True if any frame in the cycle met hip–knee parallel tolerance (secondary quality).
    private var squatRepCycleHipKneeParallelMet: Bool = false
    /// Captured when a rep is counted; read by `commitBodyweightRepIfNeeded`.
    private var lastCountedRepHipKneeDepthQualityMet: Bool = false
    
    // MARK: - Close-Grip Bench Press Rep Detection State
    
    /// Tracks whether the bar has reached chest (bottom position) in the current rep cycle.
    private var reachedBottomThisCycleBenchPress: Bool = false
    /// Consistent-frame counters for bench rep transitions (avoid false reps from jitter).
    private var consecutiveFramesAtBottomBenchPress: Int = 0
    private var consecutiveFramesAtTopBenchPress: Int = 0
    
    /// Timestamps for tracking eccentric (lowering) and concentric (pressing) phases.
    /// Used to measure tempo: eccentric should be ≥1s, concentric should be ≤2s.
    private var benchPressEccentricStartTime: CFTimeInterval?
    private var benchPressBottomTime: CFTimeInterval?
    
    /// Stores wrist Y position at bottom of rep for relative lockout detection.
    /// Used in tripod view to detect lockout even if absolute threshold isn't met.
    /// Cleared after rep validation.
    private var benchPressBottomWristY: Float?
    
    // MARK: - Audio Feedback Properties
    private var lastSpokenRep: Int = 0
    private var repFeedbackInterval = 5 // Speak every 5 reps
    
    private var analysisQueue = DispatchQueue(label: "pose.analysis", qos: .userInteractive)
    
    // MARK: - MediaPipe Pose Properties
    
    private var poseLandmarker: PoseLandmarker?
    private let poseAdapter = MediaPipePoseAdapter()
    
    /// Higher alpha (0.35) so lower body tracks with less lag; deep squats update overlay and rep logic faster.
    private let jointSmoother = JointSmoother(alpha: 0.35, twoStage: true)
    /// More responsive overlay so hip/knee positions follow motion better (alphaWhenMoving 0.35).
    private let overlayLandmarkSmoother = Landmark2DSmoother(alphaWhenMoving: 0.35, alphaWhenStill: 0.1)
    /// Hold last stable form/landmarks for this many frames when pose is missing or low confidence.
    private let holdStablePoseFrames: Int = 3
    private var framesSinceGoodPose: Int = 0
    private(set) var currentAnalysisSource: PoseAnalysisSource = .pose3D
    
    /// Monotonic frame counter used as timestamp for MediaPipe livestream API.
    private var frameTimestampMs: Int = 0

    /// Latest smoothed skeleton from the analysis queue, used by squat rep detection.
    private var lastSmoothedSkeleton: Skeleton3D?
    
    // 3D depth thresholds (hip-displacement / legLength scale).
    private let deepDepthThreshold3D: Float = 0.45
    private let shallowDepthThreshold3D: Float = 0.20
    
    // Cue speaking state
    private var lastCueSpokenAt: Date?
    private var lastCueText: String = ""
    private let cueCooldownSeconds: TimeInterval = 6.0
    private let cueByIssue: [IssueCode: String] = [
        .kneeValgus:        "Push your knees out",
        .kneeVarus:         "Keep your knees over your toes",
        .forwardLean:       "Lift your chest",
        .insufficientDepth: "Squat a little deeper"
    ]
    
    // Aggregation for mid-set feedback (collected during the set, spoken between sets)
    private var issueCounts: [IssueCode: Int] = [:]

    private enum PositiveKey: String { case goodDepth, chestTall, kneesOverToes }
    private var positiveCounts: [PositiveKey: Int] = [:]
    private let positiveCueByKey: [PositiveKey: String] = [
        .goodDepth:     "Good depth",
        .chestTall:     "Chest tall",
        .kneesOverToes: "Knees over toes"
    ]
    
    // Tempo tracking for hypertrophy (milliseconds)
    private var repStartTime: CFTimeInterval?
    private var bottomTime: CFTimeInterval?
    private var lastDepth: Float = 0
    private var sumEccentricMs: Double = 0  // Total time going down
    private var sumPauseMs: Double = 0      // Total time paused at bottom
    private var sumConcentricMs: Double = 0 // Total time coming up
    private var tempoRepSamples: Int = 0
    // Legacy 2D tempo thresholds removed; now uses deepDepthThreshold3D / shallowDepthThreshold3D.

    // Hip-based depth calibration (self-calibrates to standing reference each set)
    private var standingHipHeight: Float?
    private var standingLegLength: Float?

    // ROM tracking (depth-based)
    private var sumBottomDepth: Double = 0
    private var bottomDepthSamples: Int = 0
    private var deepFrameCount: Int = 0
    private var totalDepthSamples: Int = 0
    private var currentRepBottomDepthMax: Float = 0

    /// Set by updateTempoTracking when a squat rep completes (before resetting currentRepBottomDepthMax). Used by bodyweight rep commit.
    private var lastCompletedRepDepthAtBottom: Float?

    // MARK: - Bodyweight squat rep-level aggregation (phase-relevant metrics)
    private var bodyweightRepHistory: [BodyweightRepMetrics] = []
    private var bodyweightRepPhase: RepPhase = .idle
    private var currentRepBackAngleMax: Float?
    private var currentRepKneeAlignmentWorst: Float?
    private var bodyweightRepFrameCount: Int = 0
    private var bodyweightKneeWindowSampleCount: Int = 0
    /// Peak `calculateHipDepth3D` during current in-progress rep (for commit).
    private var bodyweightCurrentRepPeakDepth: Float = 0
    private let bodyweightMinFramesInRep = 4
    private let bodyweightMinDepthForViableBottom: Float = 0.22
    private let bodyweightKneeWindowDepthThreshold: Float = 0.24

    override init() {
        super.init()
        // Load MediaPipe model on a background queue so app launch is not blocked.
        // iOS kills the app (SIGKILL) if launch takes too long; the model load is heavy.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.setupMediaPipe()
        }
    }
    
    // MARK: - MediaPipe Setup
    
    private func setupMediaPipe() {
        guard let modelPath = Bundle.main.path(forResource: "pose_landmarker_full", ofType: "task") else {
            return
        }
        
        let options = PoseLandmarkerOptions()
        options.baseOptions.modelAssetPath = modelPath
        options.runningMode = .liveStream
        options.numPoses = 1
        options.minPoseDetectionConfidence = 0.5
        // Slightly lower presence/tracking so we keep landmarks in deep squat (lower body can be partly occluded).
        options.minPosePresenceConfidence = 0.4
        options.minTrackingConfidence = 0.4
        options.poseLandmarkerLiveStreamDelegate = self
        
        do {
            poseLandmarker = try PoseLandmarker(options: options)
        } catch {
        }
    }
    
    // MARK: - Pose Detection
    
    func analyzeFrame(_ pixelBuffer: CVPixelBuffer) {
        guard let poseLandmarker = poseLandmarker else { return }
        
        frameTimestampMs += 33 // ~30 fps; must be monotonically increasing
        let ts = frameTimestampMs
        
        do {
            let mpImage = try MPImage(pixelBuffer: pixelBuffer)
            try poseLandmarker.detectAsync(image: mpImage, timestampInMilliseconds: ts)
        } catch {
            // MediaPipe drops the frame if the previous one is still being processed
        }
    }
    
    /// Called by the PoseLandmarker livestream delegate on a serial queue.
    fileprivate func handleMediaPipeResult(_ result: PoseLandmarkerResult?, timestampMs: Int, error: Error?) {
        guard let result = result,
              let adapted = poseAdapter.adapt(result, timestampMs: timestampMs) else {
            framesSinceGoodPose += 1
            if framesSinceGoodPose >= holdStablePoseFrames {
                DispatchQueue.main.async {
                    self.poseDetected = false
                    self.currentFormAnalysis = nil
                    self.currentNormalizedLandmarks = nil
                }
            }
            return
        }
        
        guard adapted.skeleton.meetsMinimumRequirements(for: trackedExerciseType) else {
            framesSinceGoodPose += 1
            if framesSinceGoodPose >= holdStablePoseFrames {
                DispatchQueue.main.async {
                    self.poseDetected = false
                    self.currentFormAnalysis = nil
                    self.currentNormalizedLandmarks = nil
                }
            }
            return
        }
        
        framesSinceGoodPose = 0
        currentAnalysisSource = .pose3D
        
        let smoothed = jointSmoother.smooth(adapted.skeleton)
        lastSmoothedSkeleton = smoothed
        let landmarks = overlayLandmarkSmoother.smooth(adapted.overlayLandmarks)
        if trackedExerciseType == .bodyweight {
            updateBodyweightViewpointAndExtension(overlay: landmarks, skeleton: smoothed, confidence: adapted.perJointConfidence)
        }
        let formAnalysis = formAnalysisFrom3D(skeleton: smoothed)
        
        let tempoDepth: Float = {
            switch trackedExerciseType {
            case .bodyweight, .barbell, .benchPress:
                return calculateHipDepth3D(smoothed)
            case .closeGripBenchPress:
                return formAnalysis.depth
            }
        }()
        updateTempoTracking(currentDepth: tempoDepth)
        
        DispatchQueue.main.async {
            self.poseDetected = true
            self.currentFormAnalysis = formAnalysis
            self.currentNormalizedLandmarks = landmarks
            self.inactivityDetector.updateLastActivity()
        }
        
        aggregateFeedback(from: formAnalysis)
        
        // Rep counting should not advance while we're in setup mode (e.g. test overlays).
        // Set start may be explicit (Track `startManualSet`) or rep-driven (`checkForNextSetStart` after reps while `.waiting`).
        // The squat rep state machine is advanced only from this path (never from `checkForNextSetStart`).
        if !SharedCameraSessionManager.shared.isInSetupMode,
           !SharedCameraSessionManager.shared.suppressRepCounting {
            let now = Date()
            if validateRep(skeleton: smoothed, overlay: landmarks, formAnalysis: formAnalysis, now: now) {
                if trackedExerciseType == .bodyweight {
                    commitBodyweightRepIfNeeded()
                }
                DispatchQueue.main.async {
                    self.handleRepDetected()
                }
            }

            DispatchQueue.main.async {
                if !SharedCameraSessionManager.shared.trackExplicitSetActive {
                    self.checkForSetEnd()
                }
                self.checkForNextSetStart()
            }
        }
    }
    
    // MARK: - Form Analysis (2D overlay)

    private func analyzeFormFrom2DOverlay(_ points: [String: CGPoint]) -> FormAnalysis {
        switch trackedExerciseType {
        case .bodyweight:
            return analyzeBodyweightSquatForm(points)
        case .barbell:
            return analyzeBarbellSquatForm(points)
        case .benchPress:
            return analyzeBodyweightSquatForm(points)
        case .closeGripBenchPress:
            return analyzeCloseGripBenchPressForm(points)
        }
    }
    
    private func analyzeBodyweightSquatForm(_ points: [String: CGPoint]) -> FormAnalysis {
        let depth = calculateBodyweightDepth(points)
        let backAngle = calculateBodyweightBackAngle(points)
        let kneeAlignment = calculateBodyweightKneeAlignment(points)
        let overallScore = calculateBodyweightOverallScore(depth: depth, backAngle: backAngle, kneeAlignment: kneeAlignment)
        let issues = detectBodyweightIssues(depth: depth, backAngle: backAngle, kneeAlignment: kneeAlignment)
        let summary = generateBodyweightFormSummary(depth: depth, backAngle: backAngle, overallScore: overallScore)
        
        return FormAnalysis(
            depth: depth, backAngle: backAngle, kneeAlignment: kneeAlignment,
            overallScore: overallScore, issues: issues, summary: summary,
            repCount: repCount,
            avgEccentricMs: tempoRepSamples > 0 ? Float(sumEccentricMs / Double(tempoRepSamples)) : nil,
            avgPauseMs: tempoRepSamples > 0 ? Float(sumPauseMs / Double(tempoRepSamples)) : nil,
            avgConcentricMs: tempoRepSamples > 0 ? Float(sumConcentricMs / Double(tempoRepSamples)) : nil,
            avgBottomDepth: bottomDepthSamples > 0 ? Float(sumBottomDepth / Double(bottomDepthSamples)) : nil,
            deepRepRatio: totalDepthSamples > 0 ? Float(deepFrameCount) / Float(totalDepthSamples) : nil
        )
    }
    
    private func analyzeBarbellSquatForm(_ points: [String: CGPoint]) -> FormAnalysis {
        let depth = calculateDepth(points)
        let backAngle = calculateBackAngle(points)
        let overallScore = calculateOverallScore(depth: depth, backAngle: backAngle)
        let summary = generateFormSummary(depth: depth, backAngle: backAngle, overallScore: overallScore)
        
        return FormAnalysis(
            depth: depth, backAngle: backAngle, kneeAlignment: 0.0,
            overallScore: overallScore, issues: [], summary: summary,
            repCount: repCount,
            avgEccentricMs: nil as Float?, avgPauseMs: nil as Float?, avgConcentricMs: nil as Float?,
            avgBottomDepth: nil as Float?, deepRepRatio: nil as Float?
        )
    }
    
    // MARK: - Close-Grip Bench Press Form Analysis
    
    /// Analyzes close-grip bench press form with view-specific adjustments for camera angle.
    ///
    /// Form Metrics (weighted scoring):
    /// - **Grip width (20%)**: Should be just outside ribs (0.8-1.0x shoulder width)
    /// - **Elbow position (20%)**: Should be flush to sides (not flared out)
    /// - **Full ROM (30%)**: Elbows locked at top, bar touches chest at bottom
    /// - **Eccentric tempo (15%)**: Lowering phase should be ≥1 second
    /// - **Concentric tempo (15%)**: Pressing phase should be ≤2 seconds
    ///
    /// View-specific adjustments account for camera angle differences:
    /// - Rack view (top-down): Adjusts for compressed width perception
    /// - Floor view (bottom-up): Adjusts for expanded width perception
    /// - Tripod view (side): Standard calculations
    private func analyzeCloseGripBenchPressForm(_ points: [String: CGPoint]) -> FormAnalysis {
        // Calculate close-grip bench press specific metrics
        let gripWidthScore = calculateCloseGripWidthScore(points)
        let elbowPositionScore = calculateElbowPositionScore(points)
        let romScore = calculateBenchPressROMScore(points)
        
        // Get tempo scores (from accumulated tracking data)
        let eccentricScore = calculateBenchPressEccentricScore()
        let concentricScore = calculateBenchPressConcentricScore()
        
        // Calculate overall score with weights:
        // - Grip width: 20%
        // - Elbow position: 20%
        // - Full ROM: 30%
        // - Eccentric tempo: 15%
        // - Concentric tempo: 15%
        let overallScore = (gripWidthScore * 0.20) +
                           (elbowPositionScore * 0.20) +
                           (romScore * 0.30) +
                           (eccentricScore * 0.15) +
                           (concentricScore * 0.15)
        
        
        var issues: [IssueCode] = []
        if gripWidthScore < CoachingContract.Threshold.gripTooWide { issues.append(.gripTooWide) }
        if elbowPositionScore < CoachingContract.Threshold.elbowsFlaring { issues.append(.elbowsFlaring) }
        if romScore < CoachingContract.Threshold.incompleteRom { issues.append(.incompleteRom) }
        if eccentricScore < CoachingContract.Threshold.eccentricTooFast { issues.append(.eccentricTooFast) }
        if concentricScore < CoachingContract.Threshold.concentricTooSlow { issues.append(.concentricTooSlow) }
        
        let summary = generateCloseGripBenchPressSummary(
            gripScore: gripWidthScore,
            elbowScore: elbowPositionScore,
            romScore: romScore,
            overallScore: overallScore
        )
        
        // Use the depth field to store wrist Y position for rep detection
        let depth = calculateBenchPressDepth(points)
        
        return FormAnalysis(
            depth: depth,
            backAngle: 0.0, // Not relevant for bench press
            kneeAlignment: 0.0, // Not relevant for bench press
            overallScore: overallScore,
            issues: issues,
            summary: summary,
            repCount: repCount,
            avgEccentricMs: tempoRepSamples > 0 ? Float(sumEccentricMs / Double(tempoRepSamples)) : nil,
            avgPauseMs: tempoRepSamples > 0 ? Float(sumPauseMs / Double(tempoRepSamples)) : nil,
            avgConcentricMs: tempoRepSamples > 0 ? Float(sumConcentricMs / Double(tempoRepSamples)) : nil,
            avgBottomDepth: nil,
            deepRepRatio: nil
        )
    }
    
    /// Calculates grip width score for close-grip bench press.
    /// 
    /// **Ideal Grip:** 0.8-1.0x shoulder width (just outside ribs)
    /// 
    /// **Scoring (Lenient):**
    /// - Acceptable range: 0.7-1.2x shoulder width (score: 1.0)
    /// - Too narrow: Minimum score 0.5 (was 0.3)
    /// - Too wide: Minimum score 0.5 (was 0.3)
    /// 
    /// **View Adjustments:** Applies camera angle corrections for rack/floor/tripod views.
    private func calculateCloseGripWidthScore(_ points: [String: CGPoint]) -> Float {
        guard let leftWrist = points["leftWrist"],
              let rightWrist = points["rightWrist"],
              let leftShoulder = points["leftShoulder"],
              let rightShoulder = points["rightShoulder"] else {
            return 0.5 // Default score if points not detected
        }
        
        // Calculate grip width relative to shoulder width
        let gripWidth = abs(leftWrist.x - rightWrist.x)
        let shoulderWidth = abs(leftShoulder.x - rightShoulder.x)
        
        guard shoulderWidth > 0 else { return 0.5 }
        
        // Ideal grip width for close-grip is 0.8-1.0x shoulder width (just outside ribs)
        // Regular bench press would be 1.5x+ shoulder width
        let gripRatio = Float(gripWidth / shoulderWidth)
        
        // View-specific adjustments
        let adjustedGripRatio: Float
        switch benchPressViewType {
        case .rack:
            // Top-down view may compress perceived width
            adjustedGripRatio = gripRatio * 1.1
        case .floor:
            // Bottom-up view may expand perceived width
            adjustedGripRatio = gripRatio * 0.95
        case .tripod:
            // Side view is most accurate
            adjustedGripRatio = gripRatio
        }
        
        // Score calculation: ideal is 0.8-1.0, penalize outside this range
        // Made more lenient: wider acceptable range and less harsh penalties
        if adjustedGripRatio >= 0.7 && adjustedGripRatio <= 1.2 {
            return 1.0 // Perfect or acceptable close-grip width
        } else if adjustedGripRatio < 0.7 {
            // Grip too narrow - more lenient
            return max(0.5, adjustedGripRatio / 0.7)
        } else {
            // Grip too wide - more lenient
            let overWidth = adjustedGripRatio - 1.2
            return max(0.5, 1.0 - (overWidth * 1.0))
        }
    }
    
    /// Calculates elbow position score for close-grip bench press.
    /// 
    /// **Ideal Position:** Elbows flush to sides (not flared out)
    /// 
    /// **Scoring (Lenient):**
    /// - Acceptable range: flare ratio ≤ 0.6 (score: 1.0)
    /// - Slightly flared (0.6-0.8): Score 0.7-1.0
    /// - Significantly flared (>0.8): Minimum score 0.5 (was 0.3)
    /// 
    /// **View Adjustments:** Applies camera angle corrections for rack/floor/tripod views.
    private func calculateElbowPositionScore(_ points: [String: CGPoint]) -> Float {
        guard let leftElbow = points["leftElbow"],
              let rightElbow = points["rightElbow"],
              let leftShoulder = points["leftShoulder"],
              let rightShoulder = points["rightShoulder"],
              let leftHip = points["leftHip"],
              let rightHip = points["rightHip"] else {
            return 0.5 // Default score if points not detected
        }
        
        // Calculate elbow distance from torso midline
        let torsoMidlineX = (leftShoulder.x + rightShoulder.x + leftHip.x + rightHip.x) / 4.0
        let shoulderWidth = abs(leftShoulder.x - rightShoulder.x)
        
        guard shoulderWidth > 0 else { return 0.5 }
        
        // Calculate how far elbows are from the body
        let leftElbowOffset = abs(leftElbow.x - torsoMidlineX)
        let rightElbowOffset = abs(rightElbow.x - torsoMidlineX)
        let avgElbowOffset = (leftElbowOffset + rightElbowOffset) / 2.0
        
        // Normalize to shoulder width
        let elbowFlareRatio = Float(avgElbowOffset / shoulderWidth)
        
        // View-specific adjustments
        let adjustedFlareRatio: Float
        switch benchPressViewType {
        case .rack:
            // Top-down view makes elbows appear more tucked
            adjustedFlareRatio = elbowFlareRatio * 1.15
        case .floor:
            // Bottom-up view makes elbows appear more flared
            adjustedFlareRatio = elbowFlareRatio * 0.9
        case .tripod:
            adjustedFlareRatio = elbowFlareRatio
        }
        
        // For close-grip, elbows should be tucked (ratio < 0.5)
        // Score calculation: ideal is 0.3-0.5 (flush to sides)
        // Made more lenient: accept wider range and less harsh penalties
        if adjustedFlareRatio <= 0.6 {
            return 1.0 // Perfect or acceptable elbow position
        } else if adjustedFlareRatio <= 0.8 {
            // Slightly flared - more lenient
            return max(0.7, 1.0 - ((adjustedFlareRatio - 0.6) * 0.75))
        } else {
            // Significantly flared - more lenient
            return max(0.5, 0.85 - ((adjustedFlareRatio - 0.8) * 0.7))
        }
    }
    
    /// Calculates range of motion score for close-grip bench press.
    /// 
    /// **Checks:** Full lockout at top and chest touch at bottom
    /// 
    /// **Scoring (Lenient for Tripod View):**
    /// - Good lockout: Elbow extension > 0.05 (score: 1.0)
    /// - Partial lockout: Extension > 0 (score: 0.8-1.0, was 0.7)
    /// - Incomplete extension: Minimum score 0.6 (was 0.3)
    /// 
    /// **View-Specific:** Uses different reference points for rack/floor/tripod camera angles.
    private func calculateBenchPressROMScore(_ points: [String: CGPoint]) -> Float {
        guard let leftWrist = points["leftWrist"],
              let rightWrist = points["rightWrist"],
              let leftElbow = points["leftElbow"],
              let rightElbow = points["rightElbow"],
              let leftShoulder = points["leftShoulder"],
              let rightShoulder = points["rightShoulder"] else {
            return 0.5 // Default score if points not detected
        }
        
        // Calculate average positions
        let avgWristY = Float((leftWrist.y + rightWrist.y) / 2.0)
        let avgElbowY = Float((leftElbow.y + rightElbow.y) / 2.0)
        let avgShoulderY = Float((leftShoulder.y + rightShoulder.y) / 2.0)
        
        // View-specific ROM assessment
        switch benchPressViewType {
        case .rack:
            // Top-down view: Use Y position relative to shoulders
            // At lockout: wrists should be above (lower Y) than shoulders
            // At bottom: wrists should be at or below shoulder level
            let lockoutScore: Float = avgWristY < avgShoulderY ? 1.0 : max(0.3, 1.0 - (avgWristY - avgShoulderY) * 2)
            return lockoutScore
            
        case .floor:
            // Bottom-up view: Similar assessment but inverted Y
            let lockoutScore: Float = avgWristY > avgShoulderY ? 1.0 : max(0.3, 1.0 - (avgShoulderY - avgWristY) * 2)
            return lockoutScore
            
        case .tripod:
            // Side view: Assess elbow extension
            // At lockout: wrist should be significantly above elbow (lower Y in normalized image coords)
            // Made more lenient: accept smaller extension and give higher minimum scores
            let elbowExtension = avgElbowY - avgWristY
            if elbowExtension > 0.05 {
                return 1.0 // Good lockout
            } else if elbowExtension > 0 {
                return max(0.8, 0.7 + (elbowExtension * 2.0)) // Partial lockout - more lenient
            } else {
                return max(0.6, 0.7 + elbowExtension) // Incomplete extension - more lenient
            }
        }
    }
    
    /// Calculates bench press depth using average wrist Y position for rep detection.
    /// Higher Y = deeper/lower bar position (normalized image coords, Y down).
    private func calculateBenchPressDepth(_ points: [String: CGPoint]) -> Float {
        guard let leftWrist = points["leftWrist"],
              let rightWrist = points["rightWrist"] else {
            return 0.5
        }
        
        // Average wrist Y position (higher Y = deeper/lower bar in normalized image coords)
        return Float((leftWrist.y + rightWrist.y) / 2.0)
    }
    
    /// Calculates eccentric (lowering) tempo score.
    /// 
    /// **Target:** ≥1000ms (1 second) for controlled lowering
    /// 
    /// **Scoring (Lenient):**
    /// - ≥800ms: Score 1.0 (was ≥1000ms)
    /// - ≥600ms: Score 0.9
    /// - ≥400ms: Score 0.75
    /// - <400ms: Minimum score 0.6 (was 0.3)
    /// 
    /// **Default:** Returns 0.8 if no tempo data available (was 0.7)
    private func calculateBenchPressEccentricScore() -> Float {
        guard tempoRepSamples > 0 else { return 0.8 }
        
        let avgEccentricMs = sumEccentricMs / Double(tempoRepSamples)
        
        if avgEccentricMs >= 800 {
            return 1.0
        } else if avgEccentricMs >= 600 {
            return 0.9
        } else if avgEccentricMs >= 400 {
            return 0.75
        } else {
            return max(0.6, Float(avgEccentricMs / 800.0))
        }
    }
    
    /// Calculates concentric (pressing) tempo score.
    /// 
    /// **Target:** ≤2000ms (2 seconds) for explosive pressing
    /// 
    /// **Scoring (Lenient):**
    /// - ≤3000ms: Score 1.0 (was ≤2000ms)
    /// - ≤4000ms: Score 0.9
    /// - ≤5000ms: Score 0.75
    /// - >5000ms: Minimum score 0.6 (was 0.3)
    /// 
    /// **Default:** Returns 0.8 if no tempo data available (was 0.7)
    private func calculateBenchPressConcentricScore() -> Float {
        guard tempoRepSamples > 0 else { return 0.8 }
        
        let avgConcentricMs = sumConcentricMs / Double(tempoRepSamples)
        
        if avgConcentricMs <= 3000 {
            return 1.0
        } else if avgConcentricMs <= 4000 {
            return 0.9
        } else if avgConcentricMs <= 5000 {
            return 0.75
        } else {
            return max(0.6, Float(3000.0 / avgConcentricMs))
        }
    }
    
    /// Generate summary for close-grip bench press form analysis
    private func generateCloseGripBenchPressSummary(gripScore: Float, elbowScore: Float, romScore: Float, overallScore: Float) -> String {
        var summaryParts: [String] = []
        
        // Add positive feedback first
        if gripScore >= 0.8 {
            summaryParts.append("good grip width")
        }
        if elbowScore >= 0.8 {
            summaryParts.append("elbows tucked well")
        }
        if romScore >= 0.8 {
            summaryParts.append("full range of motion")
        }
        
        // Add areas for improvement
        if gripScore < 0.6 {
            summaryParts.append("grip too wide")
        }
        if elbowScore < 0.6 {
            summaryParts.append("elbows flaring out")
        }
        if romScore < 0.6 {
            summaryParts.append("incomplete lockout or depth")
        }
        
        if summaryParts.isEmpty {
            return "Solid close-grip bench press form"
        }
        
        return summaryParts.joined(separator: ", ")
    }
    
    // MARK: - 3D Form Analysis
    
    /// Dispatches to exercise-specific 3D form analysis.
    /// Bodyweight: computes frame metrics, updates rep accumulation, then aggregates from rep history or fallback.
    private func formAnalysisFrom3D(skeleton: Skeleton3D) -> FormAnalysis {
        switch trackedExerciseType {
        case .bodyweight:
            let depth = calculateHipDepth3D(skeleton)
            let backAngle = calculateBackAngle3D(skeleton)
            let kneeAlignment = calculateKneeAlignment3D(skeleton)
            updateBodyweightRepAccumulation(depth: depth, backAngle: backAngle, kneeAlignment: kneeAlignment)
            return analyzeBodyweightSquatFromRepHistory(
                repHistory: bodyweightRepHistory,
                fallback: FrameMetrics(depth: depth, backAngle: backAngle, kneeAlignment: kneeAlignment),
                viewpointProfile: activeBodyweightRepProfile
            )
        case .barbell, .benchPress:
            return analyzeSquatForm3D(skeleton)
        case .closeGripBenchPress:
            return analyzeCloseGripBenchPressForm3D(skeleton)
        }
    }

    // MARK: - Bodyweight Rep Accumulation (phase-relevant)

    private func updateBodyweightRepAccumulation(depth: Float, backAngle: Float, kneeAlignment: Float) {
        let startDepth = activeBodyweightRepProfile.repAccumulationStartDepth
        let kneeDepthLine = max(
            bodyweightKneeWindowDepthThreshold,
            activeBodyweightRepProfile.repCountDepthThreshold * 0.92
        )
        switch bodyweightRepPhase {
        case .idle:
            if depth >= startDepth {
                bodyweightRepPhase = .accumulating
                bodyweightRepFrameCount = 0
                bodyweightKneeWindowSampleCount = 0
                bodyweightCurrentRepPeakDepth = depth
                currentRepBackAngleMax = nil
                currentRepKneeAlignmentWorst = nil
            }
        case .accumulating:
            bodyweightCurrentRepPeakDepth = max(bodyweightCurrentRepPeakDepth, depth)
            bodyweightRepFrameCount += 1
            if let cur = currentRepBackAngleMax {
                currentRepBackAngleMax = max(cur, backAngle)
            } else {
                currentRepBackAngleMax = backAngle
            }
            if depth > kneeDepthLine {
                bodyweightKneeWindowSampleCount += 1
                if let cur = currentRepKneeAlignmentWorst {
                    currentRepKneeAlignmentWorst = min(cur, kneeAlignment)
                } else {
                    currentRepKneeAlignmentWorst = kneeAlignment
                }
            }
        }
    }

    /// Clears in-progress bodyweight rep accumulation (squat rep cycle abandoned before count).
    private func abortInProgressBodyweightRepAccumulation() {
        bodyweightRepPhase = .idle
        bodyweightRepFrameCount = 0
        bodyweightKneeWindowSampleCount = 0
        bodyweightCurrentRepPeakDepth = 0
        currentRepBackAngleMax = nil
        currentRepKneeAlignmentWorst = nil
    }

    // MARK: - Bodyweight Set-Level Aggregation

    /// Builds FormAnalysis from rep history using recurring-pattern rules; falls back to frame metrics when no valid reps.
    private func analyzeBodyweightSquatFromRepHistory(
        repHistory: [BodyweightRepMetrics],
        fallback: FrameMetrics,
        viewpointProfile: SquatRepDetectionProfile
    ) -> FormAnalysis {
        let validReps = repHistory.filter { $0.valid }
        guard !validReps.isEmpty else {
            return buildFormAnalysisFromFrameMetrics(fallback, viewpointProfile: viewpointProfile)
        }

        let depthAtBottomMin = validReps.map(\.depthAtBottom).min() ?? fallback.depth
        let backAngleMaxOverall = validReps.map(\.backAngleMax).max() ?? fallback.backAngle
        let kneeWorstOverall = validReps.map(\.kneeAlignmentWorstNearBottom).min() ?? fallback.kneeAlignment

        let leanCount = validReps.filter(\.excessiveForwardLean).count
        let valgusCount = validReps.filter(\.kneeValgus).count
        let n = validReps.count
        let valgusPct = n > 0 ? Float(valgusCount) / Float(n) : 0
        let leanPct = n > 0 ? Float(leanCount) / Float(n) : 0

        let backAngle75th: Float = {
            let sorted = validReps.map(\.backAngleMax).sorted()
            let idx = Int(Float(sorted.count) * 0.75)
            return sorted[min(idx, sorted.count - 1)]
        }()

        let p = viewpointProfile
        let depthShallowLine = CoachingContract.Threshold.depthShallow * max(0.45, min(1.15, p.formWeightDepth))
        let forwardLeanLine = CoachingContract.Threshold.forwardLean / max(0.55, min(1.25, p.formWeightForwardLean))
        let valgusRepFloor = max(2, Int(ceil(2.0 / Double(max(0.5, p.formWeightKneeTracking)))))
        let valgusPctLine = min(0.5, 0.25 * Float(p.formIssueEvidenceMultiplier) / max(0.55, p.formWeightKneeTracking))
        let leanRepFloor = max(2, Int(ceil(2.0 * Double(p.formIssueEvidenceMultiplier) / Double(max(0.65, p.formWeightForwardLean)))))
        let leanPctLine = min(0.45, 0.25 * Float(p.formIssueEvidenceMultiplier) / max(0.55, p.formWeightForwardLean))

        var issues: [IssueCode] = []
        if depthAtBottomMin < depthShallowLine {
            issues.append(.insufficientDepth)
        }
        if leanCount >= leanRepFloor || (n > 0 && leanPct >= leanPctLine) || backAngle75th > forwardLeanLine {
            issues.append(.forwardLean)
        }
        if valgusCount >= valgusRepFloor || (n > 0 && valgusPct >= valgusPctLine) {
            issues.append(.kneeValgus)
        } else if validReps.contains(where: { $0.kneeAlignmentWorstNearBottom > CoachingContract.Threshold.kneeVarus }) {
            let varusCount = validReps.filter { $0.kneeAlignmentWorstNearBottom > CoachingContract.Threshold.kneeVarus }.count
            let varusFloor = max(2, Int(ceil(Double(valgusRepFloor) * Double(p.formIssueEvidenceMultiplier) * 0.9)))
            if varusCount >= varusFloor || (n > 0 && Float(varusCount) / Float(n) >= valgusPctLine) {
                issues.append(.kneeVarus)
            }
        }
        let parallelMiss = validReps.filter { !$0.hipKneeDepthQualityMet }.count
        let goodDepthLine = p.repGoodDepthThreshold
        if n >= 2,
           parallelMiss >= 2,
           Float(parallelMiss) / Float(n) >= 0.5,
           depthAtBottomMin >= goodDepthLine * 0.95,
           !issues.contains(.insufficientDepth) {
            issues.append(.insufficientDepth)
        }
        issues = Array(issues.prefix(CoachingContract.maxIssuesInPayload))

        let overallScore = calculateOverallScore3D(
            depth: depthAtBottomMin,
            backAngle: backAngleMaxOverall,
            kneeAlignment: kneeWorstOverall,
            exerciseType: .bodyweight
        )
        let summary = generateFormSummary3D(
            depth: depthAtBottomMin,
            backAngle: backAngleMaxOverall,
            overallScore: overallScore
        )

        return FormAnalysis(
            depth: depthAtBottomMin,
            backAngle: backAngleMaxOverall,
            kneeAlignment: kneeWorstOverall,
            overallScore: overallScore,
            issues: issues,
            summary: summary,
            repCount: repCount,
            avgEccentricMs: tempoRepSamples > 0 ? Float(sumEccentricMs / Double(tempoRepSamples)) : nil,
            avgPauseMs: tempoRepSamples > 0 ? Float(sumPauseMs / Double(tempoRepSamples)) : nil,
            avgConcentricMs: tempoRepSamples > 0 ? Float(sumConcentricMs / Double(tempoRepSamples)) : nil,
            avgBottomDepth: bottomDepthSamples > 0 ? Float(sumBottomDepth / Double(bottomDepthSamples)) : nil,
            deepRepRatio: totalDepthSamples > 0 ? Float(deepFrameCount) / Float(totalDepthSamples) : nil
        )
    }

    private func buildFormAnalysisFromFrameMetrics(
        _ f: FrameMetrics,
        viewpointProfile: SquatRepDetectionProfile? = nil
    ) -> FormAnalysis {
        let overallScore = calculateOverallScore3D(
            depth: f.depth,
            backAngle: f.backAngle,
            kneeAlignment: f.kneeAlignment,
            exerciseType: trackedExerciseType
        )
        let issues: [IssueCode]
        if trackedExerciseType == .bodyweight, let vp = viewpointProfile {
            issues = detectBodyweightIssues3DWithViewpoint(
                depth: f.depth,
                backAngle: f.backAngle,
                kneeAlignment: f.kneeAlignment,
                profile: vp
            )
        } else {
            issues = detectIssues3D(depth: f.depth, backAngle: f.backAngle, kneeAlignment: f.kneeAlignment)
        }
        let summary = generateFormSummary3D(
            depth: f.depth,
            backAngle: f.backAngle,
            overallScore: overallScore
        )
        return FormAnalysis(
            depth: f.depth,
            backAngle: f.backAngle,
            kneeAlignment: f.kneeAlignment,
            overallScore: overallScore,
            issues: issues,
            summary: summary,
            repCount: repCount,
            avgEccentricMs: tempoRepSamples > 0 ? Float(sumEccentricMs / Double(tempoRepSamples)) : nil,
            avgPauseMs: tempoRepSamples > 0 ? Float(sumPauseMs / Double(tempoRepSamples)) : nil,
            avgConcentricMs: tempoRepSamples > 0 ? Float(sumConcentricMs / Double(tempoRepSamples)) : nil,
            avgBottomDepth: bottomDepthSamples > 0 ? Float(sumBottomDepth / Double(bottomDepthSamples)) : nil,
            deepRepRatio: totalDepthSamples > 0 ? Float(deepFrameCount) / Float(totalDepthSamples) : nil
        )
    }
    
    // MARK: - 3D Squat Form Analysis
    
    private func analyzeSquatForm3D(_ skeleton: Skeleton3D) -> FormAnalysis {
        let movementDepthScore = calculateHipDepth3D(skeleton)
        let backAngle = calculateBackAngle3D(skeleton)
        let kneeAlignment = calculateKneeAlignment3D(skeleton)
        let overallScore = calculateOverallScore3D(
            depth: movementDepthScore, backAngle: backAngle, kneeAlignment: kneeAlignment,
            exerciseType: .barbell
        )
        let issues = detectIssues3D(
            depth: movementDepthScore, backAngle: backAngle, kneeAlignment: kneeAlignment
        )
        let summary = generateFormSummary3D(
            depth: movementDepthScore, backAngle: backAngle, overallScore: overallScore
        )
        
        return FormAnalysis(
            depth: movementDepthScore,
            backAngle: backAngle,
            kneeAlignment: kneeAlignment,
            overallScore: overallScore,
            issues: issues,
            summary: summary,
            repCount: repCount,
            avgEccentricMs: tempoRepSamples > 0 ? Float(sumEccentricMs / Double(tempoRepSamples)) : nil,
            avgPauseMs: tempoRepSamples > 0 ? Float(sumPauseMs / Double(tempoRepSamples)) : nil,
            avgConcentricMs: tempoRepSamples > 0 ? Float(sumConcentricMs / Double(tempoRepSamples)) : nil,
            avgBottomDepth: bottomDepthSamples > 0 ? Float(sumBottomDepth / Double(bottomDepthSamples)) : nil,
            deepRepRatio: totalDepthSamples > 0 ? Float(deepFrameCount) / Float(totalDepthSamples) : nil
        )
    }
    
    /// Hip-to-foot vertical displacement depth, normalized by leg length. Body-proportion invariant.
    /// Self-calibrates: tracks the maximum hip height seen (standing reference).
    /// Falls back to knee-angle depth until calibration data is available.
    private func calculateHipDepth3D(_ skeleton: Skeleton3D) -> Float {
        guard let leftHip = skeleton.position("leftHip"),
              let rightHip = skeleton.position("rightHip"),
              let leftAnkle = skeleton.position("leftAnkle"),
              let rightAnkle = skeleton.position("rightAnkle") else { return 0.5 }

        let hipCenter = (leftHip + rightHip) / 2.0
        let ankleCenter = (leftAnkle + rightAnkle) / 2.0
        let currentHipHeight = hipCenter.y - ankleCenter.y

        let currentLegLen = length(hipCenter - ankleCenter)
        if currentHipHeight > (standingHipHeight ?? 0) {
            standingHipHeight = currentHipHeight
            standingLegLength = currentLegLen
        }

        guard let refHeight = standingHipHeight,
              let legLen = standingLegLength, legLen > 0.01 else {
            return calculateMovementDepthScore3D_legacy(skeleton)
        }

        let displacement = refHeight - currentHipHeight
        let depthRaw = displacement / legLen
        return max(0, min(1, depthRaw))
    }

    /// Legacy knee-angle based depth. Used as fallback before hip-height calibration.
    private func calculateMovementDepthScore3D_legacy(_ skeleton: Skeleton3D) -> Float {
        guard let leftHip = skeleton.position("leftHip"),
              let rightHip = skeleton.position("rightHip"),
              let leftKnee = skeleton.position("leftKnee"),
              let rightKnee = skeleton.position("rightKnee"),
              let leftAnkle = skeleton.position("leftAnkle"),
              let rightAnkle = skeleton.position("rightAnkle") else {
            return 0.5
        }

        let leftKneeAngle = angleDegrees(a: leftHip, b: leftKnee, c: leftAnkle)
        let rightKneeAngle = angleDegrees(a: rightHip, b: rightKnee, c: rightAnkle)
        let avgKneeAngle = (leftKneeAngle + rightKneeAngle) / 2.0

        return max(0, min(1, (170 - avgKneeAngle) / 110))
    }
    
    /// Torso lean angle from vertical, computed from 3D shoulder/hip vectors.
    private func calculateBackAngle3D(_ skeleton: Skeleton3D) -> Float {
        guard let leftShoulder = skeleton.position("leftShoulder"),
              let rightShoulder = skeleton.position("rightShoulder"),
              let leftHip = skeleton.position("leftHip"),
              let rightHip = skeleton.position("rightHip") else {
            return 0.0
        }
        
        let shoulderCenter = (leftShoulder + rightShoulder) / 2.0
        let hipCenter = (leftHip + rightHip) / 2.0
        let torso = shoulderCenter - hipCenter
        let lenTorso = length(torso)
        guard lenTorso > .ulpOfOne else { return 0.0 }
        
        let vertical = SIMD3<Float>(0, 1, 0)
        let cosAngle = dot(torso / lenTorso, vertical)
        return acos(max(-1, min(1, cosAngle))) * 180.0 / .pi
    }
    
    /// Lateral knee tracking relative to ankles in 3D.
    private func calculateKneeAlignment3D(_ skeleton: Skeleton3D) -> Float {
        guard let leftKnee = skeleton.position("leftKnee"),
              let rightKnee = skeleton.position("rightKnee"),
              let leftAnkle = skeleton.position("leftAnkle"),
              let rightAnkle = skeleton.position("rightAnkle") else {
            return 0.0
        }
        
        let leftTracking = leftKnee.x - leftAnkle.x
        let rightTracking = rightKnee.x - rightAnkle.x
        let avg = (leftTracking + rightTracking) / 2.0
        return max(-1, min(1, avg / 0.05))
    }
    
    // MARK: - Sub-Score Helpers (config-driven, body-proportion invariant)

    /// Linear ramp between depthMinThreshold (score 0) and depthTarget (score 1).
    private func computeDepthScore(_ depth: Float, config: SquatScoringConfig) -> Float {
        if depth >= config.depthTarget { return 1.0 }
        if depth <= config.depthMinThreshold { return 0.0 }
        return (depth - config.depthMinThreshold)
             / (config.depthTarget - config.depthMinThreshold)
    }

    /// Banded: perfect up to anglePerfectMax, gradual taper to 0.65 at angleAcceptableMax,
    /// then steeper penalty beyond.
    private func computeAngleScore(_ backAngle: Float, config: SquatScoringConfig) -> Float {
        if backAngle <= config.anglePerfectMax { return 1.0 }
        if backAngle <= config.angleAcceptableMax {
            let t = (backAngle - config.anglePerfectMax)
                  / (config.angleAcceptableMax - config.anglePerfectMax)
            return 1.0 - t * 0.35
        }
        let excess = backAngle - config.angleAcceptableMax
        return max(0, 0.65 - excess / 60.0)
    }

    /// Asymmetric: valgus (kneeAlignment < 0) is penalized heavily; varus only mildly.
    private func computeAlignmentScore(_ kneeAlignment: Float, config: SquatScoringConfig) -> Float {
        if kneeAlignment < config.valgusHeavyPenaltyBelow {
            let severity = abs(kneeAlignment - config.valgusHeavyPenaltyBelow)
            return max(0, 0.5 - severity * 0.5)
        }
        if kneeAlignment < 0 {
            let t = abs(kneeAlignment) / abs(config.valgusHeavyPenaltyBelow)
            return 1.0 - t * 0.5
        }
        if kneeAlignment > config.varusMildPenaltyAbove {
            let excess = kneeAlignment - config.varusMildPenaltyAbove
            return max(0.7, 1.0 - excess * 0.3)
        }
        return 1.0
    }

    /// Weighted overall score with exercise-type config and a minimum score floor
    /// for reps that are clearly adequate on depth and alignment.
    private func calculateOverallScore3D(
        depth: Float, backAngle: Float, kneeAlignment: Float,
        exerciseType: TrackedExerciseType
    ) -> Float {
        let config: SquatScoringConfig = (exerciseType == .barbell) ? .barbell : .bodyweight

        let depthScore = computeDepthScore(depth, config: config)
        let angleScore = computeAngleScore(backAngle, config: config)
        let alignmentScore = computeAlignmentScore(kneeAlignment, config: config)

        var score = depthScore * config.weightDepth
                  + angleScore * config.weightAngle
                  + alignmentScore * config.weightAlignment
        score = min(score, 1.0)

        if depthScore >= config.scoreFloorDepthMin
            && alignmentScore >= config.scoreFloorAlignMin
            && backAngle <= config.scoreFloorAngleMax {
            score = max(score, config.scoreFloor)
        }

        return score
    }
    
    private func detectIssues3D(depth: Float, backAngle: Float, kneeAlignment: Float) -> [IssueCode] {
        var issues: [IssueCode] = []
        if depth < CoachingContract.Threshold.depthShallow { issues.append(.insufficientDepth) }
        if backAngle > CoachingContract.Threshold.forwardLean { issues.append(.forwardLean) }
        if kneeAlignment < CoachingContract.Threshold.kneeValgus {
            issues.append(.kneeValgus)
        } else if kneeAlignment > CoachingContract.Threshold.kneeVarus {
            issues.append(.kneeVarus)
        }
        return Array(issues.prefix(CoachingContract.maxIssuesInPayload))
    }

    /// Single-frame issue hints for bodyweight with viewpoint-aware thresholds (fallback when no rep history).
    private func detectBodyweightIssues3DWithViewpoint(
        depth: Float,
        backAngle: Float,
        kneeAlignment: Float,
        profile: SquatRepDetectionProfile
    ) -> [IssueCode] {
        var issues: [IssueCode] = []
        let depthLine = CoachingContract.Threshold.depthShallow * max(0.45, min(1.15, profile.formWeightDepth))
        let leanLine = CoachingContract.Threshold.forwardLean / max(0.55, min(1.25, profile.formWeightForwardLean))
        let wKnee = min(1.2, max(0.5, profile.formWeightKneeTracking))
        let kneeValgusLine = CoachingContract.Threshold.kneeValgus - (1.0 - wKnee) * 0.12
        let kneeVarusLine = CoachingContract.Threshold.kneeVarus + (1.0 - wKnee) * 0.08
        if depth < depthLine { issues.append(.insufficientDepth) }
        if backAngle > leanLine { issues.append(.forwardLean) }
        if kneeAlignment < kneeValgusLine {
            issues.append(.kneeValgus)
        } else if kneeAlignment > kneeVarusLine {
            issues.append(.kneeVarus)
        }
        return Array(issues.prefix(CoachingContract.maxIssuesInPayload))
    }
    
    private func generateFormSummary3D(depth: Float, backAngle: Float, overallScore: Float) -> String {
        let pct = Int(overallScore * 100)
        if overallScore > 0.85 { return "Excellent form (3D)! Score: \(pct)%" }
        if overallScore > 0.7  { return "Good form (3D). Score: \(pct)%" }
        if overallScore > 0.5  { return "Form needs work (3D). Score: \(pct)%" }
        return "Focus on form basics (3D). Score: \(pct)%"
    }
    
    // MARK: - 3D Close-Grip Bench Press Form Analysis
    
    private func analyzeCloseGripBenchPressForm3D(_ skeleton: Skeleton3D) -> FormAnalysis {
        let gripWidthScore = calculateCloseGripWidthScore3D(skeleton)
        let elbowPositionScore = calculateElbowPositionScore3D(skeleton)
        let romScore = calculateBenchPressROMScore3D(skeleton)
        let eccentricScore = calculateBenchPressEccentricScore()
        let concentricScore = calculateBenchPressConcentricScore()
        
        let overallScore = (gripWidthScore * 0.20) +
                           (elbowPositionScore * 0.20) +
                           (romScore * 0.30) +
                           (eccentricScore * 0.15) +
                           (concentricScore * 0.15)
        
        var issues: [IssueCode] = []
        if gripWidthScore < CoachingContract.Threshold.gripTooWide { issues.append(.gripTooWide) }
        if elbowPositionScore < CoachingContract.Threshold.elbowsFlaring { issues.append(.elbowsFlaring) }
        if romScore < CoachingContract.Threshold.incompleteRom { issues.append(.incompleteRom) }
        if eccentricScore < CoachingContract.Threshold.eccentricTooFast { issues.append(.eccentricTooFast) }
        if concentricScore < CoachingContract.Threshold.concentricTooSlow { issues.append(.concentricTooSlow) }
        
        let summary = generateCloseGripBenchPressSummary(
            gripScore: gripWidthScore,
            elbowScore: elbowPositionScore,
            romScore: romScore,
            overallScore: overallScore
        )
        
        let depth = calculateBenchPressDepth3D(skeleton)
        
        return FormAnalysis(
            depth: depth,
            backAngle: 0.0,
            kneeAlignment: 0.0,
            overallScore: overallScore,
            issues: issues,
            summary: summary,
            repCount: repCount,
            avgEccentricMs: tempoRepSamples > 0 ? Float(sumEccentricMs / Double(tempoRepSamples)) : nil,
            avgPauseMs: tempoRepSamples > 0 ? Float(sumPauseMs / Double(tempoRepSamples)) : nil,
            avgConcentricMs: tempoRepSamples > 0 ? Float(sumConcentricMs / Double(tempoRepSamples)) : nil,
            avgBottomDepth: nil,
            deepRepRatio: nil
        )
    }
    
    /// 3D grip width: uses actual 3D distance between wrists vs shoulders (camera-invariant).
    private func calculateCloseGripWidthScore3D(_ skeleton: Skeleton3D) -> Float {
        guard let lw = skeleton.position("leftWrist"),
              let rw = skeleton.position("rightWrist"),
              let ls = skeleton.position("leftShoulder"),
              let rs = skeleton.position("rightShoulder") else { return 0.5 }
        
        let gripWidth = length(lw - rw)
        let shoulderWidth = length(ls - rs)
        guard shoulderWidth > .ulpOfOne else { return 0.5 }
        
        let ratio = gripWidth / shoulderWidth
        if ratio >= 0.7 && ratio <= 1.2 { return 1.0 }
        if ratio < 0.7 { return max(0.5, ratio / 0.7) }
        return max(0.5, 1.0 - (ratio - 1.2))
    }
    
    /// 3D elbow flare: lateral elbow offset vs shoulder width (camera-invariant).
    private func calculateElbowPositionScore3D(_ skeleton: Skeleton3D) -> Float {
        guard let le = skeleton.position("leftElbow"),
              let re = skeleton.position("rightElbow"),
              let ls = skeleton.position("leftShoulder"),
              let rs = skeleton.position("rightShoulder"),
              let lh = skeleton.position("leftHip"),
              let rh = skeleton.position("rightHip") else { return 0.5 }
        
        let center = (ls + rs + lh + rh) / 4.0
        let shoulderWidth = length(ls - rs)
        guard shoulderWidth > .ulpOfOne else { return 0.5 }
        
        let avgOffset = (abs(le.x - center.x) + abs(re.x - center.x)) / 2.0
        let flare = avgOffset / shoulderWidth
        
        if flare <= 0.6 { return 1.0 }
        if flare <= 0.8 { return max(0.7, 1.0 - (flare - 0.6) * 0.75) }
        return max(0.5, 0.85 - (flare - 0.8) * 0.7)
    }
    
    /// 3D ROM: elbow extension angle (camera-invariant).
    private func calculateBenchPressROMScore3D(_ skeleton: Skeleton3D) -> Float {
        guard let lw = skeleton.position("leftWrist"),
              let rw = skeleton.position("rightWrist"),
              let le = skeleton.position("leftElbow"),
              let re = skeleton.position("rightElbow"),
              let ls = skeleton.position("leftShoulder"),
              let rs = skeleton.position("rightShoulder") else { return 0.5 }
        
        let leftAngle = angleDegrees(a: ls, b: le, c: lw)
        let rightAngle = angleDegrees(a: rs, b: re, c: rw)
        let avg = (leftAngle + rightAngle) / 2.0
        
        if avg > 150 { return 1.0 }
        if avg > 120 { return 0.8 }
        return max(0.6, avg / 150.0)
    }
    
    /// 3D bench press depth: elbow-angle based, camera-invariant.
    /// Lockout (~170°) → 0.0, chest touch (~80°) → 1.0.
    private func calculateBenchPressDepth3D(_ skeleton: Skeleton3D) -> Float {
        guard let lw = skeleton.position("leftWrist"),
              let rw = skeleton.position("rightWrist"),
              let le = skeleton.position("leftElbow"),
              let re = skeleton.position("rightElbow"),
              let ls = skeleton.position("leftShoulder"),
              let rs = skeleton.position("rightShoulder") else { return 0.5 }
        
        let leftAngle = angleDegrees(a: ls, b: le, c: lw)
        let rightAngle = angleDegrees(a: rs, b: re, c: rw)
        let avg = (leftAngle + rightAngle) / 2.0
        return max(0, min(1, (170 - avg) / 90))
    }
    
    private func calculateDepth(_ points: [String: CGPoint]) -> Float {
        // Simplified depth calculation based on hip position
        guard let leftHip = points["leftHip"], let rightHip = points["rightHip"] else {
            return 0.5
        }
        
        // Calculate average hip position as depth indicator
        let hipY = (leftHip.y + rightHip.y) / 2.0
        return Float(hipY)
    }
    
    // MARK: - Bodyweight-Specific Calculations
    
    private func calculateBodyweightDepth(_ points: [String: CGPoint]) -> Float {
        // Use nose position for depth calculation - always visible and reliable
        guard let nose = points["nose"] else {
            return 0.5
        }
        
        // Normalized image coords (0–1): Y=0 is top, Y=1 is bottom (same as MediaPipe overlay)
        // When squatting: nose Y increases (moves down); when standing: nose Y decreases (moves up)
        
        // Simple depth calculation: higher Y = deeper squat
        // Normalize to 0-1 range where 0 = standing, 1 = deep squat
        let depth = max(0, min(1, nose.y))
        
        return Float(depth)
    }
    
    private func calculateBodyweightBackAngle(_ points: [String: CGPoint]) -> Float {
        // Enhanced back angle calculation for bodyweight squats
        // More sensitive to natural posture without barbell interference
        
        guard let leftShoulder = points["leftShoulder"],
              let rightShoulder = points["rightShoulder"],
              let leftHip = points["leftHip"],
              let rightHip = points["rightHip"] else {
            return 90.0
        }
        
        // Calculate shoulder and hip centers
        let shoulderCenter = CGPoint(
            x: (leftShoulder.x + rightShoulder.x) / 2.0,
            y: (leftShoulder.y + rightShoulder.y) / 2.0
        )
        
        let hipCenter = CGPoint(
            x: (leftHip.x + rightHip.x) / 2.0,
            y: (leftHip.y + rightHip.y) / 2.0
        )
        
        // Calculate angle between vertical and back line
        let dx = shoulderCenter.x - hipCenter.x
        let dy = shoulderCenter.y - hipCenter.y
        let angle = atan2(dx, dy) * 180.0 / .pi
        
        // Enhanced angle calculation for bodyweight squats
        // More forgiving for natural movement patterns
        let normalizedAngle = abs(angle)
        return Float(normalizedAngle)
    }
    
    private func calculateBodyweightKneeAlignment(_ points: [String: CGPoint]) -> Float {
        // Enhanced knee alignment calculation for bodyweight squats
        // More sensitive to natural knee tracking
        
        guard let leftKnee = points["leftKnee"], let rightKnee = points["rightKnee"],
              let leftAnkle = points["leftAnkle"], let rightAnkle = points["rightAnkle"] else {
            return 0.0
        }
        
        // Calculate knee tracking relative to ankles
        let leftKneeTracking = leftKnee.x - leftAnkle.x
        let rightKneeTracking = rightKnee.x - rightAnkle.x
        
        // Enhanced alignment calculation for bodyweight squats
        // More forgiving for natural movement patterns
        let averageTracking = (leftKneeTracking + rightKneeTracking) / 2.0
        let normalizedAlignment = max(-1.0, min(1.0, averageTracking / 0.1))
        
        return Float(normalizedAlignment)
    }
    
    private func calculateBodyweightOverallScore(depth: Float, backAngle: Float, kneeAlignment: Float) -> Float {
        // Enhanced scoring algorithm for bodyweight squats
        // Weighted toward mobility and control rather than load
        
        // Depth score - more forgiving for bodyweight
        let depthScore = min(depth * 1.5, 1.0) // Enhanced depth sensitivity
        
        // Angle score - optimized for bodyweight movement patterns
        let angleScore = 1.0 - abs(backAngle - 85.0) / 85.0 // Prefer 85 degrees for bodyweight
        
        // Knee alignment score - enhanced for bodyweight
        let alignmentScore = 1.0 - abs(kneeAlignment) / 2.0
        
        // Weighted scoring for bodyweight squats
        // Emphasizes natural movement patterns
        let overallScore = (depthScore * 0.4 + angleScore * 0.4 + alignmentScore * 0.2)
        
        return min(overallScore, 1.0)
    }

    // MARK: - Rule-based issue detection for cues
    private func detectBodyweightIssues(depth: Float, backAngle: Float, kneeAlignment: Float) -> [IssueCode] {
        var issues: [IssueCode] = []
        if depth < 0.45 { issues.append(.insufficientDepth) }
        if backAngle > CoachingContract.Threshold.forwardLean { issues.append(.forwardLean) }
        if kneeAlignment < CoachingContract.Threshold.kneeValgus {
            issues.append(.kneeValgus)
        } else if kneeAlignment > CoachingContract.Threshold.kneeVarus {
            issues.append(.kneeVarus)
        }
        return Array(issues.prefix(CoachingContract.maxIssuesInPayload))
    }
    
    private func generateBodyweightFormSummary(depth: Float, backAngle: Float, overallScore: Float) -> String {
        let scorePercentage = Int(overallScore * 100)
        
        if overallScore > 0.85 {
            return "Excellent bodyweight form! Score: \(scorePercentage)%"
        } else if overallScore > 0.7 {
            return "Good bodyweight form. Score: \(scorePercentage)%"
        } else if overallScore > 0.5 {
            return "Bodyweight form needs work. Score: \(scorePercentage)%"
        } else {
            return "Focus on bodyweight form basics. Score: \(scorePercentage)%"
        }
    }
    
    private func calculateBackAngle(_ points: [String: CGPoint]) -> Float {
        // Simplified back angle calculation
        guard let leftShoulder = points["leftShoulder"],
              let rightShoulder = points["rightShoulder"],
              let leftHip = points["leftHip"],
              let rightHip = points["rightHip"] else {
            return 90.0
        }
        
        // Calculate shoulder and hip centers
        let shoulderCenter = CGPoint(
            x: (leftShoulder.x + rightShoulder.x) / 2.0,
            y: (leftShoulder.y + rightShoulder.y) / 2.0
        )
        
        let hipCenter = CGPoint(
            x: (leftHip.x + rightHip.x) / 2.0,
            y: (leftHip.y + rightHip.y) / 2.0
        )
        
        // Calculate angle between vertical and back line
        let dx = shoulderCenter.x - hipCenter.x
        let dy = shoulderCenter.y - hipCenter.y
        let angle = atan2(dx, dy) * 180.0 / .pi
        
        return Float(abs(angle))
    }
    
    private func calculateOverallScore(depth: Float, backAngle: Float) -> Float {
        // Simplified scoring algorithm
        let depthScore = min(depth * 2.0, 1.0) // Normalize depth
        let angleScore = 1.0 - abs(backAngle - 90.0) / 90.0 // Prefer 90 degrees
        
        return (depthScore + angleScore) / 2.0
    }
    
    private func generateFormSummary(depth: Float, backAngle: Float, overallScore: Float) -> String {
        let scorePercentage = Int(overallScore * 100)
        
        if overallScore > 0.8 {
            return "Excellent form! Score: \(scorePercentage)%"
        } else if overallScore > 0.6 {
            return "Good form. Score: \(scorePercentage)%"
        } else {
            return "Form needs improvement. Score: \(scorePercentage)%"
        }
    }
    
    // MARK: - Automatic Set Detection Methods
    
    func resetRepCount() {
        DispatchQueue.main.async {
            self.repCount = 0
            self.lastRepFormAnalysis = nil
        }
        consecutiveGoodReps = 0
        lastRepTime = nil
        setStartTime = nil
        lastRepValidationTime = nil
        lastSpokenRep = 0
        resetSquatRepPhaseState()
        bodyweightRepHistory.removeAll()
        bodyweightRepPhase = .idle
        bodyweightCurrentRepPeakDepth = 0
        lastCountedRepHipKneeDepthQualityMet = false
        consecutiveFramesAtBottomBenchPress = 0
        consecutiveFramesAtTopBenchPress = 0
        framesSinceGoodPose = 0
        inactivityDetector.resetTimer()
        // Reset tempo tracking
        repStartTime = nil
        bottomTime = nil
        lastDepth = 0
        sumEccentricMs = 0
        sumPauseMs = 0
        sumConcentricMs = 0
        tempoRepSamples = 0
        // Reset ROM tracking
        sumBottomDepth = 0
        bottomDepthSamples = 0
        deepFrameCount = 0
        totalDepthSamples = 0
        currentRepBottomDepthMax = 0
        // Reset close-grip bench press rep detection state
        reachedBottomThisCycleBenchPress = false
        benchPressEccentricStartTime = nil
        benchPressBottomTime = nil
        benchPressBottomWristY = nil
        // Reset pose smoothing state
        currentAnalysisSource = .pose3D
        jointSmoother.reset()
        overlayLandmarkSmoother.reset()
        
        if trackedExerciseType == .closeGripBenchPress {
            initializeBenchPressRepTracking()
        }
        viewpointSmoother.reset(keepBucket: .chest_side)
        activeBodyweightRepProfile = SquatRepProfileTable.profile(for: .chest_side)
        squatExtensionFrameStateInternal = .neither
        resetBodyweightSquatRepCycleState()
        DispatchQueue.main.async {
            self.currentCameraHeightCategory = .unknown
            self.currentCameraViewCategory = .unknown
            self.currentSquatViewpointBucket = .chest_side
            self.currentSquatProfileName = SquatViewpointBucket.chest_side.rawValue
            self.currentSquatExtensionFrameState = .neither
        }
    }
    
    func resetRepCountingState() {
        DispatchQueue.main.async {
            self.repCount = 0
            self.workoutState = .waiting
            self.lastRepFormAnalysis = nil
        }
        consecutiveGoodReps = 0
        lastRepTime = nil
        setStartTime = nil
        lastRepValidationTime = nil
        lastSpokenRep = 0
        resetSquatRepPhaseState()
        bodyweightRepHistory.removeAll()
        bodyweightRepPhase = .idle
        bodyweightCurrentRepPeakDepth = 0
        lastCountedRepHipKneeDepthQualityMet = false
        consecutiveFramesAtBottomBenchPress = 0
        consecutiveFramesAtTopBenchPress = 0
        framesSinceGoodPose = 0
        inactivityDetector.resetTimer()
        repStartTime = nil
        bottomTime = nil
        lastDepth = 0
        sumEccentricMs = 0
        sumPauseMs = 0
        sumConcentricMs = 0
        tempoRepSamples = 0
        sumBottomDepth = 0
        bottomDepthSamples = 0
        deepFrameCount = 0
        totalDepthSamples = 0
        currentRepBottomDepthMax = 0
        standingHipHeight = nil
        standingLegLength = nil
        reachedBottomThisCycleBenchPress = false
        benchPressEccentricStartTime = nil
        benchPressBottomTime = nil
        benchPressBottomWristY = nil
        currentAnalysisSource = .pose3D

        if trackedExerciseType == .closeGripBenchPress {
            initializeBenchPressRepTracking()
        }
        viewpointSmoother.reset(keepBucket: .chest_side)
        activeBodyweightRepProfile = SquatRepProfileTable.profile(for: .chest_side)
        squatExtensionFrameStateInternal = .neither
        resetBodyweightSquatRepCycleState()
        DispatchQueue.main.async {
            self.currentCameraHeightCategory = .unknown
            self.currentCameraViewCategory = .unknown
            self.currentSquatViewpointBucket = .chest_side
            self.currentSquatProfileName = SquatViewpointBucket.chest_side.rawValue
            self.currentSquatExtensionFrameState = .neither
        }
    }
    
    /// Initializes bench press rep tracking state for proper first-rep detection.
    /// Sets up eccentric start time so the first rep's eccentric phase is tracked.
    /// Called when starting a close-grip bench press exercise.
    func initializeBenchPressRepTracking() {
        // Initialize eccentric start time immediately so first rep is tracked
        // This ensures we can measure eccentric tempo from the very first rep
        benchPressEccentricStartTime = CACurrentMediaTime()
        reachedBottomThisCycleBenchPress = false
        benchPressBottomTime = nil
        benchPressBottomWristY = nil
    }
    
    func getCurrentRepCount() -> Int {
        return repCount
    }
    
    func checkForSetEnd() {
        guard workoutState == .exercising else { return }
        
        if inactivityDetector.checkInactivity() {
            handleSetEnd()
        }
    }
    
    func startNewSet() {
        DispatchQueue.main.async {
            self.currentSet += 1
            self.workoutState = .waiting
            self.resetRepCount()
            
            // Provide audio feedback
            SpeechManager.shared.speak("Starting set \(self.currentSet)", priority: .normal)
        }
    }
    
    // MARK: - Bodyweight viewpoint + extension (runs on analysis queue)

    private func updateBodyweightViewpointAndExtension(
        overlay: [String: CGPoint],
        skeleton: Skeleton3D,
        confidence: [String: Float]
    ) {
        let (hCat, hScores) = SquatViewpointClassifier.classifyCameraHeight(overlay: overlay)
        let (vCat, vScores) = SquatViewpointClassifier.classifyCameraView(overlay: overlay, confidence: confidence)
        let rawBucket = SquatViewpointBucket.bucket(height: hCat, view: vCat)
        _ = viewpointSmoother.push(candidate: rawBucket)
        activeBodyweightRepProfile = SquatRepProfileTable.profile(for: viewpointSmoother.activeBucket)

        let depth = calculateHipDepth3D(skeleton)
        let newExt = SquatExtensionFrameClassifier.nextState(
            previous: squatExtensionFrameStateInternal,
            hipDepth: depth,
            profile: activeBodyweightRepProfile
        )
        if newExt != squatExtensionFrameStateInternal {
            squatExtensionFrameStateInternal = newExt
            DispatchQueue.main.async {
                self.currentSquatExtensionFrameState = newExt
            }
        }

        DispatchQueue.main.async {
            self.currentCameraHeightCategory = hCat
            self.currentCameraViewCategory = vCat
            self.currentSquatViewpointBucket = self.viewpointSmoother.activeBucket
            self.currentSquatProfileName = self.viewpointSmoother.activeBucket.rawValue
        }
    }

    private func bodyweightOverlayLegSpanY(_ overlay: [String: CGPoint]) -> Float? {
        guard let lh = overlay["leftHip"], let rh = overlay["rightHip"],
              let la = overlay["leftAnkle"], let ra = overlay["rightAnkle"] else { return nil }
        let hipY = Float((lh.y + rh.y) / 2)
        let ankleY = Float((la.y + ra.y) / 2)
        let span = abs(hipY - ankleY)
        return span > 0.02 ? span : nil
    }

    private func rejectBodyweightRep(reason _: SquatRepRejectReason, note _: String = "") {
        resetBodyweightSquatRepCycleState()
        abortInProgressBodyweightRepAccumulation()
    }

    private func resetBodyweightSquatRepCycleState() {
        bwShoulderPhase = .idleAtTop
        bwTopRefShoulderY = nil
        bwCycleExtremeShoulderY = nil
        bwTopLocked = false
        bwShoulderConsecutive = 0
        bwEarlyTopReturnFrames = 0
        bwRepCycleStartTime = nil
        squatRepCycleHipKneeParallelMet = false
        bwSmoothedShoulderY = nil
        bwPrevSmoothedShoulderY = nil
        bwShoulderVelocity = 0
    }

    private func updateBodyweightHipKneeParallelTag(skeleton: Skeleton3D) {
        guard let frame = squatRepHipKneeMetrics(skeleton) else { return }
        let tol = activeBodyweightRepProfile.hipKneeDepthQualityToleranceNormalized
        if frame.normalizedHipKneeDelta <= tol {
            squatRepCycleHipKneeParallelMet = true
        }
    }

    /// Mid-shoulder vertical motion in overlay Y (normalized by leg span). No secondary hip/knee gating.
    /// Uses EMA-smoothed shoulder Y and velocity confirmation for robust angle-independent rep detection.
    private func validateBodyweightSquatRep(overlay: [String: CGPoint], skeleton: Skeleton3D, now: Date) -> Bool {
        let profile = activeBodyweightRepProfile
        guard let ls = overlay["leftShoulder"], let rs = overlay["rightShoulder"] else { return false }
        guard let legSpan = bodyweightOverlayLegSpanY(overlay) else { return false }

        let rawShoulderY = Float((ls.y + rs.y) / 2)

        // EMA smoothing: reduces MediaPipe landmark jitter across all camera angles.
        let alpha = profile.shoulderEMAAlpha
        let smoothed: Float
        if let prev = bwSmoothedShoulderY {
            smoothed = alpha * rawShoulderY + (1 - alpha) * prev
        } else {
            smoothed = rawShoulderY
        }
        bwPrevSmoothedShoulderY = bwSmoothedShoulderY
        bwSmoothedShoulderY = smoothed

        // Velocity: positive = moving down in overlay coords, negative = moving up.
        let rawVelocity: Float
        if let prev = bwPrevSmoothedShoulderY {
            rawVelocity = smoothed - prev
        } else {
            rawVelocity = 0
        }
        // Smooth velocity with same alpha to damp noise.
        bwShoulderVelocity = alpha * rawVelocity + (1 - alpha) * bwShoulderVelocity

        let shoulderY = smoothed

        switch bwShoulderPhase {
        case .idleAtTop:
            if !bwTopLocked {
                if bwTopRefShoulderY == nil { bwTopRefShoulderY = shoulderY }
                let top = bwTopRefShoulderY!
                if abs(shoulderY - top) <= profile.repTopLockToleranceNormalized * legSpan {
                    bwShoulderConsecutive += 1
                    if bwShoulderConsecutive >= profile.framesForTopLock {
                        bwTopLocked = true
                        bwTopRefShoulderY = shoulderY
                        bwShoulderConsecutive = 0
                    }
                } else {
                    bwShoulderConsecutive = 0
                    bwTopRefShoulderY = shoulderY
                }
                return false
            }

            let top = bwTopRefShoulderY!
            let excursion = shoulderY - top
            let velocityConfirmed = bwShoulderVelocity >= profile.velocityDescentConfirm
            if excursion >= profile.repDescentExcursionNormalized * legSpan, velocityConfirmed {
                bwShoulderPhase = .descending
                bwRepCycleStartTime = now
                bwShoulderConsecutive = 0
                bwEarlyTopReturnFrames = 0
                bwCycleExtremeShoulderY = shoulderY
                updateBodyweightHipKneeParallelTag(skeleton: skeleton)
            }
            return false

        case .descending:
            let top = bwTopRefShoulderY ?? shoulderY
            updateBodyweightHipKneeParallelTag(skeleton: skeleton)
            if let extreme = bwCycleExtremeShoulderY {
                bwCycleExtremeShoulderY = max(extreme, shoulderY)
            } else {
                bwCycleExtremeShoulderY = shoulderY
            }

            let exc = shoulderY - top
            if exc >= profile.repBottomExcursionNormalized * legSpan {
                bwShoulderConsecutive += 1
                if bwShoulderConsecutive >= profile.framesForBottomConfirm {
                    bwShoulderPhase = .bottomReached
                    bwShoulderConsecutive = 0
                    bwEarlyTopReturnFrames = 0
                }
            } else {
                bwShoulderConsecutive = 0
            }

            // Shallow bounce rejection: returned near top before reaching bottom depth.
            if exc < profile.repDescentExcursionNormalized * legSpan * 0.35 {
                bwEarlyTopReturnFrames += 1
                if bwEarlyTopReturnFrames >= profile.framesForTopReturnConfirm {
                    rejectBodyweightRep(reason: .shallowBounceAborted, note: "returnedToTopBeforeBottom")
                    return false
                }
            } else {
                bwEarlyTopReturnFrames = 0
            }
            return false

        case .bottomReached:
            updateBodyweightHipKneeParallelTag(skeleton: skeleton)
            // Track the deepest point even after bottom is confirmed.
            if let extreme = bwCycleExtremeShoulderY {
                bwCycleExtremeShoulderY = max(extreme, shoulderY)
            }
            // Transition to ascending: require upward position recovery AND upward velocity.
            if let extreme = bwCycleExtremeShoulderY,
               shoulderY < extreme - profile.repAscentRecoveryNormalized * legSpan,
               bwShoulderVelocity <= profile.velocityAscentConfirm {
                bwShoulderPhase = .ascending
                bwShoulderConsecutive = 0
            }
            return false

        case .ascending:
            updateBodyweightHipKneeParallelTag(skeleton: skeleton)

            let top = bwTopRefShoulderY ?? shoulderY
            if shoulderY - top <= profile.repReturnToTopToleranceNormalized * legSpan {
                bwShoulderConsecutive += 1
                if bwShoulderConsecutive >= profile.framesForTopReturnConfirm {
                    let dur = now.timeIntervalSince(bwRepCycleStartTime ?? now)
                    if let last = lastRepValidationTime, now.timeIntervalSince(last) < profile.minRepInterval {
                        rejectBodyweightRep(reason: .minRepInterval, note: "dt=\(now.timeIntervalSince(last))")
                        return false
                    }
                    if dur < profile.minRepCycleDuration {
                        rejectBodyweightRep(reason: .minCycleDuration, note: "dur=\(dur)")
                        return false
                    }
                    if dur > profile.maxRepCycleDuration {
                        rejectBodyweightRep(reason: .maxCycleDuration, note: "dur=\(dur)")
                        return false
                    }
                    lastCountedRepHipKneeDepthQualityMet = squatRepCycleHipKneeParallelMet
                    lastRepValidationTime = now
                    // Preserve EMA continuity across reps for smooth tracking.
                    let savedSmoothed = bwSmoothedShoulderY
                    let savedPrev = bwPrevSmoothedShoulderY
                    let savedVel = bwShoulderVelocity
                    // Adaptive top reference: update to current standing position for next rep.
                    let returnedTopY = shoulderY
                    resetBodyweightSquatRepCycleState()
                    bwTopRefShoulderY = returnedTopY
                    bwTopLocked = true
                    bwSmoothedShoulderY = savedSmoothed
                    bwPrevSmoothedShoulderY = savedPrev
                    bwShoulderVelocity = savedVel
                    return true
                }
            } else {
                bwShoulderConsecutive = 0
            }

            // If user sinks back down during ascent, re-enter bottomReached.
            // Use velocity to confirm genuine re-descent vs noise.
            let reDescentExc = shoulderY - top
            if reDescentExc > profile.repBottomExcursionNormalized * legSpan * 0.80,
               bwShoulderVelocity >= profile.velocityDescentConfirm {
                bwShoulderPhase = .bottomReached
                bwShoulderConsecutive = 0
            }
            return false
        }
    }

    // MARK: - Squat rep detection (hip depth hysteresis)

    /// Hip-vs-knee vertical relationship for secondary quality tagging only (does not gate counting).
    private func squatRepHipKneeMetrics(_ skeleton: Skeleton3D) -> SquatRepFrame? {
        guard let lh = skeleton.position("leftHip"),
              let rh = skeleton.position("rightHip"),
              let lk = skeleton.position("leftKnee"),
              let rk = skeleton.position("rightKnee"),
              let la = skeleton.position("leftAnkle"),
              let ra = skeleton.position("rightAnkle") else { return nil }

        let avgHipY = (lh.y + rh.y) / 2
        let avgKneeY = (lk.y + rk.y) / 2
        let hipCenter = (lh + rh) / 2
        let ankleCenter = (la + ra) / 2
        let legLen = standingLegLength ?? length(hipCenter - ankleCenter)
        guard legLen > 0.01 else { return nil }

        let delta = (avgHipY - avgKneeY) / legLen
        return SquatRepFrame(avgHipY: avgHipY, avgKneeY: avgKneeY, legLength: legLen, normalizedHipKneeDelta: delta)
    }

    private func updateSquatRepHipKneeParallelTag(skeleton: Skeleton3D) {
        guard let frame = squatRepHipKneeMetrics(skeleton) else { return }
        let tol: Float = hipKneeBottomToleranceNormalizedBarbell
        if frame.normalizedHipKneeDelta <= tol {
            squatRepCycleHipKneeParallelMet = true
        }
    }

    /// Clears barbell/benchPress hip-depth rep machine only (after a counted rep). Bodyweight uses shoulder-vertical cycle state instead.
    private func resetSquatRepDepthMachineOnly() {
        guard trackedExerciseType != .bodyweight else { return }
        squatRepPhase = .idleAtTop
        squatRepTopHoldFrames = 0
        squatRepBottomHoldFrames = 0
        squatRepMaxDepthThisCycle = 0
        squatRepCycleHipKneeParallelMet = false
    }

    /// Abandon in-flight rep: bodyweight resets shoulder rep cycle + accumulation; barbell/bench use hip-depth machine.
    private func abandonSquatRepCycle() {
        if trackedExerciseType == .bodyweight {
            abortInProgressBodyweightRepAccumulation()
            resetBodyweightSquatRepCycleState()
        } else {
            resetSquatRepDepthMachineOnly()
        }
    }

    /// Full reset for new set / rep counting reset (includes abandoning partial bodyweight rep).
    private func resetSquatRepPhaseState() {
        abandonSquatRepCycle()
    }

    private func validateRep(
        skeleton: Skeleton3D?,
        overlay: [String: CGPoint]?,
        formAnalysis: FormAnalysis,
        now: Date
    ) -> Bool {
        switch trackedExerciseType {
        case .closeGripBenchPress:
            if let last = lastRepValidationTime,
               now.timeIntervalSince(last) < minTimeBetweenReps {
                return false
            }
            let requiredScore = poseConfidenceThreshold * 0.5
            if formAnalysis.overallScore < requiredScore {
                return false
            }
            return validateCloseGripBenchPressRep(formAnalysis: formAnalysis, now: now)
        case .bodyweight:
            guard let sk = skeleton, let ov = overlay else { return false }
            return validateBodyweightSquatRep(overlay: ov, skeleton: sk, now: now)
        case .barbell, .benchPress:
            return validateSquatRepHipDepthLegacy(skeleton: skeleton, now: now)
        }
    }

    /// Hip-depth hysteresis (barbell / benchPress squat only): idleAtTop → descending → bottomReached → ascending → count at top.
    private func validateSquatRepHipDepthLegacy(skeleton: Skeleton3D?, now: Date) -> Bool {
        guard let skeleton = skeleton else { return false }
        let depth = calculateHipDepth3D(skeleton)

        switch squatRepPhase {
        case .idleAtTop:
            if depth >= repStartThreshold {
                squatRepPhase = .descending
                squatRepMaxDepthThisCycle = depth
                squatRepCycleHipKneeParallelMet = false
                squatRepTopHoldFrames = 0
                squatRepBottomHoldFrames = 0
                updateSquatRepHipKneeParallelTag(skeleton: skeleton)
                return false
            }
            if depth <= repTopThreshold {
                squatRepTopHoldFrames = min(squatRepTopHoldFrames + 1, framesForTopConfirmation)
            } else {
                squatRepTopHoldFrames = 0
            }
            return false

        case .descending:
            squatRepMaxDepthThisCycle = max(squatRepMaxDepthThisCycle, depth)
            updateSquatRepHipKneeParallelTag(skeleton: skeleton)
            if depth >= repBottomThreshold {
                squatRepBottomHoldFrames += 1
                if squatRepBottomHoldFrames >= framesForBottomConfirmation {
                    squatRepPhase = .bottomReached
                    squatRepBottomHoldFrames = 0
                }
            } else {
                squatRepBottomHoldFrames = 0
            }
            if depth <= repTopThreshold {
                squatRepTopHoldFrames += 1
                if squatRepTopHoldFrames >= framesForTopConfirmation {
                    abandonSquatRepCycle()
                }
            } else {
                squatRepTopHoldFrames = 0
            }
            return false

        case .bottomReached:
            squatRepMaxDepthThisCycle = max(squatRepMaxDepthThisCycle, depth)
            updateSquatRepHipKneeParallelTag(skeleton: skeleton)
            if depth < repBottomThreshold {
                squatRepPhase = .ascending
                squatRepTopHoldFrames = 0
            }
            return false

        case .ascending:
            updateSquatRepHipKneeParallelTag(skeleton: skeleton)
            if depth >= repBottomThreshold {
                squatRepPhase = .bottomReached
                squatRepBottomHoldFrames = 0
                return false
            }
            if depth <= repTopThreshold {
                squatRepTopHoldFrames += 1
                if squatRepTopHoldFrames >= framesForTopConfirmation {
                    if let last = lastRepValidationTime,
                       now.timeIntervalSince(last) < minTimeBetweenReps {
                        return false
                    }
                    lastCountedRepHipKneeDepthQualityMet = squatRepCycleHipKneeParallelMet
                    lastRepValidationTime = now
                    resetSquatRepDepthMachineOnly()
                    return true
                }
            } else {
                squatRepTopHoldFrames = 0
            }
            return false
        }
    }

    
    /// Validates close-grip bench press rep using state machine pattern detection.
    ///
    /// Movement Pattern: Top (lockout) → Bottom (chest touch) → Top (lockout)
    ///
    /// Uses wrist Y position from form analysis depth field:
    /// - Higher Y = bar closer to chest (bottom position)
    /// - Lower Y = bar at lockout (top position)
    ///
    /// View-specific thresholds account for camera angle differences:
    /// - Rack view: Standard Y axis (Y increases as bar goes down)
    /// - Floor view: Inverted Y axis (Y decreases as bar goes down)
    /// - Tripod view: Standard Y axis with adjusted thresholds
    ///
    /// Also tracks tempo: measures eccentric (top→bottom) and concentric (bottom→top) phases.
    private func validateCloseGripBenchPressRep(formAnalysis: FormAnalysis, now: Date) -> Bool {
        let depthValue = formAnalysis.depth
        
        let bottomThreshold: Float
        let topThreshold: Float
        
        // 3D path: depth is elbow-angle based (0 = lockout, 1 = chest), camera-invariant
        bottomThreshold = 0.65
        topThreshold = 0.25
        
        let wristY = depthValue
        
        if benchPressEccentricStartTime == nil {
            if wristY <= topThreshold {
                benchPressEccentricStartTime = CACurrentMediaTime()
            }
        }
        
        let atBottom = wristY >= bottomThreshold
        let atTop = wristY <= topThreshold
        
        if atBottom {
            consecutiveFramesAtBottomBenchPress += 1
            consecutiveFramesAtTopBenchPress = 0
            if consecutiveFramesAtBottomBenchPress >= consistentFramesForRepTransition && !reachedBottomThisCycleBenchPress {
                reachedBottomThisCycleBenchPress = true
                benchPressBottomWristY = wristY
                if let eccentricStart = benchPressEccentricStartTime {
                    sumEccentricMs += (CACurrentMediaTime() - eccentricStart) * 1000
                }
                benchPressBottomTime = CACurrentMediaTime()
            }
            return false
        }
        
        if atTop && reachedBottomThisCycleBenchPress {
            consecutiveFramesAtTopBenchPress += 1
            if consecutiveFramesAtTopBenchPress >= consistentFramesForRepTransition {
                if let bt = benchPressBottomTime {
                    sumConcentricMs += (CACurrentMediaTime() - bt) * 1000
                    tempoRepSamples += 1
                }
                lastRepValidationTime = now
                reachedBottomThisCycleBenchPress = false
                benchPressBottomWristY = nil
                benchPressEccentricStartTime = CACurrentMediaTime()
                consecutiveFramesAtBottomBenchPress = 0
                consecutiveFramesAtTopBenchPress = 0
                return true
            }
            return false
        }
        
        consecutiveFramesAtBottomBenchPress = 0
        consecutiveFramesAtTopBenchPress = 0
        return false
    }
    
    /// Handles rep detection: increments rep count and stores form analysis for score calculation.
    /// Bodyweight rep commit (commitBodyweightRepIfNeeded) is done on the analysis queue before this is dispatched.
    private func handleRepDetected() {
        repCount += 1
        consecutiveGoodReps += 1
        lastRepTime = Date()
        inactivityDetector.updateLastRep()
        
        lastRepFormAnalysis = currentFormAnalysis

        if workoutState == .waiting && consecutiveGoodReps >= minRepsForSetStart {
            handleSetStart()
        }
    }

    /// Builds BodyweightRepMetrics from current-rep accumulators, validates, appends only if valid, resets state.
    private func commitBodyweightRepIfNeeded() {
        let depthAtBottom = bodyweightCurrentRepPeakDepth
        let backAngleMax = currentRepBackAngleMax ?? 0
        let kneeWorst = currentRepKneeAlignmentWorst ?? 0
        let hipKneeQ = lastCountedRepHipKneeDepthQualityMet
        let p = activeBodyweightRepProfile
        let goodDepth = p.repGoodDepthThreshold
        let minBottom = max(bodyweightMinDepthForViableBottom, p.repCountDepthThreshold * 0.82)

        let shallowDepth = depthAtBottom < goodDepth
        let excessiveForwardLean = backAngleMax > CoachingContract.Threshold.forwardLean
        let kneeValgus = kneeWorst < CoachingContract.Threshold.kneeValgus

        let valid = depthAtBottom >= minBottom
            && bodyweightRepFrameCount >= bodyweightMinFramesInRep
            && bodyweightKneeWindowSampleCount >= 1

        let metrics = BodyweightRepMetrics(
            depthAtBottom: depthAtBottom,
            backAngleMax: backAngleMax,
            kneeAlignmentWorstNearBottom: kneeWorst,
            shallowDepth: shallowDepth,
            excessiveForwardLean: excessiveForwardLean,
            kneeValgus: kneeValgus,
            hipKneeDepthQualityMet: hipKneeQ,
            valid: valid,
            timestamp: Date().timeIntervalSince1970
        )
        if valid {
            bodyweightRepHistory.append(metrics)
        }

        bodyweightRepPhase = .idle
        currentRepBackAngleMax = nil
        currentRepKneeAlignmentWorst = nil
        bodyweightRepFrameCount = 0
        bodyweightKneeWindowSampleCount = 0
        bodyweightCurrentRepPeakDepth = 0
        lastCountedRepHipKneeDepthQualityMet = false
    }

    /// Per-set reset shared by rep-driven set start and explicit Track set start.
    private func performPerSetAggregationReset() {
        setStartTime = Date()
        viewpointSmoother.reset(keepBucket: .chest_side)
        activeBodyweightRepProfile = SquatRepProfileTable.profile(for: .chest_side)
        squatExtensionFrameStateInternal = .neither
        resetBodyweightSquatRepCycleState()
        DispatchQueue.main.async {
            self.currentCameraHeightCategory = .unknown
            self.currentCameraViewCategory = .unknown
            self.currentSquatViewpointBucket = .chest_side
            self.currentSquatProfileName = SquatViewpointBucket.chest_side.rawValue
            self.currentSquatExtensionFrameState = .neither
        }
        resetSquatRepPhaseState()
        lastRepValidationTime = nil
        issueCounts.removeAll()
        positiveCounts.removeAll()
        repStartTime = nil
        bottomTime = nil
        lastDepth = 0
        sumEccentricMs = 0
        sumPauseMs = 0
        sumConcentricMs = 0
        tempoRepSamples = 0
        sumBottomDepth = 0
        bottomDepthSamples = 0
        deepFrameCount = 0
        totalDepthSamples = 0
        currentRepBottomDepthMax = 0
        lastCompletedRepDepthAtBottom = nil
        standingHipHeight = nil
        standingLegLength = nil
        bodyweightRepHistory.removeAll()
        bodyweightRepPhase = .idle
        currentRepBackAngleMax = nil
        currentRepKneeAlignmentWorst = nil
        bodyweightRepFrameCount = 0
        bodyweightKneeWindowSampleCount = 0
        bodyweightCurrentRepPeakDepth = 0
        lastCountedRepHipKneeDepthQualityMet = false
    }

    /// Call when the user explicitly starts a set (e.g. Track “Begin Set”). Forces `.exercising` and full per-set reset.
    func startManualSet() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { self.startManualSet() }
            return
        }
        workoutState = .exercising
        performPerSetAggregationReset()
    }

    private func handleSetStart() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { self.handleSetStart() }
            return
        }
        guard workoutState == .waiting else { return }
        workoutState = .exercising
        performPerSetAggregationReset()
    }
    
    private func handleSetEnd() {
        // Ensure we're on main thread for @Published property updates
        DispatchQueue.main.async {
            guard self.workoutState == .exercising else { return }
            
            self.workoutState = .resting
            // Reset rep count for next set (but keep total workout state)
            self.repCount = 0
            self.consecutiveGoodReps = 0
            self.resetSquatRepPhaseState()
            self.lastRepValidationTime = nil
        }
        
        restStartTime = Date()
        
        // State and rest timer only. Do not call API or SpeechManager here — the UI owns when to
        // request feedback and speak (e.g. TrackView speaks only when the user taps "End Set").
        DispatchQueue.main.async {
            DispatchQueue.main.asyncAfter(deadline: .now() + self.restPeriodDuration) {
                self.handleRestPeriodEnd()
            }
        }
    }
    
    private func handleRestPeriodEnd() {
        // Already on main thread (called from DispatchQueue.main.asyncAfter)
        guard workoutState == .resting else { return }
        
        workoutState = .waiting
    }
    
    func checkForNextSetStart() {
        guard workoutState == .waiting else { return }
        // Rep validation runs only in `handleMediaPipeResult`; do not call `validateRep` here (avoids double-advancing the squat state machine).
        if consecutiveGoodReps >= minRepsForSetStart {
            handleSetStart()
        }
    }

    // Public method to allow UI to force end a set and use aggregated feedback
    func forceEndCurrentSet() {
        handleSetEnd()
    }

    // MARK: - Aggregation helpers
    private func aggregateFeedback(from analysis: FormAnalysis) {
        for issue in analysis.issues {
            issueCounts[issue, default: 0] += 1
        }
        if analysis.depth >= CoachingContract.PositiveThreshold.goodDepth {
            positiveCounts[.goodDepth, default: 0] += 1
        }
        if abs(analysis.backAngle) <= CoachingContract.PositiveThreshold.chestTall {
            positiveCounts[.chestTall, default: 0] += 1
        }
        if abs(analysis.kneeAlignment) <= CoachingContract.PositiveThreshold.kneesTracking {
            positiveCounts[.kneesOverToes, default: 0] += 1
        }
    }
    
    // MARK: - Legacy Two-Point Feedback (Deprecated)
    @available(*, deprecated, message: "Use OpenAICoachingManager.analyzeAndGetNaturalFeedback instead")
    private func aggregatedTwoPointFeedback() -> (String, String) {
        let topPositiveKey = positiveCounts.max(by: { $0.value < $1.value })?.key
        let good = (topPositiveKey.flatMap { positiveCueByKey[$0] }) ?? {
            if let analysis = currentFormAnalysis {
                if analysis.depth >= CoachingContract.PositiveThreshold.goodDepth { return "Good depth" }
                if abs(analysis.backAngle) <= CoachingContract.PositiveThreshold.chestTall { return "Chest tall" }
            }
            return "Controlled tempo"
        }()
        
        let topIssue = issueCounts.max(by: { $0.value < $1.value })?.key
        let improve: String = {
            if let issue = topIssue, let cue = cueByIssue[issue] { return cue }
            if let analysis = currentFormAnalysis {
                if analysis.issues.contains(.kneeValgus) { return "Push your knees out" }
                if analysis.issues.contains(.kneeVarus) { return "Keep your knees over your toes" }
                if analysis.issues.contains(.forwardLean) { return "Lift your chest" }
                if analysis.depth < 0.45 { return "Squat a little deeper" }
            }
            return "Brace your core"
        }()
        
        return (good, improve)
    }
    
    private func updateTempoTracking(currentDepth: Float) {
        let now = CACurrentMediaTime()
        
        let bottomThresh = deepDepthThreshold3D
        let topThresh = shallowDepthThreshold3D
        
        totalDepthSamples += 1
        if currentDepth >= bottomThresh { deepFrameCount += 1 }
        if currentDepth > currentRepBottomDepthMax { currentRepBottomDepthMax = currentDepth }
        if repStartTime == nil, currentDepth <= topThresh {
            repStartTime = now
        }
        if lastDepth < bottomThresh && currentDepth >= bottomThresh {
            bottomTime = now
        }
        if let bTime = bottomTime, lastDepth >= bottomThresh && currentDepth < bottomThresh {
            let pauseMs = max(0, (now - bTime) * 1000.0)
            sumPauseMs += pauseMs
        }
        if let start = repStartTime, lastDepth > topThresh && currentDepth <= topThresh {
            if currentRepBottomDepthMax > 0 {
                sumBottomDepth += Double(currentRepBottomDepthMax)
                bottomDepthSamples += 1
            }
            lastCompletedRepDepthAtBottom = currentRepBottomDepthMax > 0 ? currentRepBottomDepthMax : nil
            let totalMs = (now - start) * 1000.0
            var eccMs = totalMs * 0.5
            var conMs = totalMs * 0.5
            if let bTime = bottomTime {
                let ecc = max(0, (bTime - start) * 1000.0)
                let con = max(0, totalMs - ecc)
                eccMs = ecc
                conMs = con
            }
            sumEccentricMs += eccMs
            sumConcentricMs += conMs
            tempoRepSamples += 1
            repStartTime = nil
            bottomTime = nil
            currentRepBottomDepthMax = 0
        }
        lastDepth = currentDepth
    }
}

// MARK: - MediaPipe Livestream Delegate

extension OnDevicePoseManager: PoseLandmarkerLiveStreamDelegate {
    func poseLandmarker(
        _ poseLandmarker: PoseLandmarker,
        didFinishDetection result: PoseLandmarkerResult?,
        timestampInMilliseconds: Int,
        error: Error?
    ) {
        handleMediaPipeResult(result, timestampMs: timestampInMilliseconds, error: error)
    }
}
