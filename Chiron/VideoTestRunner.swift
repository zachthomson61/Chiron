//
//  VideoTestRunner.swift
//  Chiron
//
//  Runs MediaPipe pose detection in video mode over bundled test clips
//  (test_squat, test_deadlift, test_bench, test_row). Records per-frame
//  landmarks to JSON and aggregates latency/jitter for validation.
//

import Foundation
import AVFoundation
import CoreGraphics
import MediaPipeTasksVision

final class VideoTestRunner: ObservableObject {

    // MARK: - Published State

    @Published private(set) var isRunning = false
    @Published private(set) var currentVideo: String = ""
    @Published private(set) var progress: Double = 0
    @Published private(set) var results: [VideoTestResult] = []

    /// Result of processing one test video. repCount is always 0 (no rep logic in video mode).
    struct VideoTestResult: Identifiable {
        let id = UUID()
        let videoName: String
        let totalFrames: Int
        let framesWithPose: Int
        let repCount: Int
        let avgLatencyMs: Double
        let avgJitter: Double
        let landmarkFileURL: URL?
    }

    // MARK: - Test Videos

    static let testVideos = [
        "test_squat",
        "test_deadlift",
        "test_bench",
        "test_row",
    ]

    // MARK: - Run

    func runAll() {
        guard !isRunning else { return }
        isRunning = true
        results = []

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            for name in VideoTestRunner.testVideos {
                DispatchQueue.main.async { self?.currentVideo = name }
                if let result = self?.processVideo(name: name) {
                    DispatchQueue.main.async { self?.results.append(result) }
                }
            }
            DispatchQueue.main.async {
                self?.isRunning = false
                self?.currentVideo = ""
            }
        }
    }

    // MARK: - Process One Video

    private func processVideo(name: String) -> VideoTestResult? {
        guard let path = Bundle.main.path(forResource: name, ofType: "mp4") else {
            return VideoTestResult(
                videoName: name, totalFrames: 0, framesWithPose: 0,
                repCount: 0, avgLatencyMs: 0, avgJitter: 0, landmarkFileURL: nil
            )
        }

        let url = URL(fileURLWithPath: path)
        let asset = AVAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else { return nil }

        let modelPath = Bundle.main.path(forResource: "pose_landmarker_full", ofType: "task")!
        let options = PoseLandmarkerOptions()
        options.baseOptions.modelAssetPath = modelPath
        options.runningMode = .video
        options.numPoses = 1
        options.minPoseDetectionConfidence = 0.5
        options.minPosePresenceConfidence = 0.5
        options.minTrackingConfidence = 0.5

        guard let landmarker = try? PoseLandmarker(options: options) else { return nil }

        let adapter = MediaPipePoseAdapter()
        let smoother = JointSmoother(alpha: 0.2, twoStage: true)
        let overlaySmoother = Landmark2DSmoother()

        let reader: AVAssetReader
        do { reader = try AVAssetReader(asset: asset) } catch { return nil }

        let outputSettings: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        let trackOutput = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        reader.add(trackOutput)
        reader.startReading()

        let fps = track.nominalFrameRate
        let duration = CMTimeGetSeconds(asset.duration)
        let estimatedFrames = max(1, Int(fps * Float(duration)))

        var totalFrames = 0
        var framesWithPose = 0
        var latencies: [Double] = []
        var jitterWindow: [[String: CGPoint]] = []
        var jitterSamples: [Double] = []
        var landmarkFrames: [[String: Any]] = []
        var timestampMs: Int = 0
        let frameDurationMs = Int(1000.0 / max(1, fps))

        while let sampleBuffer = trackOutput.copyNextSampleBuffer(),
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            totalFrames += 1
            timestampMs += frameDurationMs
            DispatchQueue.main.async { self.progress = Double(totalFrames) / Double(estimatedFrames) }

            let start = CACurrentMediaTime()
            guard let mpImage = try? MPImage(pixelBuffer: pixelBuffer),
                  let result = try? landmarker.detect(videoFrame: mpImage, timestampInMilliseconds: timestampMs) else {
                continue
            }
            let latency = (CACurrentMediaTime() - start) * 1000
            latencies.append(latency)

            guard let adapted = adapter.adapt(result, timestampMs: timestampMs) else { continue }
            framesWithPose += 1

            let smoothedSkeleton = smoother.smooth(adapted.skeleton)
            let smoothedOverlay = overlaySmoother.smooth(adapted.overlayLandmarks)

            // Jitter
            jitterWindow.append(smoothedOverlay)
            if jitterWindow.count > 30 { jitterWindow.removeFirst() }
            if jitterWindow.count >= 2 {
                let allKeys = Set(jitterWindow.flatMap { $0.keys })
                var sum = 0.0
                var cnt = 0
                for key in allKeys {
                    let pts = jitterWindow.compactMap { $0[key] }
                    guard pts.count >= 2 else { continue }
                    let mx = pts.map(\.x).reduce(0, +) / CGFloat(pts.count)
                    let my = pts.map(\.y).reduce(0, +) / CGFloat(pts.count)
                    let v = pts.reduce(0.0) { $0 + Double(($1.x - mx) * ($1.x - mx) + ($1.y - my) * ($1.y - my)) } / Double(pts.count)
                    sum += v; cnt += 1
                }
                jitterSamples.append(cnt > 0 ? sum / Double(cnt) : 0)
            }

            // Record landmarks
            var lmDict: [String: [String: CGFloat]] = [:]
            for (k, p) in adapted.overlayLandmarks { lmDict[k] = ["x": p.x, "y": p.y] }
            var wDict: [String: [String: Float]] = [:]
            for (k, j) in smoothedSkeleton.joints { wDict[k] = ["x": j.position.x, "y": j.position.y, "z": j.position.z] }
            landmarkFrames.append([
                "timestampMs": timestampMs,
                "landmarks": lmDict,
                "worldLandmarks": wDict,
                "confidence": adapted.perJointConfidence
            ])
        }
        reader.cancelReading()

        // Save landmarks JSON
        let fileURL = saveLandmarks(landmarkFrames, videoName: name)

        let avgLatency = latencies.isEmpty ? 0 : latencies.reduce(0, +) / Double(latencies.count)
        let avgJitter = jitterSamples.isEmpty ? 0 : jitterSamples.reduce(0, +) / Double(jitterSamples.count)

        return VideoTestResult(
            videoName: name,
            totalFrames: totalFrames,
            framesWithPose: framesWithPose,
            repCount: 0,
            avgLatencyMs: avgLatency,
            avgJitter: avgJitter,
            landmarkFileURL: fileURL
        )
    }

    private func saveLandmarks(_ frames: [[String: Any]], videoName: String) -> URL? {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("TestResults", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let file = "\(videoName)_\(formatter.string(from: Date())).json"
        let url = dir.appendingPathComponent(file)

        guard let data = try? JSONSerialization.data(withJSONObject: frames, options: [.prettyPrinted]) else { return nil }
        try? data.write(to: url)
        return url
    }
}
