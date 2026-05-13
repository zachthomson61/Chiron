//
//  RecentProgressSection.swift
//  Chiron
//
//  Home-tab section that surfaces the three exercises the user has most
//  recently trained, each rendered as a compact version of the history-sheet
//  progression chart with the exercise's library thumbnail alongside the
//  title. Tapping a card opens the full history sheet for that exercise.
//

import SwiftUI
import Charts

// MARK: - Section View

/// "Recent Progress" home-page section. Loads every set log for the user
/// on appear, ranks exercises by most recent activity, and renders the
/// three most recently trained as compact progression cards.
struct RecentProgressSection: View {
    @StateObject private var loader = RecentProgressLoader()
    @State private var selectedEntry: RecentProgressEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Strength Progress")
                .font(.neueMontrealBold(size: 20))
                .foregroundColor(.textPrimary)

            if loader.isLoading {
                // Skeleton placeholder so the layout doesn't jump when data
                // finishes loading.
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .primaryPurple))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
            } else if loader.entries.isEmpty {
                emptyState
            } else {
                VStack(spacing: 12) {
                    ForEach(loader.entries) { entry in
                        Button {
                            selectedEntry = entry
                        } label: {
                            RecentProgressCard(entry: entry)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .onAppear {
            loader.loadIfNeeded()
        }
        .sheet(item: $selectedEntry) { entry in
            ExerciseHistorySheet(
                isPresented: Binding(
                    get: { selectedEntry != nil },
                    set: { if !$0 { selectedEntry = nil } }
                ),
                exerciseName: entry.exerciseName,
                isBodyweight: entry.isBodyweight
            )
            .presentationDragIndicator(.visible)
        }
    }

    /// Inline placeholder shown when the user hasn't logged at least two days
    /// of any exercise yet — progression needs ≥2 data points per exercise.
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Log a few sets to see your progression here")
                .font(.neueMontrealSemiBold(size: 15))
                .foregroundColor(.textPrimary)
            Text("Your three most recently trained exercises will show up in this section.")
                .font(.neueMontrealRegular(size: 13))
                .foregroundColor(.textSecondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface)
        .cornerRadius(16)
    }
}

// MARK: - Card

/// Compact progression card rendered inside the section. Layout:
///   [title / subtitle]            [thumbnail]
///   [───────── mini chart ─────────────────]
struct RecentProgressCard: View {
    let entry: RecentProgressEntry
    /// Each card owns its own Volume toggle state so the Home cards don't
    /// fight each other when the user taps the Volume pill on one of them.
    @State private var showVolume: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                RecentProgressThumbnail(imageName: entry.imageName)
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.exerciseName)
                        .font(.neueMontrealBold(size: 17))
                        .foregroundColor(.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let prText = entry.personalRecordText {
                        Text(prText)
                            .font(.neueMontrealSemiBold(size: 13))
                            .foregroundColor(.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)

            // Exact same chart used in the history sheet — the Home card
            // just suppresses the inner "Strength" title + card chrome so
            // the chart sits naturally under the title/thumbnail header
            // above. Minimal horizontal padding (6pt) here instead of the
            // full 16pt — the chart needs the extra width to fit the
            // rotated "lbs" title on the leading edge AND the Volume pill
            // on the trailing edge without either getting clipped by the
            // card's corner radius.
            ProgressChartSection(
                setLogs: entry.setLogs,
                showVolume: $showVolume,
                isBodyweight: entry.isBodyweight,
                showsOuterChrome: false
            )
            // Minimal horizontal padding on the chart inside the Home card
            // (4pt instead of 16pt) so the rotated leading `lbs` title and
            // the trailing Volume pill both have enough room to render
            // inside the card's `cornerRadius(16)` clip.
            .padding(.leading, 4)
            .padding(.trailing, 4)
        }
        .padding(.vertical, 16)
        .background(Color.surface)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primaryPurple.opacity(0.15), lineWidth: 1)
        )
    }
}

// MARK: - Thumbnail

/// 52×52 rounded thumbnail matching the exercise-library card artwork.
/// Falls back to a system icon for exercises whose imageName points to an
/// SF Symbol (rather than an asset-catalog image).
private struct RecentProgressThumbnail: View {
    let imageName: String?

    var body: some View {
        ZStack {
            if let imageName = imageName {
                if imageName.contains(".") && !imageName.hasSuffix(".jpg") && !imageName.hasSuffix(".png") {
                    // SF Symbol path
                    Image(systemName: imageName)
                        .font(.system(size: 24))
                        .foregroundStyle(Color.white.opacity(0.85))
                } else if let uiImage = Self.loadBundleImage(named: imageName) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    fallbackIcon
                }
            } else {
                fallbackIcon
            }
        }
        .frame(width: 52, height: 52)
        .background(Color.white.opacity(0.12))
        .cornerRadius(10)
        .clipped()
    }

    private var fallbackIcon: some View {
        Image(systemName: "figure.strengthtraining.traditional")
            .font(.system(size: 24))
            .foregroundStyle(Color.white.opacity(0.55))
    }

    /// Searches the asset catalog and main bundle (jpg / png). Mirrors the
    /// image-loading logic in `ExerciseThumbnail` without pulling the full
    /// helper in — keeps this file self-contained.
    static func loadBundleImage(named name: String) -> UIImage? {
        let base = name.replacingOccurrences(of: ".jpg", with: "").replacingOccurrences(of: ".png", with: "")
        if let ui = UIImage(named: base) { return ui }
        if let ui = UIImage(named: name) { return ui }
        if let url = Bundle.main.url(forResource: base, withExtension: "jpg"),
           let ui = UIImage(contentsOfFile: url.path) { return ui }
        if let url = Bundle.main.url(forResource: base, withExtension: "png"),
           let ui = UIImage(contentsOfFile: url.path) { return ui }
        return nil
    }
}

// MARK: - Data Structures

/// Single aggregated day for a given exercise.
struct RecentProgressPoint: Identifiable {
    let id = UUID()
    let day: Date
    /// e1RM (lbs) for weighted exercises or top-set reps for bodyweight.
    let value: Double
}

/// Everything the card needs to render + what the sort orders on.
struct RecentProgressEntry: Identifiable {
    let id = UUID()
    let exerciseName: String
    let imageName: String?
    let isBodyweight: Bool
    /// Aggregated one-point-per-day series — used only for the subtitle
    /// delta. The chart itself is fed the raw `setLogs` so it re-renders
    /// with the exact same logic the history sheet uses.
    let points: [RecentProgressPoint]
    /// Raw set logs passed straight through to `ProgressChartSection` so
    /// the Home card chart is bit-for-bit identical to the History sheet.
    let setLogs: [ExerciseSetLog]

    /// Actual (not estimated) personal record derived from the raw set
    /// logs. Mirrors the history sheet so the Home card and the sheet
    /// stay in sync. Weighted: heaviest weight logged, tie-broken by the
    /// highest reps at that weight. Bodyweight: most reps in one set.
    var personalRecordText: String? {
        let performed = setLogs.filter { ($0.reps ?? 0) > 0 }
        guard !performed.isEmpty else { return nil }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "M/d/yy"

        if isBodyweight {
            guard let best = performed.max(by: { ($0.reps ?? 0) < ($1.reps ?? 0) }),
                  let reps = best.reps else { return nil }
            return "PR: \(reps) reps - \(dateFormatter.string(from: best.timestamp))"
        } else {
            let weighted = performed.filter { ($0.weight ?? 0) > 0 }
            guard !weighted.isEmpty else { return nil }
            guard let maxWeight = weighted.compactMap({ $0.weight }).max() else { return nil }
            let atMax = weighted.filter { ($0.weight ?? 0) == maxWeight }
            guard let best = atMax.max(by: { ($0.reps ?? 0) < ($1.reps ?? 0) }),
                  let reps = best.reps else { return nil }
            let weightStr: String
            if maxWeight == floor(maxWeight) {
                weightStr = "\(Int(maxWeight))"
            } else {
                weightStr = String(format: "%.1f", maxWeight)
            }
            return "PR: \(weightStr) lbs for \(reps) reps - \(dateFormatter.string(from: best.timestamp))"
        }
    }

    /// Short descriptor shown under the exercise name. Two cases:
    ///  - ≥ 2 days of data → delta from previous session ("+8 lbs since
    ///    last session").
    ///  - Single day of data → current value with an "only session" hint
    ///    so the card has a sensible secondary line even without a trend.
    var subtitle: String {
        let unit = isBodyweight ? "reps" : "lbs"
        guard let last = points.last else {
            return isBodyweight ? "Top set reps" : "Top set e1RM"
        }
        if points.count >= 2 {
            let prev = points[points.count - 2].value
            let delta = last.value - prev
            let sign = delta >= 0 ? "+" : "−"
            let mag = abs(delta)
            let formatted = mag.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%@%.0f %@", sign, mag, unit)
                : String(format: "%@%.1f %@", sign, mag, unit)
            return "\(formatted) since last session"
        } else {
            let formatted = last.value.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0f", last.value)
                : String(format: "%.1f", last.value)
            return "\(formatted) \(unit) — first session logged"
        }
    }
}

// MARK: - Loader

/// Fetches every set log for the user, aggregates per-day metrics per
/// exercise, and exposes the three exercises most recently trained.
@MainActor
final class RecentProgressLoader: ObservableObject {
    @Published var entries: [RecentProgressEntry] = []
    @Published var isLoading: Bool = false

    /// True once we've completed at least one fetch — prevents `loadIfNeeded`
    /// from re-firing every time HomeView re-appears.
    private var hasLoaded: Bool = false

    func loadIfNeeded() {
        guard !hasLoaded, !isLoading else { return }
        load()
    }

    /// Exercise names that can appear on the Home section. These are the
    /// seed exercises created in `ExerciseLibraryView`; logs in Firestore
    /// will be stored under these exact names.
    static let knownExerciseNames: [String] = [
        "Bodyweight Squat",
        "Barbell Back Squat",
        "Deadlift",
        "Barbell Bench Press",
        "Romanian Deadlift (RDL)",
        "Barbell Row"
    ]

    /// Issues one `getHistoryForExercise` query per known exercise and
    /// aggregates the results. This path uses the existing `(exerciseName,
    /// userId, timestamp)` Firestore composite index, so it works without
    /// requiring a new `(userId, timestamp)` index that the bulk fetch
    /// would otherwise need.
    func load() {
        isLoading = true
        let userId = UserManager.shared.getUserId()
        let names = Self.knownExerciseNames

        var collected: [ExerciseSetLog] = []
        let group = DispatchGroup()
        let lock = NSLock()

        for name in names {
            group.enter()
            WorkoutLogService.shared.getHistoryForExercise(name, userId: userId, limit: 200) { result in
                if case .success(let logs) = result {
                    lock.lock()
                    collected.append(contentsOf: logs)
                    lock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.isLoading = false
            self.hasLoaded = true
            self.entries = Self.computeTopEntries(from: collected)
        }
    }

    // MARK: - Aggregation

    /// Buckets raw set logs by exercise name, computes per-day points, and
    /// returns the three exercises with the most recent set log.
    private static func computeTopEntries(from logs: [ExerciseSetLog]) -> [RecentProgressEntry] {
        let grouped = Dictionary(grouping: logs, by: { $0.exerciseName })
        let bodyweight = UserManager.shared.getCurrentBodyweight()

        var candidates: [(entry: RecentProgressEntry, latest: Date)] = []

        for (name, exerciseLogs) in grouped {
            let isBodyweight = TrackedExerciseType.from(exerciseName: name) == .bodyweight
            let points = aggregateDailyPoints(
                logs: exerciseLogs,
                isBodyweight: isBodyweight,
                bodyweight: bodyweight
            )
            // Accept any exercise with at least one logged day — single-point
            // exercises still show up if they're among the user's three most
            // recently trained movements.
            guard !points.isEmpty else { continue }

            let latest = exerciseLogs.map(\.timestamp).max() ?? .distantPast
            candidates.append((
                entry: RecentProgressEntry(
                    exerciseName: name,
                    imageName: imageName(for: name),
                    isBodyweight: isBodyweight,
                    points: points,
                    setLogs: exerciseLogs
                ),
                latest: latest
            ))
        }

        return Array(
            candidates
                .sorted { $0.latest > $1.latest }
                .prefix(3)
                .map { $0.entry }
        )
    }

    /// One point per day. Mirrors the ExerciseHistorySheet aggregation so
    /// the home card and the detail sheet show the same values.
    private static func aggregateDailyPoints(
        logs: [ExerciseSetLog],
        isBodyweight: Bool,
        bodyweight: Double
    ) -> [RecentProgressPoint] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: logs) { cal.startOfDay(for: $0.timestamp) }

        let raw: [RecentProgressPoint] = grouped.compactMap { (day, logs) in
            if isBodyweight {
                let reps = logs.compactMap { log -> Int? in
                    guard let r = log.reps, r > 0 else { return nil }
                    return r
                }
                guard let topReps = reps.max() else { return nil }
                return RecentProgressPoint(day: day, value: Double(topReps))
            } else {
                let candidates = logs.compactMap { log -> (w: Double, r: Int)? in
                    guard let w = log.weight, w > 0, let r = log.reps, r > 0 else { return nil }
                    return (w, r)
                }
                guard let top = candidates.max(by: { ($0.w * Double($0.r)) < ($1.w * Double($1.r)) }) else {
                    return nil
                }
                let e1rm = top.w * (1.0 + Double(top.r) / 30.0)
                return RecentProgressPoint(day: day, value: e1rm)
            }
        }

        _ = bodyweight  // bodyweight is needed downstream for volume but not for the top-metric mini chart
        return raw.sorted { $0.day < $1.day }
    }

    /// Maps exercise name → image asset. Mirrors the seed data in
    /// `ExerciseLibraryView`; falls back to the strength-training system
    /// icon for exercises that use SF Symbols in the library.
    private static func imageName(for exerciseName: String) -> String? {
        switch exerciseName.lowercased() {
        case "bodyweight squat":
            return "BodyweightSquat"
        case "deadlift":
            return "Deadlift"
        case "barbell bench press":
            return "BarbellBenchPress"
        case "romanian deadlift (rdl)", "romanian deadlift":
            return "RomanianDeadlift"
        case "barbell back squat", "back squat":
            return "BarbellBackSquat"
        case "barbell row":
            return "BarbellRow"
        default:
            return nil
        }
    }
}
