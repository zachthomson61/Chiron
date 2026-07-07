//
//  TempoCueAudio.swift
//  Chiron
//
//  Non-verbal audio for the intra-set tempo layer (Phase 3b). One sound: the bottom-stretch
//  "release" tone that tells the lifter they've held the deepest loaded position long enough
//  (`TempoCoachingConfig.minPauseMs`) and can drive up.
//
//  Uses `AudioServicesPlaySystemSound` — zero assets, minimal latency, already linked via
//  AudioToolbox. Playback is fire-and-forget and mixes over any active speech without
//  interrupting it. A custom tone via `AVAudioPlayer` is a drop-in upgrade later: keep the
//  `playRelease()` call site and swap the implementation.
//
//  Call from the main queue (the pose manager dispatches off the analysis queue per the
//  tempo layer's thread model), although the underlying C API is thread-safe.
//

import AudioToolbox

enum TempoCueAudio {

    /// System sound 1057 ("Tink"): a single short, percussive tick — clearly distinguishable
    /// from speech and from the app's other feedback sounds, and long-press-proof (≈0.1 s).
    private static let releaseSoundID: SystemSoundID = 1057

    /// Plays the bottom-stretch release tone once. The caller owns the once-per-rep latch.
    static func playRelease() {
        AudioServicesPlaySystemSound(releaseSoundID)
    }
}
