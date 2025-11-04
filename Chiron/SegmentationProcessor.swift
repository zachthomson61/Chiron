import Foundation
import Vision
import CoreImage
import CoreMedia
import Combine
import QuartzCore

final class SegmentationProcessor: ObservableObject {
    @Published var overlayImage: CGImage?
    @Published var qualityScore: Double = 0 // 0 = poor, 1 = great (smoothed)
    private var isEnabled: Bool = true

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
        let raw = Self.computeQualityScore(maskBuffer: maskObs.pixelBuffer)
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

    // MARK: - Quality Heuristic
    private static func computeQualityScore(maskBuffer: CVPixelBuffer) -> Double {
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

        // Scores
        let coverageTarget = 0.35 // approximate full-body area coverage at 720p
        let coverageScore = clamp01(coverage / coverageTarget)
        let heightScore = clamp01((bh - 0.6) / 0.4) // prefer tall bbox
        let widthScore = clamp01(1.0 - abs(bw - 0.4) / 0.3) // prefer moderate width

        var score = 0.5 * coverageScore + 0.3 * heightScore + 0.2 * widthScore
        score -= 0.3 * edgePenalty
        return clamp01(score)
    }

    private static func clamp01(_ v: Double) -> Double { max(0, min(1, v)) }

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
