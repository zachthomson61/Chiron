import Foundation
import Vision
import AVFoundation
import Combine
import SwiftUI // Added for Color

protocol PoseDetectionDelegate {
    func poseDetectionUpdated(_ results: PoseDetectionResults)
    func cameraSetupStatusUpdated(_ status: CameraSetupStatus)
    func squatRepCompleted(isGoodForm: Bool)
    func formFeedbackUpdated(_ feedback: FormFeedback)
}

struct PoseDetectionResults {
    let keyPoints: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]
    let confidence: Float
    let isFullBodyVisible: Bool
    let bodyOutlinePoints: [CGPoint] // Added for body outline drawing
}

struct CameraSetupStatus {
    let isFullBodyVisible: Bool
    let hasGoodLighting: Bool
    let hasStablePosition: Bool
}

struct FormFeedback {
    let depthStatus: FormStatus
    let postureStatus: FormStatus
    let tempoStatus: FormStatus
    let message: String
}



enum SquatPhase {
    case standing, descending, bottom, ascending
}

class PoseDetectionManager: ObservableObject {
    var delegate: PoseDetectionDelegate?
    
    // Detection properties
    private var poseRequest: VNDetectHumanBodyPoseRequest?
    private var lastDetectionTime: Date = Date()
    private let detectionInterval: TimeInterval = 0.1 // 10 FPS
    
    // Squat tracking
    private var squatPhase: SquatPhase = .standing
    private var repStartTime: Date?
    private var previousHipY: CGFloat = 0
    private var stableFrameCount: Int = 0
    private var previousKeyPoints: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint] = [:]
    
    // Setup tracking
    private var setupCheckFrames: Int = 0
    private let requiredSetupFrames = 15 // Reduced for faster response
    
    // Configuration
    var isDetectionActive: Bool = false
    var exerciseType: String = "Squat"
    
    init() {
        setupPoseDetection()
    }
    
    // MARK: - Public Methods
    func startDetection() {
        isDetectionActive = true
        resetSquatTracking()
    }
    
    func stopDetection() {
        isDetectionActive = false
    }
    
    func processVideoFrame(_ sampleBuffer: CMSampleBuffer) {
        guard isDetectionActive else { return }
        
        // Throttle detection
        let now = Date()
        guard now.timeIntervalSince(lastDetectionTime) >= detectionInterval else { return }
        lastDetectionTime = now
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let poseRequest = poseRequest else { return }
        
        let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        
        do {
            try requestHandler.perform([poseRequest])
        } catch {
            print("Pose detection failed: \(error)")
        }
    }
    
    // MARK: - Private Setup
    private func setupPoseDetection() {
        poseRequest = VNDetectHumanBodyPoseRequest { [weak self] request, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Pose detection error: \(error)")
                return
            }
            
            guard let observations = request.results as? [VNHumanBodyPoseObservation],
                  let observation = observations.first else {
                DispatchQueue.main.async {
                    self.handleNoPoseDetected()
                }
                return
            }
            
            DispatchQueue.main.async {
                self.processPoseObservation(observation)
            }
        }
        
        poseRequest?.revision = VNDetectHumanBodyPoseRequestRevision1
    }
    
    private func handleNoPoseDetected() {
        let setupStatus = CameraSetupStatus(
            isFullBodyVisible: false,
            hasGoodLighting: false,
            hasStablePosition: false
        )
        delegate?.cameraSetupStatusUpdated(setupStatus)
    }
    
    // MARK: - Pose Processing
    private func processPoseObservation(_ observation: VNHumanBodyPoseObservation) {
        guard let keyPoints = try? observation.recognizedPoints(.all) else { return }
        
        let bodyOutlinePoints = generateBodyOutlinePoints(from: keyPoints)
        let isFullBodyVisible = checkBodyVisibility(keyPoints)
        
        let results = PoseDetectionResults(
            keyPoints: keyPoints,
            confidence: observation.confidence,
            isFullBodyVisible: isFullBodyVisible,
            bodyOutlinePoints: bodyOutlinePoints
        )
        
        delegate?.poseDetectionUpdated(results)
        
        // Check camera setup status
        checkCameraSetupStatus(keyPoints, confidence: observation.confidence)
        
        // Analyze exercise form if in workout mode
        if exerciseType == "Squat" {
            analyzeSquatForm(keyPoints)
        }
        
        // Store for stability checking
        previousKeyPoints = keyPoints
    }
    
    // MARK: - Body Outline Generation
    private func generateBodyOutlinePoints(from keyPoints: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) -> [CGPoint] {
        var outlinePoints: [CGPoint] = []
        
        // Define body outline order for close-up detection (prioritizing upper body)
        let bodyOutlineOrder: [VNHumanBodyPoseObservation.JointName] = [
            .nose, .leftEye, .leftEar, .leftShoulder, .leftElbow, .leftWrist,
            .leftHip, .rightHip, .rightWrist, .rightElbow, .rightShoulder, 
            .rightEar, .rightEye
        ]
        
        // Generate outline points with more lenient confidence thresholds
        for jointName in bodyOutlineOrder {
            if let point = keyPoints[jointName], point.confidence > 0.2 { // Very low threshold for close-up
                let cgPoint = CGPoint(x: point.location.x, y: 1.0 - point.location.y) // Flip Y coordinate
                outlinePoints.append(cgPoint)
            }
        }
        
        // If we don't have enough points for a full outline, create a simplified version
        if outlinePoints.count < 4 {
            outlinePoints = generateSimplifiedOutline(from: keyPoints)
        }
        
        return outlinePoints
    }
    
    private func generateSimplifiedOutline(from keyPoints: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) -> [CGPoint] {
        var points: [CGPoint] = []
        
        // Try to get at least head and shoulders for close-up
        let essentialPoints: [VNHumanBodyPoseObservation.JointName] = [
            .nose, .leftShoulder, .rightShoulder, .leftElbow, .rightElbow
        ]
        
        for jointName in essentialPoints {
            if let point = keyPoints[jointName], point.confidence > 0.15 { // Even lower threshold
                let cgPoint = CGPoint(x: point.location.x, y: 1.0 - point.location.y)
                points.append(cgPoint)
            }
        }
        
        return points
    }
    
    // MARK: - Camera Setup Analysis
    private func checkBodyVisibility(_ keyPoints: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) -> Bool {
        // For close-up detection, focus on upper body and head
        let closeUpEssentialPoints: [VNHumanBodyPoseObservation.JointName] = [
            .nose, .leftEye, .rightEye, .leftShoulder, .rightShoulder
        ]
        
        let visibleEssentialPoints = closeUpEssentialPoints.compactMap { keyPoints[$0] }
            .filter { $0.confidence > 0.2 } // Very low confidence for close-up
        
        // Additional upper body points for better detection
        let upperBodyPoints: [VNHumanBodyPoseObservation.JointName] = [
            .leftElbow, .rightElbow, .leftWrist, .rightWrist, .neck
        ]
        
        let visibleUpperBodyPoints = upperBodyPoints.compactMap { keyPoints[$0] }
            .filter { $0.confidence > 0.15 }
        
        // Check if we have face OR good upper body detection
        let hasGoodFaceDetection = keyPoints[.nose]?.confidence ?? 0 > 0.3
        let hasGoodShoulderDetection = (keyPoints[.leftShoulder]?.confidence ?? 0 > 0.3) && 
                                      (keyPoints[.rightShoulder]?.confidence ?? 0 > 0.3)
        
        let essentialRatio = Float(visibleEssentialPoints.count) / Float(closeUpEssentialPoints.count)
        let upperBodyRatio = Float(visibleUpperBodyPoints.count) / Float(upperBodyPoints.count)
        
        // Much more lenient criteria for close-up detection
        return hasGoodFaceDetection || hasGoodShoulderDetection || essentialRatio >= 0.4 || upperBodyRatio >= 0.3
    }
    
    private func checkCameraSetupStatus(_ keyPoints: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint], confidence: Float) {
        let isFullBodyVisible = checkBodyVisibility(keyPoints)
        let hasGoodLighting = confidence > 0.4 // Lower threshold for close-up
        
        // Check stability by comparing key points with previous frame
        var hasStablePosition = false
        if !previousKeyPoints.isEmpty {
            let stability = calculateStability(current: keyPoints, previous: previousKeyPoints)
            if stability > 0.8 { // 80% stability threshold
                stableFrameCount += 1
                hasStablePosition = stableFrameCount > 3 // Faster stability check
            } else {
                stableFrameCount = 0
            }
        }
        
        let setupStatus = CameraSetupStatus(
            isFullBodyVisible: isFullBodyVisible,
            hasGoodLighting: hasGoodLighting,
            hasStablePosition: hasStablePosition
        )
        
        delegate?.cameraSetupStatusUpdated(setupStatus)
    }
    
    private func calculateStability(current: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint], 
                                   previous: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) -> Float {
        let trackingPoints: [VNHumanBodyPoseObservation.JointName] = [.nose, .leftShoulder, .rightShoulder]
        var stabilityScores: [Float] = []
        
        for point in trackingPoints {
            if let currentPoint = current[point], let previousPoint = previous[point],
               currentPoint.confidence > 0.2, previousPoint.confidence > 0.2 {
                let distance = sqrt(pow(currentPoint.location.x - previousPoint.location.x, 2) + 
                                  pow(currentPoint.location.y - previousPoint.location.y, 2))
                let stability = max(0, 1.0 - Float(distance * 10)) // Scale distance
                stabilityScores.append(stability)
            }
        }
        
        return stabilityScores.isEmpty ? 0 : stabilityScores.reduce(0, +) / Float(stabilityScores.count)
    }
    
    // MARK: - Squat Analysis
    private func analyzeSquatForm(_ keyPoints: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) {
        guard let leftHip = keyPoints[.leftHip],
              let rightHip = keyPoints[.rightHip],
              let leftKnee = keyPoints[.leftKnee],
              let rightKnee = keyPoints[.rightKnee],
              leftHip.confidence > 0.3, // Lowered confidence thresholds
              rightHip.confidence > 0.3,
              leftKnee.confidence > 0.3,
              rightKnee.confidence > 0.3 else {
            return
        }
        
        let hipY = (leftHip.location.y + rightHip.location.y) / 2
        let kneeY = (leftKnee.location.y + rightKnee.location.y) / 2
        
        // Track squat phases and count reps
        let isInDeepPosition = hipY < kneeY
        trackSquatPhase(isInDeepPosition: isInDeepPosition, hipY: hipY, kneeY: kneeY)
        
        // Analyze form
        let formFeedback = analyzeSquatFormDetails(keyPoints, hipY: hipY, kneeY: kneeY)
        delegate?.formFeedbackUpdated(formFeedback)
    }
    
    private func trackSquatPhase(isInDeepPosition: Bool, hipY: CGFloat, kneeY: CGFloat) {
        switch squatPhase {
        case .standing:
            if isInDeepPosition {
                squatPhase = .descending
                repStartTime = Date()
            }
        case .descending:
            if isInDeepPosition {
                squatPhase = .bottom
            }
        case .bottom:
            if !isInDeepPosition {
                squatPhase = .ascending
            }
        case .ascending:
            if !isInDeepPosition {
                // Rep completed
                completeSquatRep(hipY: hipY, kneeY: kneeY)
            }
        }
        
        previousHipY = hipY
    }
    
    private func completeSquatRep(hipY: CGFloat, kneeY: CGFloat) {
        squatPhase = .standing
        repStartTime = nil
        
        // Determine if it was good form based on depth
        let depthRatio = (kneeY - hipY) / kneeY
        let isGoodForm = depthRatio > 0.05 // Hip went below knee level
        
        delegate?.squatRepCompleted(isGoodForm: isGoodForm)
    }
    
    private func analyzeSquatFormDetails(_ keyPoints: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint], hipY: CGFloat, kneeY: CGFloat) -> FormFeedback {
        
        // Analyze depth
        let depthRatio = (kneeY - hipY) / kneeY
        let depthStatus: FormStatus
        let depthMessage: String
        
        if depthRatio > 0.15 {
            depthStatus = .perfect
            depthMessage = "Perfect depth!"
        } else if depthRatio > 0.05 {
            depthStatus = .good
            depthMessage = "Good depth"
        } else if depthRatio > -0.05 {
            depthStatus = .watch
            depthMessage = "Go deeper"
        } else {
            depthStatus = .poor
            depthMessage = "Not deep enough"
        }
        
        // Analyze posture
        let postureStatus = analyzePosture(keyPoints)
        
        // Tempo analysis (simplified)
        let tempoStatus: FormStatus = .good
        
        return FormFeedback(
            depthStatus: depthStatus,
            postureStatus: postureStatus,
            tempoStatus: tempoStatus,
            message: depthMessage
        )
    }
    
    private func analyzePosture(_ keyPoints: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) -> FormStatus {
        guard let leftShoulder = keyPoints[.leftShoulder],
              let rightShoulder = keyPoints[.rightShoulder],
              let leftHip = keyPoints[.leftHip],
              let rightHip = keyPoints[.rightHip],
              leftShoulder.confidence > 0.3, // Lowered thresholds
              rightShoulder.confidence > 0.3,
              leftHip.confidence > 0.3,
              rightHip.confidence > 0.3 else {
            return .watch
        }
        
        // Calculate torso angle
        let shoulderY = (leftShoulder.location.y + rightShoulder.location.y) / 2
        let hipY = (leftHip.location.y + rightHip.location.y) / 2
        let shoulderX = (leftShoulder.location.x + rightShoulder.location.x) / 2
        let hipX = (leftHip.location.x + rightHip.location.x) / 2
        
        let torsoAngle = atan2(shoulderY - hipY, shoulderX - hipX) * 180 / .pi
        
        if abs(torsoAngle) < 15 {
            return .perfect
        } else if abs(torsoAngle) < 30 {
            return .good
        } else if abs(torsoAngle) < 45 {
            return .watch
        } else {
            return .poor
        }
    }
    
    private func resetSquatTracking() {
        squatPhase = .standing
        repStartTime = nil
        previousHipY = 0
        stableFrameCount = 0
        setupCheckFrames = 0
        previousKeyPoints = [:]
    }
}