import Foundation
import AVFoundation
import UIKit

class VideoRecordingManager: NSObject, ObservableObject {
    static let shared = VideoRecordingManager()
    
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var recordingError: String?
    
    private var videoOutput: AVCaptureMovieFileOutput?
    private var recordingStartTime: Date?
    private var recordingTimer: Timer?
    private var currentVideoURL: URL?
    
    private override init() {
        super.init()
        // Consumers can call attach(videoOutput:) later to provide a session-attached output
        self.videoOutput = nil
    }
    
    // Allow the capture pipeline to provide its AVCaptureMovieFileOutput if available
    func attach(videoOutput: AVCaptureMovieFileOutput?) {
        self.videoOutput = videoOutput
    }
    
    func startRecording(workoutId: String) {
        print("🎥 Starting video recording for workout: \(workoutId)")
        
        guard let videoOutput = videoOutput else {
            recordingError = "No camera video output available"
            print("❌ Video recording failed: No video output attached")
            return
        }
        
        guard !videoOutput.isRecording else {
            recordingError = "Already recording"
            print("❌ Video recording failed: Already recording")
            return
        }
        
        // Create unique filename for this workout
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let videoFileName = "workout_\(workoutId)_\(Date().timeIntervalSince1970).mp4"
        let videoURL = documentsPath.appendingPathComponent(videoFileName)
        
        print("📁 Video will be saved to: \(videoURL.path)")
        
        // Start recording using the provided capture output
        videoOutput.startRecording(to: videoURL, recordingDelegate: self)
        
        isRecording = true
        recordingStartTime = Date()
        currentVideoURL = videoURL
        recordingError = nil
        
        print("✅ Video recording started successfully")
        
        // Start timer to track duration
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.recordingDuration = Date().timeIntervalSince(self?.recordingStartTime ?? Date())
            }
        }
    }
    
    func stopRecording() {
        print("🛑 Stopping video recording")
        
        guard let videoOutput = videoOutput, videoOutput.isRecording else {
            recordingError = "Not currently recording"
            print("❌ Video recording stop failed: Not currently recording")
            return
        }
        
        videoOutput.stopRecording()
        isRecording = false
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        print("✅ Video recording stopped successfully")
    }
    
    func getCurrentVideoURL() -> URL? {
        return currentVideoURL
    }
    
    func clearRecording() {
        if let videoURL = currentVideoURL {
            try? FileManager.default.removeItem(at: videoURL)
        }
        currentVideoURL = nil
        recordingDuration = 0
        recordingStartTime = nil
    }
    
    func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate
extension VideoRecordingManager: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        print("🎬 VideoRecordingManager: Recording started to \(fileURL.path)")
        DispatchQueue.main.async { self.recordingError = nil }
    }
    
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        print("🎬 VideoRecordingManager: Recording finished to \(outputFileURL.path)")
        
        DispatchQueue.main.async {
            if let error = error {
                print("❌ VideoRecordingManager: Recording failed with error: \(error.localizedDescription)")
                self.recordingError = "Recording failed: \(error.localizedDescription)"
            } else {
                print("✅ VideoRecordingManager: Recording completed successfully")
                self.currentVideoURL = outputFileURL
                let fileExists = FileManager.default.fileExists(atPath: outputFileURL.path)
                print("📁 Video file exists: \(fileExists)")
                if fileExists {
                    let fileSize = try? FileManager.default.attributesOfItem(atPath: outputFileURL.path)[.size] as? Int64
                    print("📊 Video file size: \(fileSize ?? 0) bytes")
                }
            }
        }
    }
} 