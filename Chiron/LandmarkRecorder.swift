//
//  LandmarkRecorder.swift
//  Chiron
//
//  Optional recording of pose landmark streams to JSON. When recording is on,
//  each frame is appended with timestampMs, normalised landmarks, world landmarks,
//  and per-joint confidence. One file per session in Documents/LandmarkRecordings.
//  Toggle from Settings → Developer → Pose Metrics.
//

import Foundation
import CoreGraphics

final class LandmarkRecorder: ObservableObject {

    @Published private(set) var isRecording = false
    @Published private(set) var frameCount = 0
    @Published private(set) var lastSavedURL: URL?

    private var frames: [[String: Any]] = []
    private let queue = DispatchQueue(label: "landmark.recorder", qos: .utility)

    func startRecording() {
        queue.async {
            self.frames.removeAll()
            DispatchQueue.main.async {
                self.isRecording = true
                self.frameCount = 0
            }
        }
    }

    func stopRecording() {
        queue.async {
            DispatchQueue.main.async { self.isRecording = false }
            self.writeToDisk()
        }
    }

    func record(
        timestampMs: Int,
        overlayLandmarks: [String: CGPoint],
        skeleton: Skeleton3D,
        confidence: [String: Float]
    ) {
        guard isRecording else { return }

        let landmarkDict = Dictionary(uniqueKeysWithValues: overlayLandmarks.map { ($0.key, ["x": $0.value.x, "y": $0.value.y]) })
        let worldDict = Dictionary(uniqueKeysWithValues: skeleton.joints.map { ($0.key, ["x": $0.value.position.x, "y": $0.value.position.y, "z": $0.value.position.z]) })
        let entry: [String: Any] = [
            "timestampMs": timestampMs,
            "landmarks": landmarkDict,
            "worldLandmarks": worldDict,
            "confidence": confidence
        ]

        queue.async {
            self.frames.append(entry)
            DispatchQueue.main.async { self.frameCount = self.frames.count }
        }
    }

    private func writeToDisk() {
        guard !frames.isEmpty else { return }
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("LandmarkRecordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let fileURL = dir.appendingPathComponent("landmarks_\(formatter.string(from: Date())).json")

        do {
            let data = try JSONSerialization.data(withJSONObject: frames, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: fileURL)
            DispatchQueue.main.async { self.lastSavedURL = fileURL }
        } catch {
            // Silent; lastSavedURL remains nil
        }
    }
}
