//
//  SegmentationProcessor.swift
//  Chiron
//
//  Processes person segmentation from camera frames and provides quality scoring for camera setup.
//  Supports exercise-specific quality metrics (bodyweight vs barbell squats, bench press) via exerciseMode property.
//
//  Architecture:
//  - Uses Vision framework's VNGeneratePersonSegmentationRequest for person detection
//  - Computes quality score based on person size, position, and visibility
//  - For barbell squats, enhances scoring with distance, height, and feet visibility checks
//  - For bench press, enhances scoring with view-specific metrics (RACK, FLOOR, TRIPOD)
//  - Maps quality score (0.0-1.0) to color: Red (0.0-0.4), Yellow (0.4-0.7), Green (0.7-1.0)
//
//  Test View Support:
//  - Supports portrait camera orientation with rotation parameter
//  - Overlay image is rotated 90° clockwise to match portrait preview display
//

import Foundation
import Vision
import CoreImage
import CoreMedia
import Combine
import QuartzCore

// MARK: - Bench Press View Type

/// Camera setup view type for bench press exercises.
/// Each view has different quality scoring criteria based on the camera placement.
enum BenchPressViewType {
    case rack       // Camera mounted high on rack, angled down
    case floor      // Camera on floor 4-6 ft in front, angled up
    case tripod     // Camera on tripod 2-3 ft in front, at bar level
}

/// Processes person segmentation and provides real-time quality feedback for camera positioning.
/// Quality scoring adapts based on exerciseMode (.bodyweight, .barbell, or .benchPress) to provide exercise-specific guidance.
final class SegmentationProcessor: ObservableObject {
    @Published var overlayImage: CGImage?
    @Published var qualityScore: Double = 0 // 0 = poor, 1 = great (smoothed)
    private var isEnabled: Bool = true
    
    /// Exercise mode determines which quality metrics to apply during setup scoring.
    /// - `.bodyweight`: Bodyweight squat (6-8' distance, waist-to-chest height, feet in view)
    /// - `.barbell`: Barbell back squat (7-9' distance, mid-chest height, feet + barbell in frame)
    /// - `.benchPress`: Close-grip bench press (view-specific scoring based on `benchPressViewType`)
    var exerciseMode: SquatType = .bodyweight
    
    /// Bench press view type determines which quality metrics to apply for bench press exercises.
    /// Only used when `exerciseMode == .benchPress`.
    /// - `.rack`: Camera mounted high on rack post, angled down
    /// - `.floor`: Camera on floor 4-6 ft in front, angled up
    /// - `.tripod`: Camera on tripod 2-3 ft in front, at bar level
    var benchPressViewType: BenchPressViewType = .tripod

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

    /// Processes a camera frame for person segmentation and quality scoring.
    ///
    /// - Parameters:
    ///   - sampleBuffer: The camera frame to process
    ///   - mirrored: Whether the image should be horizontally mirrored (for front camera)
    ///   - rotated: Whether the image should be rotated 90° clockwise (for portrait orientation)
    func process(sampleBuffer: CMSampleBuffer, mirrored: Bool, rotated: Bool = false) {
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
                                       rotated: rotated,
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
                                     rotated: Bool,
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
        var overlay = tint.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: clear,
            kCIInputMaskImageKey: maskImage
        ])

        // Mirror horizontally to match front-camera preview layer behavior
        if mirrored {
            let transform = CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -baseImage.extent.width, y: 0)
            overlay = overlay.transformed(by: transform)
        }
        
        // Rotate 90° clockwise to match portrait preview orientation
        // Camera buffers are typically landscape (w > h), but preview displays in portrait (h > w)
        if rotated {
            let width = overlay.extent.width
            let height = overlay.extent.height
            
            // Rotate around image center: translate to origin, rotate -90°, translate to new center
            let centerX = width / 2.0
            let centerY = height / 2.0
            let newCenterX = height / 2.0
            let newCenterY = width / 2.0
            
            var transform = CGAffineTransform.identity
            transform = transform.translatedBy(x: -centerX, y: -centerY)
            transform = transform.rotated(by: -CGFloat.pi / 2.0) // -90° = clockwise
            transform = transform.translatedBy(x: newCenterX, y: newCenterY)
            overlay = overlay.transformed(by: transform)
        }

        return ciContext.createCGImage(overlay, from: overlay.extent)
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
        
        // Exercise-specific enhancements
        switch exerciseMode {
        case .barbell:
            score = enhanceBarbellQualityScore(baseScore: score, maskBuffer: maskBuffer, pixelBuffer: pixelBuffer, bboxH: bh, minY: minY, height: height)
        case .benchPress:
            score = enhanceBenchPressQualityScore(baseScore: score, bboxW: bw, bboxH: bh, minX: minX, maxX: maxX, minY: minY, maxY: maxY, width: width, height: height)
        case .closeGripBenchPress:
            // Use same quality scoring as regular bench press
            score = enhanceBenchPressQualityScore(baseScore: score, bboxW: bw, bboxH: bh, minX: minX, maxX: maxX, minY: minY, maxY: maxY, width: width, height: height)
        case .bodyweight:
            break // Use base scoring
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
    
    // MARK: - Bench Press Quality Scoring
    
    /// Enhances quality score for bench press with view-specific requirements.
    /// Routes to the appropriate scoring method based on benchPressViewType.
    private func enhanceBenchPressQualityScore(baseScore: Double, bboxW: Double, bboxH: Double, minX: Int, maxX: Int, minY: Int, maxY: Int, width: Int, height: Int) -> Double {
        switch benchPressViewType {
        case .rack:
            return enhanceBenchPressRackScore(baseScore: baseScore, bboxW: bboxW, bboxH: bboxH, minX: minX, maxX: maxX, minY: minY, maxY: maxY, width: width, height: height)
        case .floor:
            return enhanceBenchPressFloorScore(baseScore: baseScore, bboxW: bboxW, bboxH: bboxH, minX: minX, maxX: maxX, minY: minY, maxY: maxY, width: width, height: height)
        case .tripod:
            return enhanceBenchPressTripodScore(baseScore: baseScore, bboxW: bboxW, bboxH: bboxH, minX: minX, maxX: maxX, minY: minY, maxY: maxY, width: width, height: height)
        }
    }
    
    /// Quality scoring for RACK view (camera mounted high on rack post, angled down).
    ///
    /// Scoring criteria:
    /// - Coverage (20%): Upper body occupies 20-30% of frame height
    /// - Position (30%): Upper torso in upper 50-70% of frame (camera looking down)
    /// - Centering (25%): Person horizontally centered (bar/hands centered)
    /// - Range visibility (25%): Full vertical range visible (no cropping at lockout or chest touch)
    private func enhanceBenchPressRackScore(baseScore: Double, bboxW: Double, bboxH: Double, minX: Int, maxX: Int, minY: Int, maxY: Int, width: Int, height: Int) -> Double {
        // Coverage score: Upper body should occupy 20-30% of frame height
        let coverageTargetMin: Double = 0.20
        let coverageTargetMax: Double = 0.30
        let coverageScore: Double
        if bboxH >= coverageTargetMin && bboxH <= coverageTargetMax {
            coverageScore = 1.0
        } else if bboxH < coverageTargetMin {
            coverageScore = Self.clamp01(bboxH / coverageTargetMin)
        } else {
            coverageScore = Self.clamp01(1.0 - (bboxH - coverageTargetMax) / (0.5 - coverageTargetMax))
        }
        
        // Position score: Upper torso should be in upper 50-70% of frame (camera looking down)
        let headPosition = Double(minY) / Double(height)
        let positionTargetMin: Double = 0.50
        let positionTargetMax: Double = 0.70
        let positionScore: Double
        if headPosition >= positionTargetMin && headPosition <= positionTargetMax {
            positionScore = 1.0
        } else if headPosition < positionTargetMin {
            positionScore = Self.clamp01(headPosition / positionTargetMin)
        } else {
            positionScore = Self.clamp01(1.0 - (headPosition - positionTargetMax) / (1.0 - positionTargetMax))
        }
        
        // Centering score: Person should be horizontally centered
        let centerX = Double(minX + maxX) / 2.0
        let normalizedCenterX = centerX / Double(width)
        let centeringScore = 1.0 - abs(normalizedCenterX - 0.5) * 2.0
        
        // Range visibility score: Check that bbox doesn't touch top/bottom edges (cropped)
        let edgeMargin = 5
        var rangeScore = 1.0
        if minY <= edgeMargin { rangeScore -= 0.4 } // Top cropped (lockout)
        if maxY >= height - 1 - edgeMargin { rangeScore -= 0.4 } // Bottom cropped (chest touch)
        rangeScore = Self.clamp01(rangeScore)
        
        // Combine scores: Coverage (20%), Position (30%), Centering (25%), Range (25%)
        return 0.20 * coverageScore + 0.30 * positionScore + 0.25 * Self.clamp01(centeringScore) + 0.25 * rangeScore
    }
    
    /// Quality scoring for FLOOR view (camera on floor 4-6 ft in front, angled up).
    ///
    /// Scoring criteria:
    /// - Distance (30%): Person occupies 15-25% of frame height (4-6 ft away)
    /// - Position (25%): Person in lower 60-80% of frame (camera on floor, angled up)
    /// - Centering (25%): Person horizontally centered (bar/hands centered)
    /// - Key parts visibility (20%): Hands, elbows, and bar path visible in frame
    private func enhanceBenchPressFloorScore(baseScore: Double, bboxW: Double, bboxH: Double, minX: Int, maxX: Int, minY: Int, maxY: Int, width: Int, height: Int) -> Double {
        // Distance score: Person should occupy 15-25% of frame height (4-6 ft away)
        let distanceTargetMin: Double = 0.15
        let distanceTargetMax: Double = 0.25
        let distanceScore: Double
        if bboxH >= distanceTargetMin && bboxH <= distanceTargetMax {
            distanceScore = 1.0
        } else if bboxH < distanceTargetMin {
            distanceScore = Self.clamp01(bboxH / distanceTargetMin)
        } else {
            distanceScore = Self.clamp01(1.0 - (bboxH - distanceTargetMax) / (0.5 - distanceTargetMax))
        }
        
        // Position score: Person should be in lower 60-80% of frame (camera on floor, angled up)
        let headPosition = Double(minY) / Double(height)
        let positionTargetMin: Double = 0.60
        let positionTargetMax: Double = 0.80
        let positionScore: Double
        if headPosition >= positionTargetMin && headPosition <= positionTargetMax {
            positionScore = 1.0
        } else if headPosition < positionTargetMin {
            // Too high in frame
            positionScore = Self.clamp01(headPosition / positionTargetMin)
        } else {
            // Too low in frame
            positionScore = Self.clamp01(1.0 - (headPosition - positionTargetMax) / (1.0 - positionTargetMax))
        }
        
        // Centering score: Person should be horizontally centered
        let centerX = Double(minX + maxX) / 2.0
        let normalizedCenterX = centerX / Double(width)
        let centeringScore = 1.0 - abs(normalizedCenterX - 0.5) * 2.0
        
        // Key parts visibility: Check that horizontal width is sufficient for arms
        // Wider bbox suggests arms are visible
        let widthTargetMin: Double = 0.30
        let widthTargetMax: Double = 0.50
        let keyPartsScore: Double
        if bboxW >= widthTargetMin && bboxW <= widthTargetMax {
            keyPartsScore = 1.0
        } else if bboxW < widthTargetMin {
            keyPartsScore = Self.clamp01(bboxW / widthTargetMin)
        } else {
            keyPartsScore = Self.clamp01(1.0 - (bboxW - widthTargetMax) / (0.7 - widthTargetMax))
        }
        
        // Combine scores: Distance (30%), Position (25%), Centering (25%), Key parts (20%)
        return 0.30 * distanceScore + 0.25 * positionScore + 0.25 * Self.clamp01(centeringScore) + 0.20 * keyPartsScore
    }
    
    /// Quality scoring for TRIPOD view (camera on tripod 2-3 ft in front, at bar level).
    ///
    /// Scoring criteria:
    /// - Distance (25%): Person occupies 30-45% of frame height (2-3 ft away, close)
    /// - Position (30%): Upper body centered vertically (40-60% from top, at bar level)
    /// - Centering (25%): Person horizontally centered
    /// - Key parts visibility (20%): Hands, elbows, and bar clearly visible
    private func enhanceBenchPressTripodScore(baseScore: Double, bboxW: Double, bboxH: Double, minX: Int, maxX: Int, minY: Int, maxY: Int, width: Int, height: Int) -> Double {
        // Distance score: Person should occupy 30-45% of frame height (2-3 ft away)
        let distanceTargetMin: Double = 0.30
        let distanceTargetMax: Double = 0.45
        let distanceScore: Double
        if bboxH >= distanceTargetMin && bboxH <= distanceTargetMax {
            distanceScore = 1.0
        } else if bboxH < distanceTargetMin {
            distanceScore = Self.clamp01(bboxH / distanceTargetMin)
        } else {
            distanceScore = Self.clamp01(1.0 - (bboxH - distanceTargetMax) / (0.7 - distanceTargetMax))
        }
        
        // Position score: Upper body centered vertically (40-60% from top)
        let headPosition = Double(minY) / Double(height)
        let positionTargetMin: Double = 0.40
        let positionTargetMax: Double = 0.60
        let positionScore: Double
        if headPosition >= positionTargetMin && headPosition <= positionTargetMax {
            positionScore = 1.0
        } else if headPosition < positionTargetMin {
            positionScore = Self.clamp01(headPosition / positionTargetMin)
        } else {
            positionScore = Self.clamp01(1.0 - (headPosition - positionTargetMax) / (1.0 - positionTargetMax))
        }
        
        // Centering score: Person should be horizontally centered
        let centerX = Double(minX + maxX) / 2.0
        let normalizedCenterX = centerX / Double(width)
        let centeringScore = 1.0 - abs(normalizedCenterX - 0.5) * 2.0
        
        // Key parts visibility: Check that bbox width is sufficient for arms and doesn't touch edges
        let widthTargetMin: Double = 0.35
        let widthTargetMax: Double = 0.55
        var keyPartsScore: Double
        if bboxW >= widthTargetMin && bboxW <= widthTargetMax {
            keyPartsScore = 1.0
        } else if bboxW < widthTargetMin {
            keyPartsScore = Self.clamp01(bboxW / widthTargetMin)
        } else {
            keyPartsScore = Self.clamp01(1.0 - (bboxW - widthTargetMax) / (0.8 - widthTargetMax))
        }
        
        // Penalize if arms are cropped horizontally
        let edgeMargin = 5
        if minX <= edgeMargin { keyPartsScore -= 0.3 }
        if maxX >= width - 1 - edgeMargin { keyPartsScore -= 0.3 }
        keyPartsScore = Self.clamp01(keyPartsScore)
        
        // Combine scores: Distance (25%), Position (30%), Centering (25%), Key parts (20%)
        return 0.25 * distanceScore + 0.30 * positionScore + 0.25 * Self.clamp01(centeringScore) + 0.20 * keyPartsScore
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
