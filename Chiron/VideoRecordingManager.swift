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
        
        guard let videoOutput = videoOutput else {
            recordingError = "No camera video output available"
            return
        }
        
        guard !videoOutput.isRecording else {
            recordingError = "Already recording"
            return
        }
        
        // Create unique filename for this workout
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let videoFileName = "workout_\(workoutId)_\(Date().timeIntervalSince1970).mp4"
        let videoURL = documentsPath.appendingPathComponent(videoFileName)
        
        
        // Start recording using the provided capture output
        videoOutput.startRecording(to: videoURL, recordingDelegate: self)
        
        isRecording = true
        recordingStartTime = Date()
        currentVideoURL = videoURL
        recordingError = nil
        
        
        // Start timer to track duration
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.recordingDuration = Date().timeIntervalSince(self?.recordingStartTime ?? Date())
            }
        }
    }
    
    func stopRecording() {
        
        guard let videoOutput = videoOutput, videoOutput.isRecording else {
            recordingError = "Not currently recording"
            return
        }
        
        videoOutput.stopRecording()
        isRecording = false
        recordingTimer?.invalidate()
        recordingTimer = nil
        
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
        DispatchQueue.main.async { self.recordingError = nil }
    }
    
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        
        DispatchQueue.main.async {
            if let error = error {
                self.recordingError = "Recording failed: \(error.localizedDescription)"
            } else {
                self.currentVideoURL = outputFileURL
            }
        }
    }
} 