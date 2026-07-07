//
//  ExerciseHistorySheet.swift
//  Chiron
//
//  Modal sheet for displaying exercise history from previous workouts.
//  Shows all logged sets for a specific exercise with weight, reps, flags, and dates.
//

import SwiftUI
import Foundation
import Charts

/// Modal sheet displaying exercise history from previous workouts.
///
/// Features:
/// - Fetches set logs from Firestore for the specified exercise
/// - Displays date, set number, weight, reps, and flags
/// - Shows loading state while fetching
/// - Handles empty state (no history yet)
/// - Handles error state with retry option
struct ExerciseHistorySheet: View {
    @Binding var isPresented: Bool
    let exerciseName: String
    /// When true, the chart switches to bodyweight mode: left y-axis is
    /// Top Set Reps (not e1RM), volume is computed as total reps ×
    /// user bodyweight, and the legend / latest-point callout change
    /// labels accordingly. Default false so existing call sites (weighted
    /// exercises) work unchanged.
    var isBodyweight: Bool = false

    @State private var setLogs: [ExerciseSetLog] = []
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?
    /// When true, daily total volume is overlaid on the e1RM chart as a
    /// secondary y-axis. The e1RM line always remains visible.
    @State private var showVolume: Bool = false
    
    var body: some View {
        // Dropped the NavigationView wrapper — it added a ~44pt nav bar
        // above the content that pushed everything down. The sheet now owns
        // its own layout so content can sit flush with the top.
        ZStack(alignment: .topLeading) {
            Color.background.ignoresSafeArea()

            if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .primaryPurple))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.textSecondary)

                    Text("Error Loading History")
                        .font(.neueMontrealBold(size: 20))
                        .foregroundColor(.textPrimary)

                    Text(error)
                        .font(.neueMontrealRegular(size: 16))
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)

                    Button("Retry") {
                        loadHistory()
                    }
                    .font(.neueMontrealSemiBold(size: 16))
                    .foregroundColor(.textPrimary)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.primaryPurple)
                    .cornerRadius(12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if setLogs.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 48))
                        .foregroundColor(.textSecondary)

                    Text("No History Yet")
                        .font(.neueMontrealBold(size: 20))
                        .foregroundColor(.textPrimary)

                    Text("Start logging sets to see your progress here")
                        .font(.neueMontrealRegular(size: 16))
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        // Leave just enough room at the top for the chevron
                        // dismiss button (see overlay below).
                        Spacer().frame(height: 48)

                        // Exercise title — flush with the top padding.
                        Text(exerciseName)
                            .font(.neueMontrealBold(size: 22))
                            .foregroundColor(.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.bottom, 8)

                        // PR summary — actual top set (not estimated).
                        // Weighted: max weight logged + its reps. Bodyweight:
                        // max reps. Both tagged with the date they happened.
                        if let prText = personalRecordText {
                            Text(prText)
                                .font(.neueMontrealSemiBold(size: 14))
                                .foregroundColor(.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.bottom, 12)
                        }

                        // Progression chart.
                        ProgressChartSection(
                            setLogs: setLogs,
                            showVolume: $showVolume,
                            isBodyweight: isBodyweight
                        )
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)

                        // Only show sets that actually have a rep count.
                        let performedSets = setLogs.filter { ($0.reps ?? 0) > 0 }

                        HStack {
                            // Pluralize "Set" based on count so the label
                            // reads correctly when there's only one entry.
                            Text("\(performedSets.count) Logged \(performedSets.count == 1 ? "Set" : "Sets"):")
                                .font(.neueMontrealSemiBold(size: 14))
                                .foregroundColor(.textPrimary)
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)

                        LazyVStack(spacing: 12) {
                            ForEach(performedSets) { setLog in
                                HistoryRow(
                                    setLog: setLog,
                                    isToday: Calendar.current.isDateInToday(setLog.timestamp),
                                    onSave: { weight, reps, completion in
                                        updateSet(setLog, weight: weight, reps: reps, completion: completion)
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                    }
                }
            }

            Button {
                isPresented = false
            } label: {
                Image(systemName: "xmark")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(Color.black.opacity(0.35))
                    .clipShape(Circle())
            }
            .padding(.leading, 16)
            .padding(.top, 12)
            .accessibilityLabel("Dismiss")
        }
        .onAppear {
            loadHistory()
        }
        .preferredColorScheme(.dark)
    }
    
    /// Actual (not estimated) personal record across the loaded set logs.
    /// Weighted exercises: heaviest weight ever logged; ties broken by
    /// highest reps at that weight. Bodyweight exercises: most reps in a
    /// single set. Returns nil if there's no qualifying set yet.
    private var personalRecordText: String? {
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

    private func loadHistory() {
        isLoading = true
        errorMessage = nil
        
        let userId = UserManager.shared.getUserId()
        
        // Validate userId
        guard !userId.isEmpty else {
            let errorMsg = "User ID is empty. Cannot load history."
            DispatchQueue.main.async {
                self.isLoading = false
                self.errorMessage = errorMsg
            }
            return
        }
        
        
        WorkoutLogService.shared.getHistoryForExercise(exerciseName, userId: userId) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let logs):
                    setLogs = logs
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    /// Persists an inline edit from a HistoryRow, then mirrors the change
    /// into the local `setLogs` array so the chart, PR line, and row all
    /// refresh without a re-fetch. The row stays in edit mode on failure
    /// (completion(false)) so the user can retry.
    private func updateSet(_ setLog: ExerciseSetLog, weight: Double?, reps: Int, completion: @escaping (Bool) -> Void) {
        WorkoutLogService.shared.updateSetLog(setLogId: setLog.id, weight: weight, reps: reps) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    if let idx = setLogs.firstIndex(where: { $0.id == setLog.id }) {
                        setLogs[idx].weight = weight
                        setLogs[idx].reps = reps
                    }
                    completion(true)
                case .failure:
                    completion(false)
                }
            }
        }
    }
}

// MARK: - Progression Chart

/// One aggregated data point per workout day.
private struct DailyProgressPoint: Identifiable {
    let id = UUID()
    let day: Date
    /// The primary metric plotted on the left y-axis.
    /// - Weighted exercises: estimated 1RM of the top set that day (Epley).
    /// - Bodyweight exercises: the top set's rep count (max reps in a
    ///   single set that day).
    let topMetric: Double
    /// Daily volume, always expressed in lbs so the right-axis unit
    /// stays consistent across modes.
    /// - Weighted: sum(weight × reps) across every set that day.
    /// - Bodyweight: total reps across all sets × user's bodyweight.
    let volume: Double
}

/// Progression chart card. Always draws the Top-Set metric line over time;
/// when the Volume pill is toggled on, daily total tonnage is overlaid as
/// semi-transparent bars on a secondary right-side y-axis.
///
/// For weighted exercises the top-set metric is estimated 1RM (Epley);
/// for bodyweight exercises it's the top set's rep count. The right-side
/// Volume axis is always in lbs — bodyweight volume is (total reps ×
/// user bodyweight), and the stored user bodyweight defaults to 180 lbs
/// until onboarding writes a real value.
struct ProgressChartSection: View {
    let setLogs: [ExerciseSetLog]
    @Binding var showVolume: Bool
    /// When true, all chart labels / aggregations switch to bodyweight
    /// mode (reps axis, reps-based PRs, volume = reps × bodyweight).
    let isBodyweight: Bool
    /// When false, the embedder is providing its own title + card
    /// background (e.g. the Home-page "Recent Strength Progress" card),
    /// so we skip the "Strength" header and the outer padding/fill.
    var showsOuterChrome: Bool = true

    /// Drives the left-to-right draw-in animation on first appearance.
    @State private var lineProgress: CGFloat = 0

    var body: some View {
        let points = dailyPoints()
        let growthPercent = percentIncrease(points: points)

        VStack(alignment: .leading, spacing: 10) {
            if showsOuterChrome {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Strength")
                            .font(.neueMontrealBold(size: 24))
                            .foregroundColor(.textPrimary)
                        Spacer()
                        volumeButton
                    }
                    if let pct = growthPercent {
                        growthPill(percent: pct)
                    }
                }
            }

            if points.count < 1 {
                Text("No weighted sets yet — log weight on a set to see your progression.")
                    .font(.neueMontrealRegular(size: 13))
                    .foregroundColor(.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 24)
            } else {
                // On the Home card the pill used to float over the chart's
                // top-right corner and visually overlapped the top
                // gridline / latest-point capsule. Lift it into its own row
                // just above the chart so the graph has a clean top edge.
                if !showsOuterChrome {
                    HStack {
                        if let pct = growthPercent {
                            growthPill(percent: pct)
                        }
                        Spacer()
                        volumeButton
                    }
                }

                chart(for: points)
                    .frame(height: 220)

                // Minimal legend keeps the chart clean while still making the
                // two series legible when Volume is enabled.
                HStack(spacing: 14) {
                    // Top-set metric label changes to reflect what the
                    // purple line actually represents in each mode.
                    legendDot(
                        color: .primaryPurple,
                        label: isBodyweight ? "Top Set Reps" : "Top Set Estimated 1 Rep Max"
                    )
                    if showVolume {
                        legendBar(color: .volumeAccent, label: "Total Weight Lifted")
                    }
                    Spacer()
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, showsOuterChrome ? 16 : 0)
        .padding(.top, showsOuterChrome ? 10 : 0)
        .padding(.bottom, showsOuterChrome ? 14 : 0)
        .background(showsOuterChrome ? Color.white.opacity(0.05) : Color.clear)
        .cornerRadius(showsOuterChrome ? 16 : 0)
    }

    // MARK: - Volume Pill

    private var volumeButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                showVolume.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text(showVolume ? "Hide Volume" : "Show Volume")
                    .font(.neueMontrealSemiBold(size: 13))
            }
            // When active, the button adopts the same cyan as the bars /
            // axis numbers / legend chip so the whole Volume series reads
            // as one coordinated element.
            .foregroundColor(showVolume ? Color.softBlack : .textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(showVolume ? Color.volumeAccent : Color.white.opacity(0.08))
            )
            .overlay(
                Capsule()
                    .stroke(showVolume ? Color.clear : Color.white.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.neueMontrealRegular(size: 11))
                .foregroundColor(.textSecondary)
        }
    }

    /// Volume legend marker — uses a small bar shape instead of a dot so the
    /// icon visually matches the BarMark it represents in the chart.
    private func legendBar(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(color)
                .frame(width: 10, height: 7)
            Text(label)
                .font(.neueMontrealRegular(size: 11))
                .foregroundColor(.textSecondary)
        }
    }

    // MARK: - Growth Pill

    /// Total percentage gain from the lowest top-metric on this chart to the
    /// highest. Returns nil when there isn't an upward delta to celebrate
    /// (single point, or every day is identical).
    private func percentIncrease(points: [DailyProgressPoint]) -> Double? {
        guard points.count >= 2 else { return nil }
        // Peak must come AFTER the trough chronologically — only then is
        // it a genuine upward trend worth celebrating. Flat series, single
        // points, and "peaked early then dropped" series all return nil.
        guard let mn = points.min(by: { $0.topMetric < $1.topMetric }),
              let mx = points.max(by: { $0.topMetric < $1.topMetric }),
              mn.id != mx.id,
              mx.day > mn.day,
              mn.topMetric > 0,
              mx.topMetric > mn.topMetric else { return nil }
        return (mx.topMetric - mn.topMetric) / mn.topMetric * 100
    }

    /// "↑ +25% Peak" capsule shown alongside the chart's header row. Uses
    /// `secondaryPurple` so it visually couples with the min/max highlight
    /// dots on the chart that the percentage is computed from.
    private func growthPill(percent: Double) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.up")
                .font(.system(size: 10, weight: .bold))
            Text("+\(Int(percent.rounded()))% Peak")
                .font(.neueMontrealSemiBold(size: 12))
        }
        .foregroundColor(.secondaryPurple)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.secondaryPurple.opacity(0.15)))
    }

    // MARK: - Chart

    @ViewBuilder
    private func chart(for points: [DailyProgressPoint]) -> some View {
        // Shared y-domain padding — gives the line room to breathe and keeps
        // PR markers from clipping against the top edge. `topMetric` is lbs
        // for weighted exercises and reps for bodyweight.
        let maxMetric = points.map { $0.topMetric }.max() ?? 1
        let minMetric = points.map { $0.topMetric }.min() ?? 0
        // Bodyweight's scale is tiny (often 1–15 reps), so the minimum pad
        // has to be smaller than the 5-lb pad used for weighted.
        let minPad = isBodyweight ? 1.0 : 5.0
        let metricPad = max((maxMetric - minMetric) * 0.15, minPad)
        let yLower = max(0, minMetric - metricPad)
        let yUpper = maxMetric + metricPad

        // Scale volume into the VISIBLE top-metric range so the bar's top
        // sits inside the plot body.
        let maxVolume = points.map { $0.volume }.max() ?? 0
        let visibleRange = max(yUpper - yLower, 1)

        // The two endpoints the growth pill is measuring. We highlight
        // them in `secondaryPurple` (same as the pill) so the user can
        // visually tie the percentage to the points it's derived from.
        // Highlighting only kicks in for a genuine upward trend — peak
        // must come temporally AFTER the trough. Otherwise the chart
        // falls back to plain dots for every session and the pill hides.
        let minPoint = points.min(by: { $0.topMetric < $1.topMetric })
        let maxPoint = points.max(by: { $0.topMetric < $1.topMetric })
        let isUpwardTrend: Bool = {
            guard let mn = minPoint, let mx = maxPoint, mn.id != mx.id else { return false }
            return mx.day > mn.day && mx.topMetric > mn.topMetric
        }()
        let highlightedIds: Set<UUID> = {
            guard isUpwardTrend, let mn = minPoint, let mx = maxPoint else { return [] }
            return [mn.id, mx.id]
        }()

        // Warped time positions: each session's x-coordinate is the
        // cumulative real-day gap from the first session, except every
        // consecutive pair is forced to be at least `minSpacingDays`
        // apart. This preserves time-proportional spacing for far-apart
        // sessions while preventing clustered sessions (e.g. two days in
        // a row) from visually overlapping their dots and date labels.
        let minSpacingDays: Double = 3.0
        let dayToPosition: [Date: Double] = {
            var map: [Date: Double] = [:]
            for (i, p) in points.enumerated() {
                if i == 0 {
                    map[p.day] = 0
                } else {
                    let prevDay = points[i - 1].day
                    let prevPos = map[prevDay] ?? 0
                    let realGapDays = p.day.timeIntervalSince(prevDay) / 86400
                    map[p.day] = prevPos + max(realGapDays, minSpacingDays)
                }
            }
            return map
        }()
        let firstPos = points.first.flatMap { dayToPosition[$0.day] } ?? 0
        let lastPos = points.last.flatMap { dayToPosition[$0.day] } ?? 0
        // ±1-day padding so the first/last data points don't sit flush
        // against the plot edges (their date labels would otherwise clip
        // on the card's corner radius).
        let xDomain: ClosedRange<Double> = (firstPos - 1) ... (lastPos + 1)
        // Date labels still cap at ~6 so long histories don't pack
        // unreadable stacks of dates along the axis.
        let labelDays = thinnedAxisDays(points: points)
        let labelPositions = labelDays.compactMap { dayToPosition[$0] }.sorted()

        Chart {
            // Volume bars are ALWAYS inserted into the mark tree — with
            // opacity driving visibility — so their draw-order slot below
            // the line / points never shifts. Previously the bars were
            // conditionally added when `showVolume` toggled on, which
            // caused Swift Charts to re-compose the chart and briefly
            // paint the bars on top of the e1RM data point before
            // settling. Opacity animates cleanly behind the line.
            let barOpacity = showVolume ? 0.55 : 0.0
            let barLabelOpacity = showVolume ? 1.0 : 0.0
            ForEach(points) { p in
                let idx = dayToPosition[p.day] ?? 0
                let ratio = maxVolume > 0 ? (p.volume / maxVolume) : 0
                let barTop = yLower + visibleRange * ratio * 0.75
                BarMark(
                    x: .value("Position", idx),
                    yStart: .value("Base", yLower),
                    yEnd: .value("Volume Top", barTop),
                    width: .fixed(18)
                )
                // Same bright secondary accent as the trailing y-axis
                // numbers — matching color makes the two pieces of the
                // Volume series read as one unit.
                .foregroundStyle(Color.volumeAccent.opacity(barOpacity))
                .cornerRadius(3)
                .annotation(position: .top, alignment: .center, spacing: 2) {
                    // Value label floats on top of every bar — overlap on
                    // tightly-clustered sessions is acceptable per product
                    // direction, since the primary line/dot series is the
                    // chart's focus.
                    Text("\(Int(p.volume)) lbs")
                        .font(.neueMontrealSemiBold(size: 10))
                        .foregroundColor(.volumeAccent)
                        .opacity(barLabelOpacity)
                }
            }

            // Primary top-metric line (e1RM for weighted, top reps for
            // bodyweight). Smooth monotone interpolation avoids the
            // overshoot Catmull-Rom can introduce on abrupt PR jumps.
            ForEach(points) { p in
                let idx = dayToPosition[p.day] ?? 0
                LineMark(
                    x: .value("Position", idx),
                    y: .value("Top", p.topMetric),
                    series: .value("Series", "Top")
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(Color.primaryPurple)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }

            // Uniform small dots for every day that isn't the min or max
            // endpoint. Same `primaryPurple` as the line so the series reads
            // as one piece — only the two endpoints the growth pill is
            // measuring get the brighter `secondaryPurple` treatment below.
            ForEach(points.filter { !highlightedIds.contains($0.id) }) { p in
                let idx = dayToPosition[p.day] ?? 0
                PointMark(
                    x: .value("Position", idx),
                    y: .value("Top", p.topMetric)
                )
                .symbol(.circle)
                .symbolSize(45)
                .foregroundStyle(Color.primaryPurple)
            }

            // Min endpoint — slightly smaller than the peak, with a soft
            // gray glow so the user reads it as "starting point" rather
            // than "achievement". Only rendered alongside the upward-
            // trend treatment so it matches when the pill is shown.
            if isUpwardTrend, let mn = minPoint {
                let mnIdx = dayToPosition[mn.day] ?? 0
                PointMark(
                    x: .value("Position", mnIdx),
                    y: .value("Top", mn.topMetric)
                )
                .symbol(.circle)
                .symbolSize(220)
                .foregroundStyle(Color.gray.opacity(0.45))

                PointMark(
                    x: .value("Position", mnIdx),
                    y: .value("Top", mn.topMetric)
                )
                .symbol(.circle)
                .symbolSize(100)
                .foregroundStyle(Color.secondaryPurple)
            }

            // Max endpoint — slightly larger than the min, with a purple
            // glow + value capsule. Same `secondaryPurple` as the growth
            // pill so the user sees "this point is the peak the pill is
            // bragging about". Hidden alongside the pill when there's no
            // upward trend to celebrate, so chart and pill stay in sync.
            if isUpwardTrend, let mx = maxPoint {
                let mxIdx = dayToPosition[mx.day] ?? 0
                PointMark(
                    x: .value("Position", mxIdx),
                    y: .value("Top", mx.topMetric)
                )
                .symbol(.circle)
                .symbolSize(300)
                .foregroundStyle(Color.secondaryPurple.opacity(0.35))

                PointMark(
                    x: .value("Position", mxIdx),
                    y: .value("Top", mx.topMetric)
                )
                .symbol(.circle)
                .symbolSize(140)
                .foregroundStyle(Color.secondaryPurple)
                .annotation(position: .top, alignment: .center, spacing: 4) {
                    // Unit switches with mode — "123 lbs" for weighted,
                    // "8 reps" for bodyweight.
                    Text("\(Int(mx.topMetric)) \(isBodyweight ? "reps" : "lbs")")
                        .font(.neueMontrealBold(size: 11))
                        .foregroundColor(.textPrimary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.secondaryPurple.opacity(0.85)))
                }
            }
        }
        .chartYScale(domain: yLower...yUpper)
        .chartXScale(domain: xDomain)
        .chartXAxis {
            // Tick + gridline only — the stacked "Thu / 16" date labels are
            // drawn via chartOverlay below. AxisValueLabel with custom
            // content was silently not rendering for this chart (most
            // likely a Swift Charts layout quirk with centered multi-line
            // labels at single-point domains), so we bypass the axis label
            // system entirely and position the labels ourselves.
            AxisMarks(values: labelPositions) { _ in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.18))
                AxisTick().foregroundStyle(Color.white.opacity(0.35))
            }
        }
        // Reserve space at the bottom of the plot area for the custom date
        // labels. Without this, the plot stretches to the chart frame's
        // bottom edge and our overlay labels would render below the frame
        // and get clipped.
        .chartPlotStyle { plot in
            plot.padding(.bottom, 34)
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.18))
                AxisValueLabel {
                    // Tick numbers match the e1RM data point color so the
                    // user can visually associate the axis with the series.
                    // The axis title ("lbs") stays white as a neutral unit
                    // marker.
                    if let v = value.as(Double.self) {
                        Text("\(Int(v))")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.primaryPurple)
                    }
                }
            }
            if showVolume {
                // Trailing axis mirrors the BarMark mapping so the numbers
                // printed here are the actual tonnage in lbs (inverts the
                // `ratio * 0.75` scaling applied to bar heights). Colored to
                // match the volume bars / legend dot for instant association.
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                    AxisValueLabel {
                        if let v = value.as(Double.self), maxVolume > 0, visibleRange > 0 {
                            let volume = ((v - yLower) / (visibleRange * 0.75)) * maxVolume
                            if volume >= 0 {
                                Text("\(Int(volume))")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color.volumeAccent)
                            }
                        }
                    }
                }
            }
        }
        .chartYAxisLabel(position: .leading, alignment: .center) {
            // Rotated −90° (counter-clockwise) so the unit reads bottom-to-top
            // beside the axis, the way scientific charts conventionally label
            // a vertical axis. Unit switches with mode.
            //
            // The explicit `.frame(width:height:)` AFTER the rotation is
            // critical — rotationEffect doesn't change layout bounds, so
            // Swift Charts would otherwise reserve a slot sized for the
            // un-rotated text (~22pt wide). The rotated rendering then
            // spills outside that slot and gets clipped by the parent's
            // cornerRadius on narrow layouts (the Home cards). The frame
            // swaps width/height so the rotated letters have a proper
            // bounding box.
            Text(isBodyweight ? "reps" : "lbs")
                .font(.neueMontrealSemiBold(size: 11))
                .foregroundColor(.textPrimary)
                .fixedSize()
                .rotationEffect(.degrees(-90))
                .frame(width: 14, height: 32)
        }
        .chartYAxisLabel(position: .trailing, alignment: .center) {
            // Matching "lbs" on the right axis so the Volume numbers are
            // unambiguous when the overlay is toggled on. Same rotation-
            // bounds treatment as the leading label.
            Text("lbs")
                .font(.neueMontrealSemiBold(size: 11))
                .foregroundColor(.textPrimary)
                .fixedSize()
                .rotationEffect(.degrees(-90))
                .frame(width: 14, height: 28)
                .opacity(showVolume ? 1 : 0)
        }
        // Simple opacity fade-in on appear. The previous mask-based line
        // draw-in was clipping axis labels (even after animation completed)
        // and hiding the dates — opacity is safer and still feels alive.
        .opacity(lineProgress)
        .chartOverlay { proxy in
            GeometryReader { geo in
                let plotRect = proxy.plotFrame.map { geo[$0] } ?? .zero
                // Custom x-axis date labels — positioned at each labeled
                // day's warped x-position so they line up with the dots
                // and gridlines.
                ForEach(labelDays, id: \.self) { day in
                    if let pos = dayToPosition[day], let xInPlot = proxy.position(forX: pos) {
                        VStack(spacing: 1) {
                            Text(Self.weekdayFormatter.string(from: day))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.textSecondary)
                            Text(Self.dayFormatter.string(from: day))
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.textPrimary)
                        }
                        .fixedSize()
                        .position(
                            x: plotRect.minX + xInPlot,
                            y: plotRect.maxY + 18
                        )
                    }
                }
            }
        }
        .onAppear {
            lineProgress = 0
            withAnimation(.easeOut(duration: 0.9)) {
                lineProgress = 1
            }
        }
    }

    // MARK: - Axis Label Formatters

    /// Short weekday ("Thu"). Cached on the type so the axis closure doesn't
    /// rebuild a DateFormatter on every tick.
    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    /// Month/day pair ("5/4"). Stacked under the weekday so each tick reads
    /// as "Mon / 5/4" — gives the user month context when the chart spans
    /// more than a few weeks without printing a full year.
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f
    }()

    // MARK: - Axis Helpers

    /// Returns the days to use as x-axis tick values. Each session gets an
    /// equal-width slot on the x-axis, so clustering by date is no longer
    /// a labeling concern — this function just caps at ~6 labels so long
    /// histories don't stack unreadable date columns.
    private func thinnedAxisDays(points: [DailyProgressPoint]) -> [Date] {
        let days = points.map { $0.day }
        let maxLabels = 6
        guard days.count > maxLabels else { return days }
        let step = Int(ceil(Double(days.count) / Double(maxLabels)))
        var result: [Date] = []
        for (idx, day) in days.enumerated() where idx % step == 0 {
            result.append(day)
        }
        // Always keep the last day so the latest lift is labeled.
        if let last = days.last, result.last != last {
            result.append(last)
        }
        return result
    }

    // MARK: - Aggregation

    /// Collapses the raw set logs into one `DailyProgressPoint` per calendar
    /// day. Days with no qualifying data are skipped. PR flag is computed
    /// in a single forward pass so the chart can highlight new-high days.
    ///
    /// - Weighted mode: a set must have both weight > 0 and reps > 0 to count.
    ///   Top metric = Epley e1RM of the max-tonnage set.
    ///   Volume = Σ(weight × reps).
    /// - Bodyweight mode: a set just needs reps > 0 (weight is irrelevant).
    ///   Top metric = max reps in a single set.
    ///   Volume = (Σ reps across all sets) × user bodyweight.
    private func dailyPoints() -> [DailyProgressPoint] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: setLogs) { log in
            calendar.startOfDay(for: log.timestamp)
        }

        // Fetched once per render — the user's bodyweight only matters in
        // bodyweight mode, but reading it is cheap so we always cache it.
        let bodyweight = UserManager.shared.getCurrentBodyweight()

        // Raw per-day aggregates (pre-PR flagging).
        struct Raw { let day: Date; let topMetric: Double; let volume: Double }

        let raw: [Raw] = grouped.compactMap { (day, logs) -> Raw? in
            if isBodyweight {
                // Bodyweight: we only care about rep counts.
                let reps = logs.compactMap { log -> Int? in
                    guard let r = log.reps, r > 0 else { return nil }
                    return r
                }
                guard let topReps = reps.max() else { return nil }
                let totalReps = reps.reduce(0, +)
                let volume = Double(totalReps) * bodyweight
                return Raw(day: day, topMetric: Double(topReps), volume: volume)
            } else {
                // Weighted: need both weight and reps for each counted set.
                let candidates = logs.compactMap { log -> (w: Double, r: Int)? in
                    guard let w = log.weight, w > 0, let r = log.reps, r > 0 else { return nil }
                    return (w, r)
                }
                guard !candidates.isEmpty else { return nil }
                // Top set = max tonnage; Epley e1RM on that set.
                let top = candidates.max(by: { ($0.w * Double($0.r)) < ($1.w * Double($1.r)) })!
                let e1rm = top.w * (1.0 + Double(top.r) / 30.0)
                let volume = candidates.reduce(0.0) { $0 + ($1.w * Double($1.r)) }
                return Raw(day: day, topMetric: e1rm, volume: volume)
            }
        }.sorted { $0.day < $1.day }

        return raw.map { row in
            DailyProgressPoint(
                day: row.day,
                topMetric: row.topMetric,
                volume: row.volume
            )
        }
    }
}

// MARK: - Per-Set History Card

/// A single logged set, rendered as a rounded card. Matches the structure the
/// user asked to revert to: left column shows the full timestamp and the set
/// number, right column shows weight and reps with their units, and the
/// saved coaching cue sits underneath as a small line when present.
///
/// Two additions on top of that base layout:
/// - A pencil button on the trailing edge signals that the values are
///   editable and expands an inline weight/reps editor, so mistakes from
///   the rep-counting algorithm or a mistyped weight can be corrected.
/// - Sets logged today (the workout the user just finished) get a purple
///   border, a tinted fill, and a "TODAY" badge so they stand out from
///   older history.
private struct HistoryRow: View {
    let setLog: ExerciseSetLog
    /// True when this set was logged today — drives the just-completed
    /// highlight treatment (purple border + tinted fill + TODAY badge).
    let isToday: Bool
    /// Persists an edit. The parent owns the Firestore write and the local
    /// state update; it calls the completion with false when the write
    /// fails so the row can surface the error and stay in edit mode.
    let onSave: (_ weight: Double?, _ reps: Int, _ completion: @escaping (Bool) -> Void) -> Void

    @State private var isEditing = false
    @State private var weightText: String = ""
    @State private var repsText: String = ""
    @State private var isSaving = false
    @State private var saveFailed = false

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }

    // MARK: - Edit Validation

    private var trimmedWeight: String {
        weightText.trimmingCharacters(in: .whitespaces)
    }

    private var repsValue: Int? {
        Int(repsText.trimmingCharacters(in: .whitespaces))
    }

    /// Reps must be a positive number (the history list only shows sets
    /// with reps > 0, so saving 0 would make the row vanish). Weight may
    /// be left empty for bodyweight sets, but if present must parse.
    private var isValid: Bool {
        guard let reps = repsValue, reps > 0, reps <= 999 else { return false }
        if trimmedWeight.isEmpty { return true }
        guard let weight = Double(trimmedWeight), weight >= 0, weight <= 5000 else { return false }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                // Date + set number
                VStack(alignment: .leading, spacing: 4) {
                    Text(dateFormatter.string(from: setLog.timestamp))
                        .font(.neueMontrealRegular(size: 12))
                        .foregroundColor(.textSecondary)

                    HStack(spacing: 6) {
                        Text("Set \(setLog.setNumber)")
                            .font(.neueMontrealSemiBold(size: 14))
                            .foregroundColor(.textPrimary)

                        if isToday {
                            Text("TODAY")
                                .font(.neueMontrealSemiBold(size: 9))
                                .foregroundColor(.textPrimary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.primaryPurple))
                        }
                    }
                }

                Spacer()

                // Weight and reps, each with its unit label beside the number.
                HStack(spacing: 16) {
                    if let weight = setLog.weight {
                        HStack(spacing: 4) {
                            Text(String(format: "%.1f", weight))
                                .font(.neueMontrealBold(size: 16))
                                .foregroundColor(.textPrimary)
                            Text("lbs")
                                .font(.neueMontrealRegular(size: 12))
                                .foregroundColor(.textSecondary)
                        }
                    }

                    if let reps = setLog.reps {
                        HStack(spacing: 4) {
                            Text("\(reps)")
                                .font(.neueMontrealBold(size: 16))
                                .foregroundColor(.textPrimary)
                            Text("reps")
                                .font(.neueMontrealRegular(size: 12))
                                .foregroundColor(.textSecondary)
                        }
                    }
                }
                // Dim the stored values while the editor is open so the
                // fields below read as "the new values".
                .opacity(isEditing ? 0.35 : 1)

                // Flags render on the trailing edge when the user flagged
                // pain or a loss of control for this set.
                HStack(spacing: 8) {
                    if setLog.flaggedPain {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.expertRed)
                    }
                    if setLog.flaggedNotInControl {
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.intermediateYellow)
                    }
                }

                // Always-visible pencil — the affordance telling users the
                // weight/reps on this set can be corrected. Toggles into an
                // X while the editor is open.
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if isEditing {
                            isEditing = false
                        } else {
                            beginEdit()
                        }
                    }
                } label: {
                    // Matches the app-wide edit affordance (square.and.pencil
                    // in primaryPurple, as used on TrainingProfileCard and the
                    // Home goal card). Toggles to an X while the editor is open.
                    Image(systemName: isEditing ? "xmark" : "square.and.pencil")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(isEditing ? .textSecondary : .primaryPurple)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
                .accessibilityLabel(isEditing ? "Cancel editing" : "Edit weight and reps")
            }

            // Inline editor — expands under the main row so the card keeps
            // its shape. Two fields + Save; validation gates the button.
            if isEditing {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        editField(title: "Weight (lbs)", text: $weightText, keyboard: .decimalPad)
                        editField(title: "Reps", text: $repsText, keyboard: .numberPad)
                        Spacer()

                        Button {
                            save()
                        } label: {
                            Text(isSaving ? "Saving…" : "Save")
                                .font(.neueMontrealSemiBold(size: 14))
                                .foregroundColor(.textPrimary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 9)
                                .background(
                                    Capsule().fill(
                                        isValid && !isSaving
                                            ? Color.primaryPurple
                                            : Color.white.opacity(0.08)
                                    )
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(!isValid || isSaving)
                    }

                    if saveFailed {
                        Text("Couldn't save changes. Check your connection and try again.")
                            .font(.neueMontrealRegular(size: 12))
                            .foregroundColor(.expertRed)
                    }
                }
                .padding(.top, 4)
            }

            // Saved coaching cue / note for the set (if any). Rendered under
            // the main row so it doesn't push the metrics around.
            if let cues = setLog.cues, !cues.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "quote.bubble")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.textSecondary)
                    Text(cues)
                        .font(.neueMontrealRegular(size: 13))
                        .foregroundColor(.textSecondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(16)
        // Today's sets get a tinted fill + purple border so the workout the
        // user just finished is visually separated from older history.
        .background(isToday ? Color.primaryPurple.opacity(0.12) : Color.white.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primaryPurple.opacity(isToday ? 0.6 : 0), lineWidth: 1.5)
        )
    }

    // MARK: - Edit Helpers

    private func editField(title: String, text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.neueMontrealRegular(size: 11))
                .foregroundColor(.textSecondary)
            TextField("", text: text)
                .keyboardType(keyboard)
                .font(.neueMontrealBold(size: 16))
                .foregroundColor(.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(width: title.hasPrefix("Weight") ? 92 : 64)
                .background(Color.white.opacity(0.08))
                .cornerRadius(8)
        }
    }

    /// Prefills the fields from the stored values. Whole-number weights
    /// prefill without the trailing ".0" so the field is pleasant to edit.
    private func beginEdit() {
        if let weight = setLog.weight {
            weightText = weight == floor(weight) ? "\(Int(weight))" : String(format: "%.1f", weight)
        } else {
            weightText = ""
        }
        repsText = setLog.reps.map(String.init) ?? ""
        saveFailed = false
        isEditing = true
    }

    private func save() {
        guard let reps = repsValue else { return }
        let weight = trimmedWeight.isEmpty ? nil : Double(trimmedWeight)
        isSaving = true
        saveFailed = false
        onSave(weight, reps) { success in
            isSaving = false
            if success {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isEditing = false
                }
            } else {
                saveFailed = true
            }
        }
    }
}

#Preview {
    ExerciseHistorySheet(
        isPresented: .constant(true),
        exerciseName: "Barbell Back Squat"
    )
}
