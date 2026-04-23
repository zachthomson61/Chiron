//
//  PersonalRecord.swift
//  Chiron
//
//  Detects when a just-completed set is a personal record against prior
//  history. Mirrors the PR rule used by ExerciseHistorySheet:
//    - Bodyweight: most reps in a single set.
//    - Weighted:   heaviest weight logged; ties broken by highest reps at
//                  that weight.
//
//  The first-ever set of an exercise is NOT treated as a PR. A "record"
//  implies something to beat; celebrating a movement the user has never
//  logged before is noise, not a signal.
//

import Foundation

enum PersonalRecord {

    /// Description of a PR event for phrasing celebrations. `weight` is nil
    /// for bodyweight movements; `reps` is always present and positive.
    struct Info: Equatable {
        let weight: Double?
        let reps: Int
        let isBodyweight: Bool

        /// Spoken descriptor used by the coach — e.g. "185 for 8" for a
        /// weighted PR, or "25 reps" for a bodyweight PR.
        var spokenDescriptor: String {
            if isBodyweight {
                return "\(reps) reps"
            }
            let weightStr: String
            if let w = weight {
                weightStr = (w == floor(w))
                    ? String(Int(w))
                    : String(format: "%.1f", w)
            } else {
                weightStr = "bodyweight"
            }
            return "\(weightStr) for \(reps)"
        }
    }

    /// Returns a populated `Info` when (weight, reps) strictly beats every
    /// prior set for this exercise in `history`. Returns nil when:
    ///   - there is no prior history (first-ever set — not a PR moment),
    ///   - reps is nil or zero (no set actually performed),
    ///   - a prior set equals or exceeds the candidate.
    ///
    /// `history` may contain logs for other exercises; this routine filters
    /// to `exerciseName` itself.
    static func check(
        exerciseName: String,
        isBodyweight: Bool,
        weight: Double?,
        reps: Int?,
        history: [ExerciseSetLog]
    ) -> Info? {
        guard let reps, reps > 0 else { return nil }

        let priorForExercise = history.filter {
            $0.exerciseName == exerciseName && ($0.reps ?? 0) > 0
        }
        // First-ever set of an exercise isn't a PR — there's nothing to beat.
        guard !priorForExercise.isEmpty else { return nil }

        if isBodyweight {
            let priorMaxReps = priorForExercise
                .compactMap { $0.reps }
                .max() ?? 0
            guard reps > priorMaxReps else { return nil }
            return Info(weight: nil, reps: reps, isBodyweight: true)
        }

        // Weighted: require a positive weight on the candidate to compare.
        guard let newWeight = weight, newWeight > 0 else { return nil }

        let priorWeighted = priorForExercise.filter { ($0.weight ?? 0) > 0 }
        // All prior sets were weight-less junk — nothing valid to beat.
        guard !priorWeighted.isEmpty else { return nil }

        let priorMaxWeight = priorWeighted.compactMap { $0.weight }.max() ?? 0

        if newWeight > priorMaxWeight {
            return Info(weight: newWeight, reps: reps, isBodyweight: false)
        }
        if newWeight == priorMaxWeight {
            let priorRepsAtMax = priorWeighted
                .filter { $0.weight == priorMaxWeight }
                .compactMap { $0.reps }
                .max() ?? 0
            if reps > priorRepsAtMax {
                return Info(weight: newWeight, reps: reps, isBodyweight: false)
            }
        }
        return nil
    }
}
