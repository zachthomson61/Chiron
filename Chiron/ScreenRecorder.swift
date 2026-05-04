//
//  ScreenRecorder.swift
//  Chiron
//
//  Wraps ReplayKit so a set's full on-screen experience (camera preview + pose overlay
//  + rep counter + cues) is captured to an mp4 alongside the per-frame CSV. The combo
//  lets us replay any rep and inspect the signal trace at the same timestamp.
//
//  iOS prompts the user the first time recording is requested; subsequent starts within
//  the same app launch are silent. A red status-bar pill is always visible while
//  recording, so the user is never unaware that capture is active.
//

import Foundation
import ReplayKit

final class ScreenRecorder {
    static let shared = ScreenRecorder()
    private init() {}

    private let recorder = RPScreenRecorder.shared()

    var isRecording: Bool { recorder.isRecording }

    /// Begins screen recording. Calls completion with `nil` on success or an error otherwise.
    /// No-ops if a recording is already in flight.
    func start(completion: ((Error?) -> Void)? = nil) {
        guard recorder.isAvailable else {
            completion?(NSError(domain: "ScreenRecorder", code: -1,
                                userInfo: [NSLocalizedDescriptionKey: "Screen recording unavailable on this device"]))
            return
        }
        guard !recorder.isRecording else {
            completion?(nil)
            return
        }
        recorder.isMicrophoneEnabled = false
        recorder.isCameraEnabled = false
        recorder.startRecording { error in
            DispatchQueue.main.async { completion?(error) }
        }
    }

    /// Stops the active recording and writes the mp4 into the temp directory under the given
    /// basename (no extension). The completion receives the file URL (nil if nothing was
    /// recorded or finalization failed). Caller-supplied basename keeps the CSV and video
    /// filenames in sync.
    func stop(basename: String, completion: @escaping (URL?) -> Void) {
        guard recorder.isRecording else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(basename).mp4")
        try? FileManager.default.removeItem(at: url)
        recorder.stopRecording(withOutput: url) { error in
            DispatchQueue.main.async {
                completion(error == nil ? url : nil)
            }
        }
    }
}
