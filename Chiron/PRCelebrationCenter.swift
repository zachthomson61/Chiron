//
//  PRCelebrationCenter.swift
//  Chiron
//
//  Global publisher for personal-record celebrations. Views observe
//  `isShowingConfetti` on the shared instance; the confetti overlay is
//  mounted once at app root so every workout flow (Track tab, predetermined
//  workouts, etc.) fires into the same surface.
//
//  Confetti drop is synced to the spoken announcement: callers either fire
//  `fireConfetti()` from a `SpeechManager.speak` `onStart` callback (Track tab,
//  where the LLM weaves the PR into its set-end line), or use
//  `celebrateWithSpeech(info:)` (predetermined workouts) which speaks the
//  literal celebration line and drops confetti when the audio actually starts.
//

import Foundation
import Combine

@MainActor
final class PRCelebrationCenter: ObservableObject {
    static let shared = PRCelebrationCenter()

    /// Flipped to true when a PR celebration fires. `ConfettiView` resets it
    /// to false once the burst finishes so the overlay can release.
    @Published var isShowingConfetti: Bool = false

    private init() {}

    /// Drop the confetti now. Call this from a `SpeechManager.speak` `onStart`
    /// closure so the visual lands together with the audio announcement.
    func fireConfetti() {
        isShowingConfetti = true
    }

    /// Speak the celebration line and drop confetti when the audio actually starts.
    /// Use from flows that don't already deliver a set-end coaching line (e.g. predetermined
    /// workouts) — the Track tab uses `fireConfetti()` from inside its LLM speech `onStart` instead.
    ///
    /// A 5s safety fallback drops the confetti even if speech never fires (disabled / failed).
    func celebrateWithSpeech(info: PersonalRecord.Info) {
        var fired = false
        let fireOnce: () -> Void = { [weak self] in
            guard let self, !fired else { return }
            fired = true
            self.isShowingConfetti = true
        }
        SpeechManager.shared.speak(
            Self.spokenLine(for: info),
            priority: .high,
            context: .encouragement,
            onStart: fireOnce
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { fireOnce() }
    }

    /// Deterministic celebration phrasing. Kept literal — no similes, matches
    /// the project's "no similes in spoken cues" rule.
    static func spokenLine(for info: PersonalRecord.Info) -> String {
        if info.isBodyweight {
            return "Personal record — \(info.reps) reps. Huge work."
        }
        return "Personal record — \(info.spokenDescriptor). Huge work."
    }
}
