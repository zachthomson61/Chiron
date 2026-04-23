//
//  PRCelebrationCenter.swift
//  Chiron
//
//  Global publisher for personal-record celebrations. Views observe
//  `isShowingConfetti` on the shared instance; the confetti overlay is
//  mounted once at app root so every workout flow (Track tab, predetermined
//  workouts, etc.) fires into the same surface.
//
//  Audio is split from the visual side: the Track-tab coaching pipeline
//  weaves the celebration into the set-end spoken line when `isPR` is set,
//  so calling `celebrate(info:)` there passes `speak: false`. Flows that
//  don't route through the coaching manager (predetermined workouts) pass
//  `speak: true` to have the center speak the celebration directly.
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

    /// Trigger a celebration. Visual burst is always fired; spoken line is
    /// only delivered when `speak` is true (use false when the coaching
    /// manager will voice the PR itself, to avoid overlapping speech).
    ///
    /// - Parameters:
    ///   - info: PR details used to phrase the spoken line.
    ///   - speak: whether this center should also voice a celebration.
    func celebrate(info: PersonalRecord.Info, speak: Bool) {
        isShowingConfetti = true
        guard speak else { return }
        SpeechManager.shared.speak(
            Self.spokenLine(for: info),
            priority: .high,
            context: .encouragement
        )
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
