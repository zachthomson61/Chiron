//
//  AudioSessionManager.swift
//  Chiron
//
//  Configures the app's audio session to allow background audio (e.g., Spotify)
//  to continue playing when navigating through the app, especially when video
//  players in exercise overview views are active.
//

import AVFoundation

/// Manages app-wide audio session configuration.
///
/// Configures the audio session with `.mixWithOthers` option at app startup,
/// ensuring that background audio from other apps (like Spotify) continues
/// playing when the app's video players or other audio components become active.
///
/// This prevents audio interruption when users navigate to exercise overview
/// views that contain looping video demonstrations.
class AudioSessionManager {
    static let shared = AudioSessionManager()
    
    private init() {
        configureAudioSession()
    }
    
    /// Configures the audio session to allow mixing with other audio sources.
    ///
    /// Uses `.playback` category with `.mixWithOthers` option, which allows
    /// background audio to continue playing alongside the app's audio/video content.
    /// This is essential for muted video players that would otherwise interrupt
    /// background music.
    ///
    /// Mode is `.voicePrompt`, which signals to iOS that our audio is a voice prompt
    /// and triggers significantly more aggressive ducking of other audio (e.g. Spotify)
    /// than the default ducking level. This lets coaching feedback cut through music.
    private func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(
                .playback,
                mode: .voicePrompt,
                options: [.mixWithOthers]
            )
            try audioSession.setActive(true)
        } catch {
            // Audio session configuration failure is non-fatal
            // The app will continue to function, but background audio may be interrupted
        }
    }
}

