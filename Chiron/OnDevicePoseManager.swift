import Foundation
import AVFoundation
import CoreML
import Vision
import UIKit

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
    let issues: [String]
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

// MARK: - Workout State Management
enum WorkoutState {
    case waiting        // Waiting for user to start exercising
    case exercising     // Actively performing reps in a set
    case resting        // Rest period between sets
    case finished       // Workout completed
}

// MARK: - Squat Type

/// Exercise type identifier for pose detection and form analysis.
///
/// Note: Despite the name "SquatType", this enum is used for all exercise types
/// until exercise-specific pose detection models are implemented.
enum SquatType {
    case bodyweight           // Bodyweight squat exercises
    case barbell              // Barbell back squat exercises
    case benchPress           // Regular bench press (placeholder for future implementation)
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
    @Published var squatType: SquatType = .bodyweight
    
    /// Camera view type for close-grip bench press exercises.
    /// Used to adjust form analysis calculations based on camera angle:
    /// - `.rack`: Top-down view (high, angled down)
    /// - `.floor`: Bottom-up view (low, angled up)
    /// - `.tripod`: Side view (bar level, slight angle)
    /// Set by WorkoutActiveView when starting a close-grip bench press exercise.
    var benchPressViewType: BenchPressViewType = .tripod
    
    // MARK: - Automatic Set Detection Properties
    private var inactivityDetector = InactivityDetector()
    private var consecutiveGoodReps = 0
    private var lastRepTime: Date?
    private var setStartTime: Date?
    private var restStartTime: Date?
    private let restPeriodDuration: TimeInterval = 60.0 // 60 seconds rest
    private let minRepsForSetStart = 2
    private let minTimeBetweenReps: TimeInterval = 0.8  // Minimum 0.8 seconds between reps (MORE SENSITIVE)
    
    // MARK: - Rep Validation Properties
    private var lastRepValidationTime: Date?
    private var repValidationThreshold: TimeInterval = 0.5
    private var movementThreshold: Float = 0.05  // Very sensitive to movement
    private var poseConfidenceThreshold: Float = 0.15  // Even lower confidence threshold for better detection (MORE SENSITIVE)
    // More sensitive depth thresholds for a squat cycle using nose position (normalized 0-1 depth)
    // Relaxed to improve rep detection across different camera crops/heights
    private let deepDepthThreshold: Float = 0.58  // deep when nose >= 0.58
    private let shallowDepthThreshold: Float = 0.48  // top when nose <= 0.48
    // State flag to ensure we saw a deep phase before counting on return to shallow
    private var reachedDeepThisCycle: Bool = false
    
    // MARK: - Close-Grip Bench Press Rep Detection State
    
    /// Tracks whether the bar has reached chest (bottom position) in the current rep cycle.
    /// Used for rep detection: top (lockout) → bottom (chest touch) → top (lockout).
    private var reachedBottomThisCycleBenchPress: Bool = false
    
    /// Timestamps for tracking eccentric (lowering) and concentric (pressing) phases.
    /// Used to measure tempo: eccentric should be ≥1s, concentric should be ≤2s.
    private var benchPressEccentricStartTime: CFTimeInterval?
    private var benchPressBottomTime: CFTimeInterval?
    
    // MARK: - Audio Feedback Properties
    private var lastSpokenRep: Int = 0
    private var repFeedbackInterval = 5 // Speak every 5 reps
    
    private var poseRequest: VNDetectHumanBodyPoseRequest?
    private var analysisQueue = DispatchQueue(label: "pose.analysis", qos: .userInteractive)
    
    // Cue speaking state
    private var lastCueSpokenAt: Date?
    private var lastCueText: String = ""
    private let cueCooldownSeconds: TimeInterval = 6.0
    private let cueByIssue: [String: String] = [
        "Knees Caving In": "Push your knees out",
        "Knees Bowing Out": "Keep your knees over your toes",
        "Forward Lean": "Lift your chest",
        "Insufficient Depth": "Squat a little deeper"
    ]
    
    // Aggregation for mid-set feedback (collected during the set, spoken between sets)
    private var issueCounts: [String: Int] = [:]
    private var positiveCounts: [String: Int] = [:]
    private let positiveCueByKey: [String: String] = [
        "Good Depth": "Good depth",
        "Chest Tall": "Chest tall",
        "Knees Over Toes": "Knees over toes"
    ]
    
    // Tempo tracking for hypertrophy (milliseconds)
    private var repStartTime: CFTimeInterval?
    private var bottomTime: CFTimeInterval?
    private var lastDepth: Float = 0
    private var sumEccentricMs: Double = 0  // Total time going down
    private var sumPauseMs: Double = 0      // Total time paused at bottom
    private var sumConcentricMs: Double = 0 // Total time coming up
    private var tempoRepSamples: Int = 0
    private let bottomDepthThreshold: Float = 0.58 // align with deep threshold
    private let topDepthThreshold: Float = 0.48    // align with shallow threshold

    // ROM tracking (depth-based)
    private var sumBottomDepth: Double = 0
    private var bottomDepthSamples: Int = 0
    private var deepFrameCount: Int = 0
    private var totalDepthSamples: Int = 0
    private var currentRepBottomDepthMax: Float = 0
    
    override init() {
        super.init()
        setupPoseDetection()
    }
    
    private func setupPoseDetection() {
        poseRequest = VNDetectHumanBodyPoseRequest { [weak self] request, error in
            self?.handlePoseDetection(request: request, error: error)
        }
    }
    
    // MARK: - Pose Detection
    func analyzeFrame(_ pixelBuffer: CVPixelBuffer) {
        guard let poseRequest = poseRequest else { return }
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        
        do {
            try handler.perform([poseRequest])
            
            if let observations = poseRequest.results, !observations.isEmpty {
                let observation = observations[0]
                
                // Update pose detection status
                DispatchQueue.main.async {
                    self.poseDetected = true
                    self.inactivityDetector.updateLastActivity()
                }
                
                // Analyze form and update current analysis
                let formAnalysis = analyzeForm(observation)
                
                // Update tempo tracking using current depth
                self.updateTempoTracking(currentDepth: formAnalysis.depth)
                
                // (Removed verbose nose/depth debug logging)
                
                // IMPORTANT: Ensure this runs on main thread for UI updates
                DispatchQueue.main.async {
                    self.currentFormAnalysis = formAnalysis
                }
                // Real-time cues disabled; feedback will be spoken at set end only
                
                // Aggregate issues and positives for between-sets feedback
                self.aggregateFeedback(from: formAnalysis)
                
                // Check for rep detection on background thread
                if validateRep() {
                    DispatchQueue.main.async {
                        self.handleRepDetected()
                    }
                }
                
                // Check for set transitions
                checkForSetEnd()
                checkForNextSetStart()
                
            } else {
                DispatchQueue.main.async {
                    self.poseDetected = false
                }
            }
        } catch {
            print("⚠️ Error analyzing frame: \(error)")
        }
    }
    
    private func handlePoseDetection(request: VNRequest, error: Error?) {
        guard let observations = request.results as? [VNHumanBodyPoseObservation] else {
            poseDetected = false
            return
        }
        
        guard let observation = observations.first else {
            poseDetected = false
            return
        }
        
        poseDetected = true
        
        // Analyze form
        let formAnalysis = analyzeForm(observation)
        
        DispatchQueue.main.async {
            self.currentFormAnalysis = formAnalysis
        }
    }
    
    // MARK: - Form Analysis
    private func analyzeForm(_ observation: VNHumanBodyPoseObservation) -> FormAnalysis {
        // Extract key points
        let points = extractKeyPoints(from: observation)
        
        // Use optimized analysis based on squat type
        switch squatType {
        case .bodyweight:
            return analyzeBodyweightSquatForm(points)
        case .barbell:
            return analyzeBarbellSquatForm(points)
        case .benchPress:
            // Regular bench press - use bodyweight analysis as fallback until implemented
            return analyzeBodyweightSquatForm(points)
        case .closeGripBenchPress:
            // Close-grip bench press with view-specific analysis
            return analyzeCloseGripBenchPressForm(points)
        }
    }
    
    private func analyzeBodyweightSquatForm(_ points: [String: CGPoint]) -> FormAnalysis {
        // Enhanced analysis for bodyweight squats with optimized parameters
        
        // Calculate form metrics with bodyweight-specific thresholds
        let depth = calculateBodyweightDepth(points)
        let backAngle = calculateBodyweightBackAngle(points)
        let kneeAlignment = calculateBodyweightKneeAlignment(points)
        let overallScore = calculateBodyweightOverallScore(depth: depth, backAngle: backAngle, kneeAlignment: kneeAlignment)
        let issues = detectBodyweightIssues(depth: depth, backAngle: backAngle, kneeAlignment: kneeAlignment)
        
        // Generate summary with bodyweight-specific feedback
        let summary = generateBodyweightFormSummary(depth: depth, backAngle: backAngle, overallScore: overallScore)
        
        return FormAnalysis(
            depth: depth,
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
    
    private func analyzeBarbellSquatForm(_ points: [String: CGPoint]) -> FormAnalysis {
        // TODO: Enhance barbell squat analysis with barbell-specific thresholds:
        // - Different acceptable torso angle for heavy barbell vs. bodyweight
        // - Stricter depth requirements for loaded squats
        // - Bar path tracking (if possible with pose estimation)
        // - Upper back tightness indicators
        
        // Currently uses standard analysis (reuses bodyweight logic)
        // Future: Add barbell-specific form checks and thresholds
        let depth = calculateDepth(points)
        let backAngle = calculateBackAngle(points)
        let overallScore = calculateOverallScore(depth: depth, backAngle: backAngle)
        
        let summary = generateFormSummary(depth: depth, backAngle: backAngle, overallScore: overallScore)
        
        return FormAnalysis(
            depth: depth,
            backAngle: backAngle,
            kneeAlignment: 0.0,
            overallScore: overallScore,
            issues: [],
            summary: summary,
            repCount: repCount,
            avgEccentricMs: nil,
            avgPauseMs: nil,
            avgConcentricMs: nil,
            avgBottomDepth: nil,
            deepRepRatio: nil
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
        
        // Detect issues
        var issues: [String] = []
        if gripWidthScore < 0.6 {
            issues.append("Grip Too Wide")
        }
        if elbowPositionScore < 0.6 {
            issues.append("Elbows Flaring")
        }
        if romScore < 0.6 {
            issues.append("Incomplete ROM")
        }
        if eccentricScore < 0.6 {
            issues.append("Eccentric Too Fast")
        }
        if concentricScore < 0.6 {
            issues.append("Concentric Too Slow")
        }
        
        // Generate summary
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
    /// Ideal grip is 0.8-1.0x shoulder width (just outside ribs).
    /// Applies view-specific adjustments for camera angle differences.
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
        if adjustedGripRatio >= 0.8 && adjustedGripRatio <= 1.0 {
            return 1.0 // Perfect close-grip width
        } else if adjustedGripRatio < 0.8 {
            // Grip too narrow
            return max(0.3, adjustedGripRatio / 0.8)
        } else {
            // Grip too wide
            let overWidth = adjustedGripRatio - 1.0
            return max(0.3, 1.0 - (overWidth * 2.0))
        }
    }
    
    /// Calculates elbow position score for close-grip bench press.
    /// Ideal position: elbows flush to sides (not flared out).
    /// Applies view-specific adjustments for camera angle differences.
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
        if adjustedFlareRatio <= 0.5 {
            return 1.0 // Perfect elbow position
        } else if adjustedFlareRatio <= 0.7 {
            // Slightly flared
            return 0.8 - ((adjustedFlareRatio - 0.5) * 1.0)
        } else {
            // Significantly flared
            return max(0.3, 0.6 - ((adjustedFlareRatio - 0.7) * 1.0))
        }
    }
    
    /// Calculates range of motion score for close-grip bench press.
    /// Checks for full lockout at top and chest touch at bottom.
    /// Uses view-specific reference points based on camera angle.
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
            // At lockout: wrist should be significantly above elbow (lower Y in Vision coords)
            let elbowExtension = avgElbowY - avgWristY
            if elbowExtension > 0.1 {
                return 1.0 // Good lockout
            } else if elbowExtension > 0 {
                return 0.7 // Partial lockout
            } else {
                return max(0.3, 0.5 + elbowExtension) // Incomplete extension
            }
        }
    }
    
    /// Calculates bench press depth using average wrist Y position for rep detection.
    /// Higher Y = deeper/lower bar position in Vision coordinate system.
    private func calculateBenchPressDepth(_ points: [String: CGPoint]) -> Float {
        guard let leftWrist = points["leftWrist"],
              let rightWrist = points["rightWrist"] else {
            return 0.5
        }
        
        // Average wrist Y position (higher Y = deeper/lower bar position in Vision coords)
        return Float((leftWrist.y + rightWrist.y) / 2.0)
    }
    
    /// Calculates eccentric (lowering) tempo score.
    /// Target: ≥1000ms (1 second). Penalizes faster lowering.
    private func calculateBenchPressEccentricScore() -> Float {
        guard tempoRepSamples > 0 else { return 0.7 } // Default to decent score if no data
        
        let avgEccentricMs = sumEccentricMs / Double(tempoRepSamples)
        
        // Target: ≥1000ms (1 second)
        if avgEccentricMs >= 1000 {
            return 1.0
        } else if avgEccentricMs >= 700 {
            return 0.8
        } else if avgEccentricMs >= 500 {
            return 0.6
        } else {
            return max(0.3, Float(avgEccentricMs / 1000.0))
        }
    }
    
    /// Calculates concentric (pressing) tempo score.
    /// Target: ≤2000ms (2 seconds). Penalizes slower pressing.
    private func calculateBenchPressConcentricScore() -> Float {
        guard tempoRepSamples > 0 else { return 0.7 } // Default to decent score if no data
        
        let avgConcentricMs = sumConcentricMs / Double(tempoRepSamples)
        
        // Target: ≤2000ms (2 seconds)
        if avgConcentricMs <= 2000 {
            return 1.0
        } else if avgConcentricMs <= 2500 {
            return 0.8
        } else if avgConcentricMs <= 3000 {
            return 0.6
        } else {
            return max(0.3, Float(2000.0 / avgConcentricMs))
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
    
    private func extractKeyPoints(from observation: VNHumanBodyPoseObservation) -> [String: CGPoint] {
        var points: [String: CGPoint] = [:]
        
        // Extract key body points
        let recognizedPoints = try? observation.recognizedPoints(.all)
        
        for (key, point) in recognizedPoints ?? [:] {
            if point.confidence > 0.1 {
                // Map Vision joint names to our expected names
                let jointName = mapVisionJointName(key)
                if !jointName.isEmpty {
                    points[jointName] = point.location
                }
            }
        }
        
        return points
    }
    
    private func mapVisionJointName(_ jointName: VNHumanBodyPoseObservation.JointName) -> String {
        // Map Vision's joint names to our expected names
        switch jointName {
        case .leftHip:
            return "leftHip"
        case .rightHip:
            return "rightHip"
        case .leftKnee:
            return "leftKnee"
        case .rightKnee:
            return "rightKnee"
        case .leftAnkle:
            return "leftAnkle"
        case .rightAnkle:
            return "rightAnkle"
        case .leftShoulder:
            return "leftShoulder"
        case .rightShoulder:
            return "rightShoulder"
        case .leftElbow:
            return "leftElbow"
        case .rightElbow:
            return "rightElbow"
        case .leftWrist:
            return "leftWrist"
        case .rightWrist:
            return "rightWrist"
        case .nose:
            return "nose"
        case .leftEye:
            return "leftEye"
        case .rightEye:
            return "rightEye"
        case .leftEar:
            return "leftEar"
        case .rightEar:
            return "rightEar"
        case .neck:
            return "neck"
        case .root:
            return "root"
        default:
            return ""
        }
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
        
        // In Vision coordinates: Y=0 is top, Y=1 is bottom
        // When squatting: nose Y increases (moves down)
        // When standing: nose Y decreases (moves up)
        
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
    private func detectBodyweightIssues(depth: Float, backAngle: Float, kneeAlignment: Float) -> [String] {
        var issues: [String] = []
        
        // Depth
        if depth < 0.45 { // shallow
            issues.append("Insufficient Depth")
        }
        
        // Torso angle (forward lean)
        if backAngle > 35.0 { // large lean
            issues.append("Forward Lean")
        }
        
        // Knee tracking
        if kneeAlignment < -0.2 {
            issues.append("Knees Caving In")
        } else if kneeAlignment > 0.2 {
            issues.append("Knees Bowing Out")
        }
        
        // Limit to top two to avoid spamming
        return Array(issues.prefix(2))
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
        repCount = 0
        consecutiveGoodReps = 0
        lastRepTime = nil
        setStartTime = nil
        lastRepValidationTime = nil
        lastSpokenRep = 0
        reachedDeepThisCycle = false // Reset the cycle state
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
        print("🔄 Rep count and state reset")
    }
    
    // Add method to reset rep counting state
    func resetRepCountingState() {
        repCount = 0
        consecutiveGoodReps = 0
        lastRepTime = nil
        setStartTime = nil
        lastRepValidationTime = nil
        lastSpokenRep = 0
        reachedDeepThisCycle = false
        workoutState = .waiting
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
        print("🔄 Rep counting state reset")
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
        currentSet += 1
        workoutState = .waiting
        resetRepCount()
        print("🎯 Starting new set: \(currentSet)")
        
        // Provide audio feedback
        SpeechManager.shared.speak("Starting set \(currentSet)", priority: .normal)
    }
    
    // Enhanced rep validation logic - MORE SENSITIVE
    private func validateRep() -> Bool {
        guard let formAnalysis = currentFormAnalysis else { return false }
        
        // Require minimum confidence in pose detection
        if formAnalysis.overallScore < poseConfidenceThreshold {
            return false
        }
        
        let now = Date()
        
        // Time gating to prevent double counting
        if let lastValidation = lastRepValidationTime,
           now.timeIntervalSince(lastValidation) < minTimeBetweenReps {
            return false
        }
        
        // Use different validation logic based on exercise type
        switch squatType {
        case .closeGripBenchPress:
            return validateCloseGripBenchPressRep(formAnalysis: formAnalysis, now: now)
        case .bodyweight, .barbell, .benchPress:
            return validateSquatRep(formAnalysis: formAnalysis, now: now)
        }
    }
    
    /// Validate squat rep (bodyweight, barbell, or regular bench press fallback)
    private func validateSquatRep(formAnalysis: FormAnalysis, now: Date) -> Bool {
        let depth = formAnalysis.depth
        
        // State machine for rep counting - MORE SENSITIVE
        if depth >= deepDepthThreshold {
            if !reachedDeepThisCycle {
                print("🏋️ Deep phase detected: depth=\(depth) (threshold: \(deepDepthThreshold))")
                reachedDeepThisCycle = true
            }
            return false
        }
        
        // Check if we completed a full cycle (deep -> shallow) - MORE SENSITIVE
        if reachedDeepThisCycle && depth <= shallowDepthThreshold {
            print("✅ Rep validated! Deep(\(deepDepthThreshold)) -> Shallow(\(depth)) (threshold: \(shallowDepthThreshold))")
            lastRepValidationTime = now
            reachedDeepThisCycle = false
            return true
        }
        
        // Additional check: if we're in a deep position but haven't marked it yet, mark it
        if depth >= (deepDepthThreshold - 0.03) && !reachedDeepThisCycle {
            print("🏋️ Near-deep phase detected: depth=\(depth) (near threshold: \(deepDepthThreshold - 0.03))")
            reachedDeepThisCycle = true
        }
        
        return false
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
        let wristY = formAnalysis.depth // For bench press, depth field stores wrist Y position
        
        // Bench press thresholds (based on wrist Y position)
        // Higher Y = bar closer to chest (bottom position)
        // Lower Y = bar at lockout (top position)
        // View-specific thresholds
        let (bottomThreshold, topThreshold): (Float, Float)
        switch benchPressViewType {
        case .rack:
            // Top-down view: Y increases as bar goes down
            bottomThreshold = 0.65
            topThreshold = 0.45
        case .floor:
            // Bottom-up view: Y decreases as bar goes down (inverted)
            bottomThreshold = 0.35
            topThreshold = 0.55
        case .tripod:
            // Side view: similar to rack but slightly different range
            bottomThreshold = 0.60
            topThreshold = 0.42
        }
        
        // State machine for bench press rep counting
        // Step 1: Detect bottom position (bar at chest)
        if benchPressViewType == .floor {
            // Floor view has inverted Y axis
            if wristY <= bottomThreshold {
                if !reachedBottomThisCycleBenchPress {
                    print("🏋️ Bench press bottom detected (floor view): wristY=\(wristY) (threshold: \(bottomThreshold))")
                    reachedBottomThisCycleBenchPress = true
                    // Start tracking concentric tempo
                    benchPressBottomTime = CACurrentMediaTime()
                }
                return false
            }
            
            // Step 2: Detect top position (lockout) after reaching bottom
            if reachedBottomThisCycleBenchPress && wristY >= topThreshold {
                print("✅ Bench press rep validated (floor view)! Bottom(\(bottomThreshold)) -> Top(\(wristY)) (threshold: \(topThreshold))")
                
                // Calculate tempo for this rep
                if let bottomTime = benchPressBottomTime {
                    let concentricMs = (CACurrentMediaTime() - bottomTime) * 1000
                    sumConcentricMs += concentricMs
                    tempoRepSamples += 1
                    print("📊 Bench press concentric time: \(Int(concentricMs))ms")
                }
                
                lastRepValidationTime = now
                reachedBottomThisCycleBenchPress = false
                benchPressEccentricStartTime = CACurrentMediaTime() // Start tracking next eccentric
                return true
            }
        } else {
            // Rack and Tripod views: standard Y axis
            if wristY >= bottomThreshold {
                if !reachedBottomThisCycleBenchPress {
                    print("🏋️ Bench press bottom detected: wristY=\(wristY) (threshold: \(bottomThreshold))")
                    reachedBottomThisCycleBenchPress = true
                    // Calculate eccentric tempo
                    if let eccentricStart = benchPressEccentricStartTime {
                        let eccentricMs = (CACurrentMediaTime() - eccentricStart) * 1000
                        sumEccentricMs += eccentricMs
                        print("📊 Bench press eccentric time: \(Int(eccentricMs))ms")
                    }
                    // Start tracking concentric tempo
                    benchPressBottomTime = CACurrentMediaTime()
                }
                return false
            }
            
            // Step 2: Detect top position (lockout) after reaching bottom
            if reachedBottomThisCycleBenchPress && wristY <= topThreshold {
                print("✅ Bench press rep validated! Bottom(\(bottomThreshold)) -> Top(\(wristY)) (threshold: \(topThreshold))")
                
                // Calculate concentric tempo for this rep
                if let bottomTime = benchPressBottomTime {
                    let concentricMs = (CACurrentMediaTime() - bottomTime) * 1000
                    sumConcentricMs += concentricMs
                    tempoRepSamples += 1
                    print("📊 Bench press concentric time: \(Int(concentricMs))ms")
                }
                
                lastRepValidationTime = now
                reachedBottomThisCycleBenchPress = false
                benchPressEccentricStartTime = CACurrentMediaTime() // Start tracking next eccentric
                return true
            }
        }
        
        return false
    }
    
    // Add debug logging to track rep detection
    private func handleRepDetected() {
        repCount += 1
        consecutiveGoodReps += 1
        lastRepTime = Date()
        inactivityDetector.updateLastRep()
        
        print("🎯 Rep \(repCount) detected at depth cycle completion")
        
        // Check if we should start the set (after minimum reps)
        if workoutState == .waiting && consecutiveGoodReps >= minRepsForSetStart {
            handleSetStart()
        }
    }
    
    private func handleSetStart() {
        workoutState = .exercising
        setStartTime = Date()
        // Reset aggregations at the start of a set
        issueCounts.removeAll()
        positiveCounts.removeAll()
        // Reset tempo/ROM aggregations per set
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
        print("🎯 Set started automatically with \(repCount) reps")
    }
    
    private func handleSetEnd() {
        guard workoutState == .exercising else { return }
        
        workoutState = .resting
        restStartTime = Date()
        
        print("🏁 Set ended automatically")
        
        // Reset rep count for next set (but keep total workout state)
        let completedReps = repCount
        repCount = 0
        consecutiveGoodReps = 0
        reachedDeepThisCycle = false
        lastRepValidationTime = nil
        print("🔄 Reset rep count for next set (completed \(completedReps) reps)")
        
        // Get single natural feedback and speak it once
        if let analysis = currentFormAnalysis {
            OpenAICoachingManager.shared.analyzeAndGetNaturalFeedback(
                formAnalysis: analysis,
                exerciseType: squatType
            ) { naturalFeedback in
                print("🎯 Received natural feedback for set completion: \(naturalFeedback)")
                // Speech is already handled inside analyzeAndGetNaturalFeedback
            }
        }
        
        // Start rest period timer
        DispatchQueue.main.asyncAfter(deadline: .now() + restPeriodDuration) {
            self.handleRestPeriodEnd()
        }
    }
    
    private func handleRestPeriodEnd() {
        guard workoutState == .resting else { return }
        
        workoutState = .waiting
        print("⏰ Rest period ended, ready for next set")
    }
    
    func checkForNextSetStart() {
        guard workoutState == .waiting else { return }
        
        // If we detect a rep while waiting, it might be the start of a new set
        if validateRep() {
            consecutiveGoodReps += 1
            
            if consecutiveGoodReps >= minRepsForSetStart {
                handleSetStart()
            }
        }
    }

    // Public method to allow UI to force end a set and use aggregated feedback
    func forceEndCurrentSet() {
        handleSetEnd()
    }

    // MARK: - Aggregation helpers
    private func aggregateFeedback(from analysis: FormAnalysis) {
        // Count issues
        for issue in analysis.issues {
            issueCounts[issue, default: 0] += 1
        }
        // Positives
        if analysis.depth >= 0.6 { positiveCounts["Good Depth", default: 0] += 1 }
        if abs(analysis.backAngle) <= 25 { positiveCounts["Chest Tall", default: 0] += 1 }
        if abs(analysis.kneeAlignment) <= 0.1 { positiveCounts["Knees Over Toes", default: 0] += 1 }
    }
    
    // MARK: - Legacy Two-Point Feedback (Deprecated)
    // This method is no longer used - replaced with single natural feedback
    @available(*, deprecated, message: "Use OpenAICoachingManager.analyzeAndGetNaturalFeedback instead")
    private func aggregatedTwoPointFeedback() -> (String, String) {
        // Choose most frequent positive
        let topPositiveKey = positiveCounts.max(by: { $0.value < $1.value })?.key
        let good = (topPositiveKey.flatMap { positiveCueByKey[$0] }) ?? {
            if let analysis = currentFormAnalysis {
                if analysis.depth >= 0.6 { return "Good depth" }
                if abs(analysis.backAngle) <= 25 { return "Chest tall" }
            }
            return "Controlled tempo"
        }()
        
        // Choose most frequent issue
        let topIssue = issueCounts.max(by: { $0.value < $1.value })?.key
        let improve: String = {
            if let issue = topIssue, let cue = cueByIssue[issue] { return cue }
            if let analysis = currentFormAnalysis {
                if analysis.issues.contains("Knees Caving In") { return "Push your knees out" }
                if analysis.issues.contains("Knees Bowing Out") { return "Keep your knees over your toes" }
                if analysis.issues.contains("Forward Lean") { return "Lift your chest" }
                if analysis.depth < 0.45 { return "Squat a little deeper" }
            }
            return "Brace your core"
        }()
        
        return (good, improve)
    }
    
    private func updateTempoTracking(currentDepth: Float) {
        let now = CACurrentMediaTime()
        // ROM sampling each frame
        totalDepthSamples += 1
        if currentDepth >= bottomDepthThreshold { deepFrameCount += 1 }
        if currentDepth > currentRepBottomDepthMax { currentRepBottomDepthMax = currentDepth }
        if repStartTime == nil, currentDepth <= topDepthThreshold {
            repStartTime = now
        }
        // Detect arriving at bottom
        if lastDepth < bottomDepthThreshold && currentDepth >= bottomDepthThreshold {
            bottomTime = now
        }
        // Detect leaving bottom (start concentric) and compute pause
        if let bTime = bottomTime, lastDepth >= bottomDepthThreshold && currentDepth < bottomDepthThreshold {
            let pauseMs = max(0, (now - bTime) * 1000.0)
            sumPauseMs += pauseMs
        }
        // Detect rep completion when returning near top
        if let start = repStartTime, lastDepth > topDepthThreshold && currentDepth <= topDepthThreshold {
            let totalMs = (now - start) * 1000.0
            // Approximate split: eccentric until bottom, concentric from leaving bottom to top
            // If bottomTime not available, split evenly as fallback
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
            // Record bottom depth for ROM
            if currentRepBottomDepthMax > 0 {
                sumBottomDepth += Double(currentRepBottomDepthMax)
                bottomDepthSamples += 1
            }
            // Reset markers for next rep
            repStartTime = nil
            bottomTime = nil
            currentRepBottomDepthMax = 0
        }
        lastDepth = currentDepth
    }
}
