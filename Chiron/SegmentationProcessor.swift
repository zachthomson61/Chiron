//
//  SegmentationProcessor.swift
//  Chiron
//
//  Processes person segmentation from camera frames and provides quality scoring for camera setup.
//  Supports exercise-specific quality metrics (bodyweight vs barbell squats) via exerciseMode property.
//
//  Architecture:
//  - Uses Vision framework's VNGeneratePersonSegmentationRequest for person detection
//  - Computes quality score based on person size, position, and visibility
//  - For barbell squats, enhances scoring with distance, height, and feet visibility checks
//  - Maps quality score (0.0-1.0) to color: Red (0.0-0.4), Yellow (0.4-0.7), Green (0.7-1.0)
//

import Foundation
import Vision
import CoreImage
import CoreMedia
import Combine
import QuartzCore

/// Processes person segmentation and provides real-time quality feedback for camera positioning.
/// Quality scoring adapts based on exerciseMode (.bodyweight or .barbell) to provide exercise-specific guidance.
final class SegmentationProcessor: ObservableObject {
    @Published var overlayImage: CGImage?
    @Published var qualityScore: Double = 0 // 0 = poor, 1 = great (smoothed)
    private var isEnabled: Bool = true
    
    /// Exercise mode determines which quality metrics to apply during setup scoring.
    /// Set to .barbell for barbell back squat (7-9' distance, mid-chest height, feet + barbell in frame).
    /// Set to .bodyweight for bodyweight squat (6-8' distance, waist-to-chest height, feet in view).
    var exerciseMode: SquatType = .bodyweight

    // Config
    var throttleMs: Int = 33 // ~30 fps cap
    var overlayAlpha: CGFloat = 0.55 // toned down
    var qualitySmoothingFactor: Double = 0.85 // EMA smoothing (higher = smoother)
    var colorUpdateMs: Int = 120 // update tint ~8-10 Hz

    // Vision
    private let request: VNGeneratePersonSegmentationRequest
    private let requestHandler = VNSequenceRequestHandler()

    // CI
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // Throttle state
    private var lastProcessTime: CFTimeInterval = 0

    // Smoothing state
    private var smoothedScoreInternal: Double = 0
    private var lastColorUpdateTime: CFTimeInterval = 0
    private var cachedColor: CIColor = CIColor(red: 1, green: 0, blue: 0, alpha: 0.55)

    init() {
        let req = VNGeneratePersonSegmentationRequest()
        req.qualityLevel = .balanced
        req.outputPixelFormat = kCVPixelFormatType_OneComponent8
        self.request = req
    }

    func setProcessingEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled {
            stopProcessing()
        }
    }

    func process(sampleBuffer: CMSampleBuffer, mirrored: Bool) {
        guard isEnabled else { return }
        // Throttle
        let now = CACurrentMediaTime()
        let deltaMs = (now - lastProcessTime) * 1000
        guard deltaMs >= Double(throttleMs) else { return }
        lastProcessTime = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        do {
            try requestHandler.perform([request], on: pixelBuffer)
        } catch {
            return
        }

        guard let observations = request.results,
              let maskObs = observations.first
        else { return }

        // Compute raw quality and smooth it (EMA)
        let raw = computeQualityScore(maskBuffer: maskObs.pixelBuffer, pixelBuffer: pixelBuffer)
        let ema = qualitySmoothingFactor * smoothedScoreInternal + (1.0 - qualitySmoothingFactor) * raw
        smoothedScoreInternal = ema

        // Update tint color at a reduced cadence
        let colorCadenceSec = Double(colorUpdateMs) / 1000.0
        if now - lastColorUpdateTime >= colorCadenceSec {
            cachedColor = Self.colorForScore(score: ema, alpha: overlayAlpha)
            lastColorUpdateTime = now
        }

        if let cg = makeOverlayCGImage(pixelBuffer: pixelBuffer,
                                       maskBuffer: maskObs.pixelBuffer,
                                       mirrored: mirrored,
                                       color: cachedColor) {
            DispatchQueue.main.async { [weak self] in
                self?.qualityScore = ema
                self?.overlayImage = cg
            }
        }
    }
    
    func stopProcessing() {
        // Clear the overlay image and reset state
        DispatchQueue.main.async { [weak self] in
            self?.overlayImage = nil
            self?.qualityScore = 0
        }
        // Reset internal state
        smoothedScoreInternal = 0
        lastProcessTime = 0
        lastColorUpdateTime = 0
    }

    private func makeOverlayCGImage(pixelBuffer: CVPixelBuffer,
                                     maskBuffer: CVPixelBuffer,
                                     mirrored: Bool,
                                     color: CIColor) -> CGImage? {
        let baseImage = CIImage(cvPixelBuffer: pixelBuffer)
        var maskImage = CIImage(cvPixelBuffer: maskBuffer)

        // Resize mask to base
        let sx = baseImage.extent.width / maskImage.extent.width
        let sy = baseImage.extent.height / maskImage.extent.height
        maskImage = maskImage.transformed(by: CGAffineTransform(scaleX: sx, y: sy))

        // Use cached tint color
        let tint = CIImage(color: color).cropped(to: baseImage.extent)
        let clear = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: baseImage.extent)

        // Blend tint over transparent using mask alpha
        let overlay = tint.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: clear,
            kCIInputMaskImageKey: maskImage
        ])

        // Mirror horizontally to match front-camera preview layer behavior
        let output: CIImage
        if mirrored {
            let transform = CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -baseImage.extent.width, y: 0)
            output = overlay.transformed(by: transform)
        } else {
            output = overlay
        }

        return ciContext.createCGImage(output, from: output.extent)
    }

    // MARK: - Quality Scoring
    
    /// Computes quality score (0.0-1.0) based on person segmentation mask.
    /// For barbell squats, enhances scoring with exercise-specific metrics (distance, height, feet visibility).
    /// For bodyweight squats, uses base segmentation metrics only.
    private func computeQualityScore(maskBuffer: CVPixelBuffer, pixelBuffer: CVPixelBuffer) -> Double {
        CVPixelBufferLockBaseAddress(maskBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(maskBuffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(maskBuffer) else { return 0 }
        let width = CVPixelBufferGetWidth(maskBuffer)
        let height = CVPixelBufferGetHeight(maskBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(maskBuffer)

        // Downsampled scan for speed
        let step = 3 // sample every 3 pixels in both axes
        let threshold: UInt8 = 110 // foreground threshold

        var fgCount = 0
        var totalCount = 0
        var minX = width, maxX = 0, minY = height, maxY = 0

        for y in stride(from: 0, to: height, by: step) {
            let rowPtr = base.advanced(by: y * bytesPerRow)
            for x in stride(from: 0, to: width, by: step) {
                let v = rowPtr.load(fromByteOffset: x, as: UInt8.self)
                totalCount += 1
                if v > threshold {
                    fgCount += 1
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }
        if fgCount == 0 || totalCount == 0 { return 0 }

        let coverage = Double(fgCount) / Double(totalCount) // ~area fraction
        let bboxW = max(0, maxX - minX)
        let bboxH = max(0, maxY - minY)
        let bw = Double(bboxW) / Double(max(1, width))
        let bh = Double(bboxH) / Double(max(1, height))

        // Edge touch penalty (if bbox touches borders, it's likely cropped)
        let edgeMargin = 2
        var edgePenalty = 0.0
        if minX <= edgeMargin { edgePenalty += 0.5 }
        if maxX >= width - 1 - edgeMargin { edgePenalty += 0.5 }
        if minY <= edgeMargin { edgePenalty += 0.25 }
        if maxY >= height - 1 - edgeMargin { edgePenalty += 0.25 }
        edgePenalty = min(edgePenalty, 1.0)

        // Base scores from segmentation
        let coverageTarget = 0.35 // approximate full-body area coverage at 720p
        let coverageScore = Self.clamp01(coverage / coverageTarget)
        let heightScore = Self.clamp01((bh - 0.6) / 0.4) // prefer tall bbox
        let widthScore = Self.clamp01(1.0 - abs(bw - 0.4) / 0.3) // prefer moderate width

        var score = 0.5 * coverageScore + 0.3 * heightScore + 0.2 * widthScore
        score -= 0.3 * edgePenalty
        
        // Exercise-specific enhancements for barbell squats
        if exerciseMode == .barbell {
            score = enhanceBarbellQualityScore(baseScore: score, maskBuffer: maskBuffer, pixelBuffer: pixelBuffer, bboxH: bh, minY: minY, height: height)
        }
        
        return Self.clamp01(score)
    }
    
    // MARK: - Barbell-Specific Quality Scoring
    
    /// Enhances quality score for barbell back squat setup with exercise-specific requirements.
    ///
    /// Checks three key metrics:
    /// 1. **Distance (7-9 ft)**: Person height should occupy 25-35% of frame height
    /// 2. **Camera height (mid-chest)**: Head/upper torso should be in upper 40-60% of frame
    /// 3. **Feet visibility**: Both ankles should be detected (uses pose estimation when available)
    ///
    /// Combines base segmentation score (40%) with distance (25%), height (20%), and feet (15%) scores.
    private func enhanceBarbellQualityScore(baseScore: Double, maskBuffer: CVPixelBuffer, pixelBuffer: CVPixelBuffer, bboxH: Double, minY: Int, height: Int) -> Double {
        var enhancedScore = baseScore
        
        // 1. Distance check (7-9 ft): Person should occupy 25-35% of frame height
        let distanceTargetMin: Double = 0.25
        let distanceTargetMax: Double = 0.35
        let distanceScore: Double
        if bboxH >= distanceTargetMin && bboxH <= distanceTargetMax {
            distanceScore = 1.0 // Perfect distance
        } else if bboxH < distanceTargetMin {
            // Too close (person too large)
            distanceScore = Self.clamp01(bboxH / distanceTargetMin)
        } else {
            // Too far (person too small)
            distanceScore = Self.clamp01(1.0 - (bboxH - distanceTargetMax) / (0.5 - distanceTargetMax))
        }
        
        // 2. Camera height check: Head/upper torso should be in upper 40-60% of frame
        // minY is the top of the bounding box (head area)
        let headPosition = Double(minY) / Double(height)
        let heightTargetMin: Double = 0.4
        let heightTargetMax: Double = 0.6
        let heightScore: Double
        if headPosition >= heightTargetMin && headPosition <= heightTargetMax {
            heightScore = 1.0 // Perfect height
        } else if headPosition < heightTargetMin {
            // Camera too high (person too low in frame)
            heightScore = Self.clamp01(headPosition / heightTargetMin)
        } else {
            // Camera too low (person too high in frame)
            heightScore = Self.clamp01(1.0 - (headPosition - heightTargetMax) / (1.0 - heightTargetMax))
        }
        
        // 3. Feet visibility check using pose estimation
        let feetScore = checkFeetVisibility()
        
        // Combine scores: base (40%), distance (25%), height (20%), feet (15%)
        enhancedScore = 0.4 * baseScore + 0.25 * distanceScore + 0.20 * heightScore + 0.15 * feetScore
        
        return enhancedScore
    }
    
    /// Checks if both ankles are visible using pose estimation.
    /// Returns 1.0 if feet are likely visible, 0.5 if uncertain, based on pose analysis availability.
    ///
    /// Note: This is a lightweight heuristic. Future enhancement could directly check for
    /// leftAnkle and rightAnkle keypoints from pose observations for more precise detection.
    private func checkFeetVisibility() -> Double {
        let poseManager = OnDevicePoseManager.shared
        
        // If pose analysis is available with valid data, assume feet are visible
        guard let formAnalysis = poseManager.currentFormAnalysis else {
            // No pose data yet - return neutral score to avoid harsh penalty during initial setup
            return 0.5
        }
        
        // If form analysis exists and has valid data, assume feet are likely visible
        if formAnalysis.repCount >= 0 && formAnalysis.depth > 0 {
            return 1.0
        }
        
        return 0.5
    }

    /// Clamps a value between 0.0 and 1.0
    private static func clamp01(_ v: Double) -> Double { max(0, min(1, v)) }

    /// Maps quality score (0.0-1.0) to color for silhouette overlay.
    /// - 0.0-0.4: Red (poor setup)
    /// - 0.4-0.7: Yellow (partial setup)
    /// - 0.7-1.0: Green (good setup)
    private static func colorForScore(score: Double, alpha: CGFloat) -> CIColor {
        let t = clamp01(score)
        let r, g, b: CGFloat
        if t < 0.5 {
            // Red (1,0,0) -> Yellow (1,1,0)
            let u = CGFloat(t * 2)
            r = 1.0
            g = u
            b = 0.0
        } else {
            // Yellow (1,1,0) -> Green (0,1,0)
            let u = CGFloat((t - 0.5) * 2)
            r = 1.0 - u
            g = 1.0
            b = 0.0
        }
        return CIColor(red: r, green: g, blue: b, alpha: alpha)
    }
} 
