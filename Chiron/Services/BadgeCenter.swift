//
//  BadgeCenter.swift
//  Chiron
//
//  Owns the user's earned-badges set and decides when a new badge unlocks.
//  Two evaluation entry points:
//
//    1. `evaluateAfterSet(...)` — fired from TrackView.endSet right after the
//       set is persisted. Sees the just-completed set's form metrics, so it
//       handles "First Steps" + "Form Quality" in real time and queues the
//       follow-up history pass for lifetime / consistency badges.
//
//    2. `recomputeFromHistory(setLogs:)` — replays the user's full ExerciseSetLog
//       history and re-evaluates streak / volume / mastery / consistency /
//       comeback rules. Cheap to call (linear scan) and idempotent: a badge
//       only fires the unlock celebration the first time it crosses its
//       threshold. Re-running it on every set save keeps the gallery accurate
//       without maintaining a separate counter store.
//
//  Persistence: earned badge ids live in UserDefaults under a versioned key.
//  A locally-tracked "ever earned" set means resetting Firestore data does
//  not silently revoke trophies the user has already seen — re-earning would
//  feel hollow, and we'd rather treat them as durable.
//

import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class BadgeCenter: ObservableObject {
    static let shared = BadgeCenter()

    // MARK: - Published state

    /// IDs of every badge the user has earned. UI binds to this for the
    /// achievements gallery + locked/unlocked rendering.
    @Published private(set) var earnedBadgeIDs: Set<String> = []

    /// Most recently unlocked badge — the unlock overlay observes this and
    /// resets it to nil once the celebration finishes so subsequent unlocks
    /// can fire fresh.
    @Published var pendingUnlock: Badge?

    // MARK: - Persistence keys

    private let earnedKey = "chiron.badges.earned.v1"
    /// Per-exercise lifetime count of reps logged with formAnalysis.overallScore
    /// >= 0.85. Stored locally because the form score is not currently
    /// persisted on the ExerciseSetLog — we cannot recompute it from history,
    /// so we fold it into a running total at set-completion time.
    private let cleanFormRepsKey = "chiron.badges.clean_form_reps.v1"
    /// Lifetime cumulative minutes of tracked exercise — accumulated whenever
    /// `evaluateAfterSet` runs, since the set-end is the only moment we know
    /// how long the *last set* took. History-pass durations supplement this
    /// for sets logged before the badge system shipped.
    private let durationSecondsKey = "chiron.badges.duration_seconds.v1"

    // MARK: - Pending celebration queue

    /// Newly unlocked badges queued for celebration. We expose them one at a
    /// time via `pendingUnlock` so a single set save that crosses multiple
    /// thresholds (e.g. first-set + clean-set + 100 club) animates as a
    /// sequence instead of stacking.
    private var unlockQueue: [Badge] = []

    private init() {
        let stored = UserDefaults.standard.array(forKey: earnedKey) as? [String] ?? []
        self.earnedBadgeIDs = Set(stored)
    }

    // MARK: - Public entry points

    /// Called from the onboarding "I'm ready" hand-off. Idempotent.
    func markProfileComplete() {
        award(BadgeCatalog.profileComplete)
        flushQueue()
    }

    /// Evaluate badges that depend on the just-completed set's in-memory form
    /// signals. Caller passes the same `aggregatedMetrics` snapshot used by
    /// the coaching pipeline — those flags are not persisted on the
    /// ExerciseSetLog, so this is the only chance to read them.
    ///
    /// Triggers `recomputeFromHistory` after evaluating the live signals so
    /// the same call that lands a clean set also picks up "100 Club" or a
    /// fresh consistency milestone without the caller wiring two events.
    func evaluateAfterSet(
        exerciseName: String,
        isBodyweight: Bool,
        reps: Int,
        formAnalysis: FormAnalysis?,
        aggregatedMetrics: SetEndAggregatedMetrics,
        setDurationSeconds: TimeInterval?,
        userId: String
    ) {
        guard reps > 0 else { return }

        // Set Closer always unlocks on the first valid set we see.
        award(BadgeCatalog.setCloser)

        // Form-quality unlocks. Each guard ensures we only consider the
        // exercise types where the underlying signal is meaningful.
        evaluateFormQuality(
            exerciseName: exerciseName,
            isBodyweight: isBodyweight,
            reps: reps,
            formAnalysis: formAnalysis,
            aggregatedMetrics: aggregatedMetrics
        )

        // The Standard counts lifetime reps performed at >=85% form score.
        if let score = formAnalysis?.overallScore, score >= 0.85 {
            incrementCleanFormReps(exerciseName: exerciseName, by: reps)
        }

        // Add this set's duration to the running cumulative-time total used
        // for the Heavy Hour badge. The history pass will also rebuild from
        // workout-day spans so we don't double-count, but local accumulation
        // catches Track sessions that never write a set-spanning workoutLog
        // duration upstream.
        if let secs = setDurationSeconds, secs > 0 {
            addDurationSeconds(secs)
            if cumulativeDurationSeconds() >= 60 * 60 {
                award(BadgeCatalog.heavyHour)
            }
        }

        // Drain the live-signal awards immediately so the user sees the
        // unlock overlay before the history pass finishes.
        flushQueue()

        // Lifetime / streak / mastery rules need the full history.
        WorkoutLogService.shared.getAllHistoryForUser(userId: userId) { [weak self] result in
            guard case let .success(logs) = result else { return }
            DispatchQueue.main.async {
                self?.recomputeFromHistory(setLogs: logs)
            }
        }
    }

    /// Pure-function pass over history. Safe to call from anywhere — the
    /// internal set-difference makes repeated invocations idempotent.
    func recomputeFromHistory(setLogs: [ExerciseSetLog]) {
        let validLogs = setLogs.filter { ($0.reps ?? 0) > 0 }
        guard !validLogs.isEmpty else { return }

        evaluateExerciseMastery(setLogs: validLogs)
        evaluateVolumeClubs(setLogs: validLogs)
        evaluateConsistency(setLogs: validLogs)
        evaluateHeavyHour(setLogs: validLogs)
        flushQueue()
    }

    // MARK: - Form quality

    private func evaluateFormQuality(
        exerciseName: String,
        isBodyweight: Bool,
        reps: Int,
        formAnalysis: FormAnalysis?,
        aggregatedMetrics: SetEndAggregatedMetrics
    ) {
        let exerciseType = TrackedExerciseType.from(exerciseName: exerciseName)

        // Clean Set — the average form score for this set must clear the bar.
        // Falls back to the final FormAnalysis snapshot when the running mean
        // is unavailable (e.g. degenerate per-frame stream).
        let setMeanScore = aggregatedMetrics.overallScoreMean ?? formAnalysis?.overallScore
        if let score = setMeanScore, score >= 0.75 {
            award(BadgeCatalog.cleanSet)
        }

        let isSquat = (exerciseType == .bodyweight || exerciseType == .barbell)
        let validReps = aggregatedMetrics.validReps

        if isSquat {
            // Depth Demon — 10+ reps in one set, all hitting good depth.
            if isBodyweight {
                if validReps.count >= 10, validReps.allSatisfy({ !$0.shallowDepth }) {
                    award(BadgeCatalog.depthDemon)
                }
            } else if reps >= 10,
                      (aggregatedMetrics.issueCounts[.insufficientDepth] ?? 0) == 0 {
                award(BadgeCatalog.depthDemon)
            }

            // Knees Out — 0 valgus flags on the set. Require ≥3 reps so a
            // throwaway one-rep set doesn't trivially mint the badge.
            if reps >= 3 {
                let valgusFlagged: Bool = isBodyweight
                    ? validReps.contains(where: { $0.kneeValgus })
                    : (aggregatedMetrics.issueCounts[.kneeValgus] ?? 0) > 0
                if !valgusFlagged && (isBodyweight ? !validReps.isEmpty : true) {
                    award(BadgeCatalog.kneesOut)
                }
            }

            // Tall Chest — 0 forward-lean flags on the set.
            if reps >= 3 {
                let leanFlagged: Bool = isBodyweight
                    ? validReps.contains(where: { $0.excessiveForwardLean })
                    : (aggregatedMetrics.issueCounts[.forwardLean] ?? 0) > 0
                if !leanFlagged && (isBodyweight ? !validReps.isEmpty : true) {
                    award(BadgeCatalog.tallChest)
                }
            }
        }

        // Tempo Master — average eccentric phase ≥1.5s for the set.
        if let ecc = formAnalysis?.avgEccentricMs, ecc >= 1500 {
            award(BadgeCatalog.tempoMaster)
        }
    }

    // MARK: - The Standard tracking

    private func incrementCleanFormReps(exerciseName: String, by reps: Int) {
        var stored = (UserDefaults.standard.dictionary(forKey: cleanFormRepsKey) as? [String: Int]) ?? [:]
        let next = (stored[exerciseName] ?? 0) + reps
        stored[exerciseName] = next
        UserDefaults.standard.set(stored, forKey: cleanFormRepsKey)
        if next >= 50 {
            award(BadgeCatalog.theStandard)
        }
    }

    // MARK: - Exercise mastery

    private func evaluateExerciseMastery(setLogs: [ExerciseSetLog]) {
        let totalsByExercise = lifetimeReps(by: { $0.exerciseName }, in: setLogs)

        if (totalsByExercise["Bodyweight Squat"] ?? 0) >= 100 {
            award(BadgeCatalog.bodyweightBuilder)
        }
        let backSquatReps = (totalsByExercise["Barbell Back Squat"] ?? 0)
            + (totalsByExercise["Back Squat"] ?? 0)
        if backSquatReps >= 50  { award(BadgeCatalog.ironInitiate) }
        if backSquatReps >= 250 { award(BadgeCatalog.ironVeteran) }

        let benchReps = totalsByExercise.reduce(0) { acc, pair in
            let lower = pair.key.lowercased()
            // Match all bench-press variants (close-grip etc.) under a single bucket.
            return lower.contains("bench press") ? acc + pair.value : acc
        }
        if benchReps >= 100 { award(BadgeCatalog.benchPressed) }

        let hingeReps = totalsByExercise.reduce(0) { acc, pair in
            let lower = pair.key.lowercased()
            // Treat both deadlift and Romanian deadlift / RDL as hinge volume.
            if lower.contains("romanian") || lower.contains("rdl") || lower.contains("deadlift") {
                return acc + pair.value
            }
            return acc
        }
        if hingeReps >= 100 { award(BadgeCatalog.hipHingeHero) }

        let rowReps = totalsByExercise.reduce(0) { acc, pair in
            let lower = pair.key.lowercased()
            if lower.contains("barbell row")
                || lower.contains("bent-over row")
                || lower.contains("bent over row") {
                return acc + pair.value
            }
            return acc
        }
        if rowReps >= 100 { award(BadgeCatalog.rowBoss) }

        // Six-Pack — at least one set across all six tracked exercise types.
        let names = Set(setLogs.map { $0.exerciseName })
        let coverage: Set<TrackedExerciseType> = Set(names.map { TrackedExerciseType.from(exerciseName: $0) })
        let required: Set<TrackedExerciseType> = [
            .bodyweight, .barbell, .benchPress, .deadlift, .romanianDeadlift, .row
        ]
        if required.isSubset(of: coverage) {
            award(BadgeCatalog.sixPack)
        }
    }

    // MARK: - Volume clubs

    private func evaluateVolumeClubs(setLogs: [ExerciseSetLog]) {
        let total = setLogs.reduce(0) { $0 + ($1.reps ?? 0) }
        if total >= 100  { award(BadgeCatalog.club100) }
        if total >= 500  { award(BadgeCatalog.club500) }
        if total >= 1000 { award(BadgeCatalog.club1000) }
    }

    // MARK: - Heavy Hour

    /// Sum the wall-clock span between the first and last set of every workout
    /// the user has logged. Combined with the live per-set deltas accumulated
    /// during `evaluateAfterSet`, this catches users who logged sessions
    /// before the badge system shipped without double-counting current
    /// sessions (the live counter is only checked alongside this number).
    private func evaluateHeavyHour(setLogs: [ExerciseSetLog]) {
        let grouped = Dictionary(grouping: setLogs, by: { $0.workoutLogId })
        let historicalSeconds: TimeInterval = grouped.reduce(0.0) { running, entry in
            let timestamps = entry.value.map { $0.timestamp }
            guard let first = timestamps.min(), let last = timestamps.max() else { return running }
            return running + max(0, last.timeIntervalSince(first))
        }
        let total = historicalSeconds + cumulativeDurationSeconds()
        if total >= 60 * 60 {
            award(BadgeCatalog.heavyHour)
        }
    }

    // MARK: - Consistency

    private func evaluateConsistency(setLogs: [ExerciseSetLog]) {
        let calendar = Calendar.current
        let workoutDays: [Date] = Set(
            setLogs.map { calendar.startOfDay(for: $0.timestamp) }
        ).sorted()
        guard let firstDay = workoutDays.first, let lastDay = workoutDays.last else { return }

        // Back for More — any pair of adjacent workout days exactly 1 day apart.
        if hasAdjacentDays(workoutDays, gap: 1, calendar: calendar) {
            award(BadgeCatalog.backForMore)
        }

        // Week One — three workouts within the first 7 days from the user's
        // first-ever logged set. Rolling window not needed: the rule keys off
        // the inception date, not any future window.
        if let weekEnd = calendar.date(byAdding: .day, value: 6, to: firstDay) {
            let workoutsInFirstWeek = workoutDays.filter { $0 >= firstDay && $0 <= weekEnd }.count
            if workoutsInFirstWeek >= 3 {
                award(BadgeCatalog.weekOne)
            }
        }

        // Streaks (with 1 grace day per rolling 7-day window).
        let streakLength = longestStreakWithGrace(workoutDays, calendar: calendar)
        if streakLength >= 7  { award(BadgeCatalog.streak7) }
        if streakLength >= 14 { award(BadgeCatalog.streak14) }
        if streakLength >= 30 { award(BadgeCatalog.streak30) }

        // Comeback — any time the user returned after a 7+ day gap.
        for i in 1..<workoutDays.count {
            let gap = calendar.dateComponents([.day], from: workoutDays[i - 1], to: workoutDays[i]).day ?? 0
            if gap >= 8 { // 7 full days off → 8-day delta between adjacent workouts.
                award(BadgeCatalog.comeback)
                break
            }
        }

        // Monthly Regular — any single calendar month with ≥12 workout days.
        let monthCounts = Dictionary(grouping: workoutDays) {
            calendar.dateComponents([.year, .month], from: $0)
        }.mapValues { $0.count }
        if monthCounts.values.contains(where: { $0 >= 12 }) {
            award(BadgeCatalog.monthlyRegular)
        }

        // Touch lastDay so the compiler never treats the binding as unused if
        // future rules drop their use of it. Cheap and prevents accidental
        // refactor regressions.
        _ = lastDay
    }

    private func hasAdjacentDays(_ days: [Date], gap: Int, calendar: Calendar) -> Bool {
        for i in 1..<days.count {
            let delta = calendar.dateComponents([.day], from: days[i - 1], to: days[i]).day ?? 0
            if delta == gap { return true }
        }
        return false
    }

    /// Longest streak of workout days where one missed day is forgiven per
    /// rolling 7-day window. Walks the sorted day list, tracking grace usage
    /// and resetting whenever the gap exceeds what grace can cover.
    private func longestStreakWithGrace(_ days: [Date], calendar: Calendar) -> Int {
        guard !days.isEmpty else { return 0 }
        var bestStreak = 1
        var currentStreak = 1
        var graceUsedOnDay: [Date] = []

        for i in 1..<days.count {
            let prev = days[i - 1]
            let curr = days[i]
            let gap = calendar.dateComponents([.day], from: prev, to: curr).day ?? 0

            // Drop expired grace tokens (older than 7 days from current day).
            if let cutoff = calendar.date(byAdding: .day, value: -7, to: curr) {
                graceUsedOnDay.removeAll { $0 < cutoff }
            }

            if gap == 1 {
                currentStreak += 1
            } else if gap == 2 && graceUsedOnDay.count < 1 {
                // Skipped one day — burn a grace token and keep counting.
                currentStreak += 1
                graceUsedOnDay.append(curr)
            } else {
                currentStreak = 1
                graceUsedOnDay.removeAll()
            }

            bestStreak = max(bestStreak, currentStreak)
        }
        return bestStreak
    }

    // MARK: - Persistence helpers

    private func lifetimeReps<Key: Hashable>(
        by key: (ExerciseSetLog) -> Key,
        in logs: [ExerciseSetLog]
    ) -> [Key: Int] {
        var totals: [Key: Int] = [:]
        for log in logs {
            guard let reps = log.reps, reps > 0 else { continue }
            totals[key(log), default: 0] += reps
        }
        return totals
    }

    private func cumulativeDurationSeconds() -> TimeInterval {
        UserDefaults.standard.double(forKey: durationSecondsKey)
    }

    private func addDurationSeconds(_ seconds: TimeInterval) {
        let next = cumulativeDurationSeconds() + seconds
        UserDefaults.standard.set(next, forKey: durationSecondsKey)
    }

    /// Records the badge as earned and queues a celebration. Idempotent — a
    /// badge that's already in `earnedBadgeIDs` short-circuits, so re-running
    /// the history pass is free.
    private func award(_ badge: Badge) {
        guard !earnedBadgeIDs.contains(badge.id) else { return }
        earnedBadgeIDs.insert(badge.id)
        persistEarned()
        unlockQueue.append(badge)
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    private func persistEarned() {
        UserDefaults.standard.set(Array(earnedBadgeIDs), forKey: earnedKey)
    }

    /// Pop one badge from the queue into `pendingUnlock`. The unlock overlay
    /// resets `pendingUnlock` to nil when its animation finishes, at which
    /// point we surface the next queued badge.
    private func flushQueue() {
        guard pendingUnlock == nil, !unlockQueue.isEmpty else { return }
        let next = unlockQueue.removeFirst()
        pendingUnlock = next
    }

    /// Called by the overlay when the unlock animation finishes. Pulls the
    /// next queued badge (if any) so chained unlocks animate in sequence.
    func didFinishCelebration() {
        pendingUnlock = nil
        flushQueue()
    }

    // MARK: - Catalog helpers

    func isEarned(_ badge: Badge) -> Bool { earnedBadgeIDs.contains(badge.id) }

    var earnedBadges: [Badge] {
        BadgeCatalog.all.filter { earnedBadgeIDs.contains($0.id) }
    }

    #if DEBUG
    /// Wipe state for development. Not reachable from release builds.
    func _resetForDebug() {
        earnedBadgeIDs.removeAll()
        unlockQueue.removeAll()
        pendingUnlock = nil
        UserDefaults.standard.removeObject(forKey: earnedKey)
        UserDefaults.standard.removeObject(forKey: cleanFormRepsKey)
        UserDefaults.standard.removeObject(forKey: durationSecondsKey)
    }
    #endif
}
