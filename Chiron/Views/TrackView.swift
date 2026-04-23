//
//  TrackView.swift
//  Chiron
//
//  Full-screen camera view for the Track tab. Lets the user select an exercise,
//  frame themselves, then record sets with on-device pose analysis and OpenAI coaching.
//

import SwiftUI
import SwiftData
import AVFoundation

// MARK: - Sheet presentation (explicit types avoid Swift 6 / SDK inference issues)

private let trackLibrarySheetDetents: Set<PresentationDetent> = [
    PresentationDetent.large,
    PresentationDetent.fraction(0.65)
]

// MARK: - Track View State

enum TrackViewState {
    case idle      // Camera visible, no analysis, no exercise selected
    case armed     // Camera visible, exercise selected, framing overlay shown
    case tracking  // Pose analysis running, overlay hidden
}

// MARK: - Track View

struct TrackView: View {
    @Environment(\.modelContext) private var modelContext
    /// Same sort as `ExerciseLibraryView` — keypath + order avoids `SortDescriptor` overload ambiguity (Swift 6).
    @Query(sort: \Exercise.name, order: .forward) private var exercises: [Exercise]

    @State private var trackViewState: TrackViewState = .idle
    @State private var selectedExercise: Exercise?
    @State private var setsCompletedInSession: Int = 0
    /// Short coaching cue from the last completed set's primary form deviation.
    @State private var primaryCueText: String?

    @State private var showExerciseSelector = false
    @State private var showExerciseInfo = false
    /// Pose detection overlay enabled by default; toggled via stick figure button in top-left.
    @State private var showPoseOverlay = true
    /// When true, body re-renders so the preview representable receives the session (created in onAppear).
    @State private var cameraSessionReady = false
    /// Pulsing scale for the tracking form score circle (matches WorkoutActiveView formScoreIndicator).
    @State private var trackingPulseScale: CGFloat = 1.0
    /// Sheet detent selection so exercise selector opens at full height (top of screen).
    @State private var exerciseSelectorDetent: PresentationDetent = PresentationDetent.large
    /// Sheet detent selection so info sheet opens at full height (top of screen).
    @State private var infoSheetDetent: PresentationDetent = PresentationDetent.large
    /// Share sheet for debug CSV export after a set ends.
    @State private var showDebugCSVShare: Bool = false
    @State private var debugCSVURL: URL?
    /// Snapshot of the view state captured when the info sheet opens so we can restore pose
    /// tracking / rep counting to the exact mode that was running before the sheet paused the camera.
    @State private var trackViewStateBeforeInfoSheet: TrackViewState?

    // MARK: - Weight / History Logging State

    /// Weight the user has dialed in for the current set (persists across sets
    /// of the same exercise so they don't re-enter it every time).
    @State private var currentWeight: Double?
    /// Presentation toggle for the scroller-based weight picker.
    @State private var showWeightScroller: Bool = false
    /// Presentation toggle for the Firestore-backed exercise history sheet.
    @State private var showHistorySheet: Bool = false
    /// Firestore workout-log document id for this Track session. Created lazily
    /// on the first saved set and reused for subsequent sets in this session.
    @State private var trackWorkoutLogId: String?
    /// Per-exercise set counter so saved logs get sequential setNumbers.
    @State private var setNumbersByExercise: [String: Int] = [:]

    @ObservedObject private var cameraManager = SharedCameraSessionManager.shared
    /// Rep count is published here; `cameraManager` alone does not trigger redraws when reps change.
    @ObservedObject private var poseManager = OnDevicePoseManager.shared
    @ObservedObject private var coachingManager = OpenAICoachingManager.shared

    private let lastTrackedExerciseKey = "lastTrackedExerciseName"

    var body: some View {
        ZStack {
            // Black backdrop — visible whenever the camera preview is detached.
            // AVCaptureVideoPreviewLayer keeps its last captured frame on screen after
            // `stopRunning()`, so pausing the session alone isn't enough to stop displaying
            // the user behind the info sheet. Passing `nil` to the representable routes to
            // `clearSession()`, which detaches the layer's session and hides it.
            Color.black
                .ignoresSafeArea()

            TrackCameraPreviewRepresentable(
                session: (showExerciseInfo || showExerciseSelector || showHistorySheet) ? nil : cameraManager.getCaptureSession()
            )
            .ignoresSafeArea()

            if showPoseOverlay && !showExerciseInfo && !showExerciseSelector && !showHistorySheet {
                PoseVisualizationOverlay()
                    .allowsHitTesting(false)
            }

            // Top bar: exercise selector pill (centered) and info button (trailing). Uses ZStack so
            // the pill stays geometrically centered; the info button is overlaid and does not shift center.
            VStack {
                GeometryReader { geometry in
                    let screenWidth = geometry.size.width
                    // Reserve space so the pill never overlaps the info button or overlay toggle.
                    let trailingReserved: CGFloat = 120
                    let leadingReserved: CGFloat = 60
                    let pillMaxWidth = min(320, max(0, screenWidth - trailingReserved - leadingReserved))

                    ZStack(alignment: .center) {
                        // Leading: pose overlay toggle
                        HStack {
                            /// Pose detection overlay toggle. Always shows stick figure icon;
                            /// icon color indicates active state (green when on, gray when off).
                            Button {
                                showPoseOverlay.toggle()
                            } label: {
                                Image(systemName: "figure.stand")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(showPoseOverlay ? .green : .textPrimary)
                                    .frame(width: 40, height: 40)
                                    .background(Color.black.opacity(0.3))
                                    .clipShape(Circle())
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 20)

                        HStack {
                            Spacer(minLength: 0)
                            if trackViewState == .tracking {
                                TrackFormScoreTrackingView(
                                    repCount: poseManager.repCount,
                                    trackingPulseScale: $trackingPulseScale
                                )
                            } else {
                                Button {
                                    showExerciseSelector = true
                                } label: {
                                    HStack(alignment: .center, spacing: 6) {
                                        Text(selectedExercise?.name ?? "Select Exercise")
                                            .font(.title3.weight(.semibold))
                                            .foregroundColor(.textPrimary)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.center)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Image(systemName: "chevron.down")
                                            .font(.headline.weight(.semibold))
                                            .foregroundColor(.textSecondary)
                                    }
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 12)
                                    .frame(maxWidth: pillMaxWidth)
                                    .background(Color.black.opacity(0.3))
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 20)

                        HStack {
                            Spacer()
                            if selectedExercise != nil {
                                Button {
                                    showExerciseInfo = true
                                } label: {
                                    Image(systemName: "info.circle")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundColor(.textPrimary)
                                        .frame(width: 40, height: 40)
                                        .background(Color.black.opacity(0.3))
                                        .clipShape(Circle())
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
                .frame(height: trackViewState == .tracking ? 112 : 72)
                .padding(.top, 8)

                Spacer()
            }

            // Primary coaching cue — appears when OpenAI feedback arrives, fades on Begin Next.
            // Centered card with opaque purple background, legible against any gym background.
            // Placed at the parent ZStack level so it sits in the direct middle of the track view.
            if trackViewState == .armed, let cueText = primaryCueText {
                Text(cueText)
                    .font(.title2.weight(.bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 18)
                    .background(Color.primaryPurple, in: RoundedRectangle(cornerRadius: 20))
                    .padding(.horizontal, 24)
                    .transition(.opacity.animation(.easeInOut(duration: 0.35)))
            }

            // Framing overlay + message bar + action button
            VStack {
                Spacer()

                if trackViewState == .armed && setsCompletedInSession == 0 {
                    FramingOverlayView()
                        .transition(.opacity)
                }

                Spacer()

                if trackViewState == .armed && setsCompletedInSession == 0 {
                    // Message bar (compact)
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.yellow)
                        Text("Position your full body in frame")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.textPrimary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.6), in: Capsule())
                    .padding(.bottom, 12)
                    .transition(.opacity)
                }

                // Weight + History row. Always rendered above the primary
                // action so the user can set weight or check history before a
                // set (armed), between sets, or while tracking.
                if (trackViewState == .armed || trackViewState == .tracking) && selectedExercise != nil {
                    HStack(spacing: 12) {
                        // Weight input is hidden for bodyweight exercises — there's
                        // nothing to log, and showing the button would be confusing.
                        // When hidden, the History button keeps its right-aligned
                        // position (same size/placement as on other exercises)
                        // instead of stretching across the row.
                        if !isCurrentExerciseBodyweight {
                            Button {
                                showWeightScroller = true
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "dumbbell.fill")
                                        .font(.system(size: 15, weight: .semibold))
                                    Text(weightButtonLabel)
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                }
                                .foregroundColor(.textPrimary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(Color.black.opacity(0.55))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        } else {
                            // Keep the right-hand button anchored to the right
                            // by filling the left half with an invisible spacer.
                            Spacer()
                                .frame(maxWidth: .infinity)
                        }

                        Button {
                            showHistorySheet = true
                        } label: {
                            HStack(spacing: 8) {
                                Text("History")
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundColor(.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Color.black.opacity(0.55))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 10)
                    .transition(.opacity)
                }

                // Primary action button (matches app primary button proportions)
                if trackViewState == .armed || trackViewState == .tracking {
                    Button {
                        handlePrimaryAction()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: trackViewState == .tracking ? "stop.fill" : "sparkles")
                                .font(.headline)
                            Text(primaryButtonLabel)
                                .font(.headline.weight(.semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            trackViewState == .tracking
                                ? Color.red
                                : Color.primaryPurple
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 28))
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, trackViewState == .tracking ? 8 : 30)
                    .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: trackViewState)
        .toolbar(trackViewState == .tracking ? .hidden : .visible, for: .tabBar)
        .navigationBarHidden(true)
        .onAppear(perform: onAppear)
        .onDisappear(perform: onDisappear)
        .sheet(isPresented: $showExerciseSelector) {
            TrackExerciseLibrarySheetView(
                selectedExercise: selectedExercise,
                onExerciseSelected: { exercise in
                    didSelectExercise(exercise)
                    showExerciseSelector = false
                }
            )
            .presentationDetents(trackLibrarySheetDetents, selection: $exerciseSelectorDetent)
            .presentationDragIndicator(Visibility.visible)
            .onAppear { exerciseSelectorDetent = PresentationDetent.large }
        }
        .sheet(isPresented: $showExerciseInfo) {
            if let exercise = selectedExercise {
                NavigationStack {
                    ExerciseInfoSheetContent(exercise: exercise)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { showExerciseInfo = false }
                            }
                        }
                }
                .presentationDetents(trackLibrarySheetDetents, selection: $infoSheetDetent)
                .presentationDragIndicator(Visibility.visible)
                .onAppear { infoSheetDetent = PresentationDetent.large }
            }
        }
        // When either sheet (info or exercise selector) is open, pause the capture session
        // so the camera hardware stops drawing power behind it (the feed is occluded anyway).
        // Resume and restore pose tracking to the pre-sheet state on dismiss.
        .onChange(of: showExerciseInfo) { _, isShowing in
            if isShowing {
                trackViewStateBeforeInfoSheet = trackViewState
                cameraManager.pauseCaptureSession()
            } else {
                // Only resume if no other sheet is still occluding the feed.
                guard !showExerciseSelector, !showHistorySheet else { return }
                cameraManager.resumeCaptureSession()
                switch trackViewStateBeforeInfoSheet {
                case .tracking, .armed:
                    cameraManager.startPoseTrackingOnly()
                case .idle, nil:
                    break
                }
                trackViewStateBeforeInfoSheet = nil
            }
        }
        .onChange(of: showExerciseSelector) { _, isShowing in
            if isShowing {
                if trackViewStateBeforeInfoSheet == nil {
                    trackViewStateBeforeInfoSheet = trackViewState
                }
                cameraManager.pauseCaptureSession()
            } else {
                // Only resume if no other sheet is still occluding the feed.
                guard !showExerciseInfo, !showHistorySheet else { return }
                cameraManager.resumeCaptureSession()
                switch trackViewStateBeforeInfoSheet {
                case .tracking, .armed:
                    cameraManager.startPoseTrackingOnly()
                case .idle, nil:
                    break
                }
                trackViewStateBeforeInfoSheet = nil
            }
        }
        // History sheet fully covers the feed — pause the capture session
        // while it's open so the camera hardware stops drawing power. Mirrors
        // the behavior of the info / exercise-selector sheets above.
        .onChange(of: showHistorySheet) { _, isShowing in
            if isShowing {
                if trackViewStateBeforeInfoSheet == nil {
                    trackViewStateBeforeInfoSheet = trackViewState
                }
                cameraManager.pauseCaptureSession()
            } else {
                guard !showExerciseInfo, !showExerciseSelector else { return }
                cameraManager.resumeCaptureSession()
                switch trackViewStateBeforeInfoSheet {
                case .tracking, .armed:
                    cameraManager.startPoseTrackingOnly()
                case .idle, nil:
                    break
                }
                trackViewStateBeforeInfoSheet = nil
            }
        }
        .sheet(isPresented: $showDebugCSVShare) {
            if let url = debugCSVURL {
                SquatRepShareSheet(url: url)
            }
        }
        .sheet(isPresented: $showWeightScroller) {
            WeightScrollerSheet(
                isPresented: $showWeightScroller,
                initialWeight: currentWeight,
                onSave: { weight in
                    // Local-only update. Firestore is not written here —
                    // the set log (weight + reps + date/time + cues) is
                    // persisted exclusively from `endSet` when the user
                    // presses End Set, so the history sheet only ever sees
                    // completed sets.
                    currentWeight = weight
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showHistorySheet) {
            if let exercise = selectedExercise {
                ExerciseHistorySheet(
                    isPresented: $showHistorySheet,
                    exerciseName: exercise.name,
                    isBodyweight: isCurrentExerciseBodyweight
                )
                .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Computed

    /// True when the currently selected exercise is a bodyweight movement (no
    /// external load to record). Matches the `.bodyweight` branch of
    /// `TrackedExerciseType.from(exerciseName:)` below.
    private var isCurrentExerciseBodyweight: Bool {
        guard let name = selectedExercise?.name else { return false }
        return TrackedExerciseType.from(exerciseName: name) == .bodyweight
    }

    /// Label for the weight pill: "Weight" when unset, or the formatted value
    /// with unit (e.g. "185 lbs") once the user has dialed in a weight.
    private var weightButtonLabel: String {
        guard let weight = currentWeight else { return "Weight" }
        let formatted: String
        if weight.truncatingRemainder(dividingBy: 1) == 0 {
            formatted = String(format: "%.0f", weight)
        } else {
            formatted = String(format: "%.1f", weight)
        }
        return "\(formatted) lbs"
    }

    private var primaryButtonLabel: String {
        switch trackViewState {
        case .tracking:
            return "End Set"
        case .armed:
            return setsCompletedInSession > 0 ? "Begin Another Set" : "Begin Set"
        case .idle:
            return "Begin Set"
        }
    }


    // MARK: - Actions

    private static let beginSetAffirmations: [String] = [
        "Let's get it!",
        "Let's go!",
        "You've got this!",
        "Time to work!",
        "Let's crush it!",
        "Make it count!"
    ]
    private static var beginSetAffirmationIndex: Int = 0

    private static func nextBeginSetAffirmation() -> String {
        let phrase = beginSetAffirmations[beginSetAffirmationIndex % beginSetAffirmations.count]
        beginSetAffirmationIndex += 1
        return phrase
    }

    private func exitTrackView() {
        if trackViewState == .tracking {
            cameraManager.stopPoseAnalysis()
        }
        cameraManager.suppressRepCounting = false
        cameraManager.trackExplicitSetActive = false
        trackViewState = .idle
        selectedExercise = nil
        setsCompletedInSession = 0
        primaryCueText = nil
    }

    private func handlePrimaryAction() {
        switch trackViewState {
        case .armed:
            beginSet()
        case .tracking:
            endSet()
        case .idle:
            break
        }
    }

    private func beginSet() {
        guard let exercise = selectedExercise else { return }

        // Capture the prior set's cue before clearing it so it can be spoken.
        let cueToSpeak = primaryCueText

        // Fade the previous set's cue out as the user starts the next set.
        if primaryCueText != nil {
            withAnimation(.easeInOut(duration: 0.35)) {
                primaryCueText = nil
            }
        }

        // First set of each exercise: framing reminder + affirmation.
        // Subsequent sets: supportive phrase followed by the prior set's cue.
        if setsCompletedInSession == 0 {
            SpeechManager.shared.speak(
                "Ensure your full body is in frame. \(Self.nextBeginSetAffirmation())",
                priority: .high,
                context: .instruction
            )
        } else if let cue = cueToSpeak {
            SpeechManager.shared.speak(
                "\(Self.nextBeginSetAffirmation()) \(cue).",
                priority: .high,
                context: .instruction
            )
        }

        let exerciseType = TrackedExerciseType.from(exerciseName: exercise.name)
        cameraManager.poseManager.trackedExerciseType = exerciseType
        // Keep pose pipeline on (already from `startPoseTrackingOnly`) without `startPoseAnalysis()`, which
        // calls `resetRepCountingState()` and async-sets `workoutState = .waiting` — that can race after
        // `startManualSet()` and break rep/set state.
        if !cameraManager.isAnalyzingPose {
            cameraManager.startPoseTrackingOnly()
        }
        cameraManager.poseManager.resetRepCount()
        cameraManager.poseManager.startManualSet()
        // Start debug logging for this set (auto-exported as CSV when the set ends).
        SquatRepDebugLogger.shared.reset()
        poseManager.debugLoggerEnabled = true
        // Suppress rep counting for 1 second so the user can step back from the camera
        // after pressing the button. Without this delay, the pose detector may see a
        // partial/close-up pose and erroneously count a rep during the transition.
        cameraManager.suppressRepCounting = true
        cameraManager.trackExplicitSetActive = true
        trackViewState = .tracking
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak cameraManager] in
            cameraManager?.suppressRepCounting = false
        }
    }

    private func endSet() {
        // Do not call `stopPoseAnalysis()` here — it clears `isAnalyzingPose` and freezes the overlay until the next set.
        cameraManager.trackExplicitSetActive = false
        cameraManager.suppressRepCounting = true

        // Retroactive phantom-rep filter: remove the last counted rep if it was
        // validated within 3 seconds of pressing End Set (likely the user reaching
        // toward the phone, not an actual squat).
        poseManager.retroactiveEndSetFilter(window: 3.0)

        cameraManager.endTrackSetKeepingPoseActive()
        trackViewState = .armed

        // Stop debug logging and export CSV for analysis.
        poseManager.debugLoggerEnabled = false
        // exportDebugCSV()  // Disabled to prevent debug CSV share sheet after set completion

        // If no reps were completed, treat the set as if it never happened:
        // skip analysis, audio feedback, and session bookkeeping.
        guard poseManager.repCount > 0 else { return }

        setsCompletedInSession += 1

        let formAnalysis = cameraManager.poseManager.currentFormAnalysis
            ?? cameraManager.poseManager.lastRepFormAnalysis

        // Compute the short coaching cue synchronously so it can be written
        // alongside the set log. The OpenAI callback below still governs when
        // the cue text fades in on screen / is spoken.
        var resolvedShortCue: String? = nil
        if let analysis = formAnalysis, let exercise = selectedExercise {
            let exerciseType = TrackedExerciseType.from(exerciseName: exercise.name)
            let payload = CoachingLogic.buildPayload(from: analysis, exerciseType: exerciseType)
            resolvedShortCue = payload.primaryIssue.map { CoachingContract.shortCue(for: $0) }
        }

        // Single Firestore write for this set — weight, reps, timestamp
        // (date/time), and cues/notes. This is the only path that pushes
        // data to Firebase from the Track tab; the History sheet reads back
        // from the same collection.
        if let exercise = selectedExercise {
            saveCompletedSetToFirestore(
                exerciseName: exercise.name,
                weight: currentWeight,
                reps: poseManager.repCount,
                cues: resolvedShortCue
            )
        }

        if let analysis = formAnalysis, let exercise = selectedExercise {
            let exerciseType = TrackedExerciseType.from(exerciseName: exercise.name)
            coachingManager.analyzeAndGetNaturalFeedback(
                formAnalysis: analysis,
                exerciseType: exerciseType
            ) { feedback in
                SpeechManager.shared.speak(feedback)
                // Fade the cue text in at the same moment the spoken feedback arrives.
                if let cue = resolvedShortCue {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        primaryCueText = cue
                    }
                }
            }
        }

        persistLastTrackedExercise()
    }

    private func didSelectExercise(_ exercise: Exercise) {
        let exerciseChanged = exercise.name != selectedExercise?.name
        selectedExercise = exercise
        persistLastTrackedExercise()
        if exerciseChanged {
            withAnimation(.easeInOut(duration: 0.25)) {
                setsCompletedInSession = 0
                primaryCueText = nil
            }
            // New exercise = new weight context. Keep setNumbersByExercise so
            // re-selecting an exercise resumes the same set numbering.
            currentWeight = nil
        }
        if trackViewState == .idle {
            trackViewState = .armed
        }
    }

    // MARK: - Lifecycle

    private func onAppear() {
        cameraManager.setupCameraSession()
        // Other flows call `switchToSetupMode()`; re-selecting this tab does not always rerun `onAppear`, so `RootTabView` also calls `switchToWorkoutMode` when Track is selected.
        cameraManager.switchToWorkoutMode()
        if let session = cameraManager.getCaptureSession(), !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
            }
        }
        cameraSessionReady = true
        // Start pose tracking immediately so overlay/smoothing run before user presses Begin Set.
        cameraManager.suppressRepCounting = true
        cameraManager.startPoseTrackingOnly()
        restoreLastTrackedExercise()
    }

    private func onDisappear() {
        cameraManager.suppressRepCounting = false
        cameraManager.trackExplicitSetActive = false
        if trackViewState == .tracking {
            cameraManager.stopPoseAnalysis()
            trackViewState = .armed
        }
    }

    // MARK: - Debug CSV Export

    private func exportDebugCSV() {
        let logger = SquatRepDebugLogger.shared
        guard !logger.allFrames.isEmpty else { return }
        let csv = logger.exportCSV()
        let fileName = "squat_debug_\(Int(Date().timeIntervalSince1970)).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try csv.data(using: .utf8)?.write(to: url)
            debugCSVURL = url
            showDebugCSVShare = true
        } catch {
            // Silently fail — debug export is best-effort.
        }
    }

    // MARK: - Persistence

    private func persistLastTrackedExercise() {
        if let name = selectedExercise?.name {
            UserDefaults.standard.set(name, forKey: lastTrackedExerciseKey)
        }
    }

    private func restoreLastTrackedExercise() {
        guard selectedExercise == nil else { return }
        if let savedName = UserDefaults.standard.string(forKey: lastTrackedExerciseKey),
           let match = exercises.first(where: { $0.name == savedName }) {
            selectedExercise = match
            trackViewState = .armed
        }
    }

    // MARK: - Firestore Logging

    /// Persists a completed set (weight + rep count + timestamp + cues) to
    /// Firestore. This is the single write path from the Track tab — called
    /// only from `endSet` after rep count is confirmed. The History sheet
    /// pulls from the same collection, so nothing shows up there until an
    /// End Set completes.
    private func saveCompletedSetToFirestore(exerciseName: String, weight: Double?, reps: Int, cues: String?) {
        ensureWorkoutLogId { workoutLogId in
            let userId = UserManager.shared.getUserId()
            let setNumber = setNumbersByExercise[exerciseName] ?? 1

            WorkoutLogService.shared.saveSetLog(
                workoutLogId: workoutLogId,
                userId: userId,
                exerciseName: exerciseName,
                setNumber: setNumber,
                weight: weight,
                reps: reps,
                flaggedPain: false,
                flaggedNotInControl: false,
                cues: cues
            ) { result in
                DispatchQueue.main.async {
                    if case .success = result {
                        setNumbersByExercise[exerciseName] = setNumber + 1
                    }
                }
            }
        }
    }

    /// Creates the Track-session workoutLog the first time a set is saved,
    /// then reuses the returned document id for the rest of the session.
    private func ensureWorkoutLogId(_ onReady: @escaping (String) -> Void) {
        if let existing = trackWorkoutLogId {
            onReady(existing)
            return
        }
        let userId = UserManager.shared.getUserId()
        WorkoutLogService.shared.createWorkoutLog(
            workoutName: "Track Session",
            userId: userId
        ) { result in
            DispatchQueue.main.async {
                if case .success(let logId) = result {
                    trackWorkoutLogId = logId
                    onReady(logId)
                }
            }
        }
    }
}

// MARK: - TrackedExerciseType Mapping

extension TrackedExerciseType {
    static func from(exerciseName: String) -> TrackedExerciseType {
        let lower = exerciseName.lowercased()
        if lower.contains("barbell back squat") || lower == "back squat" {
            return .barbell
        } else if lower.contains("bench press") && lower.contains("close") {
            return .closeGripBenchPress
        } else if lower.contains("bench press") {
            return .benchPress
        } else if lower.contains("barbell row") || lower.contains("bent-over row") || lower.contains("bent over row") {
            return .row
        } else if lower.contains("romanian") || lower.contains("rdl") {
            return .romanianDeadlift
        } else if lower.contains("deadlift") {
            return .deadlift
        } else {
            return .bodyweight
        }
    }
}

// MARK: - Track Camera Preview (preview-only, no delegate)

struct TrackCameraPreviewRepresentable: UIViewRepresentable {
    var session: AVCaptureSession?

    func makeUIView(context: Context) -> TrackCameraPreviewUIView {
        let view = TrackCameraPreviewUIView()
        if let session = session {
            view.setSession(session)
        } else {
            view.clearSession()
        }
        return view
    }

    func updateUIView(_ uiView: TrackCameraPreviewUIView, context: Context) {
        if let session = session {
            uiView.setSession(session)
        } else {
            // Passing nil detaches the session so the preview layer stops rendering frames
            // (and the last-frame freeze is blanked) — used to go dark behind the Track info sheet.
            uiView.clearSession()
        }
    }
}

class TrackCameraPreviewUIView: UIView {
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    /// Attach the capture session to the preview. Called from the representable when the session becomes available (e.g. after onAppear).
    func setSession(_ session: AVCaptureSession) {
        if previewLayer != nil {
            previewLayer?.session = session
            previewLayer?.isHidden = false
            return
        }
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        self.layer.addSublayer(layer)
        previewLayer = layer
    }

    /// Detaches the capture session and hides the preview layer so the view renders nothing.
    /// Used when we want the preview to go dark without tearing the view down (e.g. info sheet open).
    func clearSession() {
        previewLayer?.session = nil
        previewLayer?.isHidden = true
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
}

// MARK: - Framing Overlay (rounded-rect corners)

struct FramingOverlayView: View {
    private let cornerLength: CGFloat = 40
    private let lineWidth: CGFloat = 3
    private let cornerRadius: CGFloat = 16
    private let color: Color = .white.opacity(0.7)

    var body: some View {
        GeometryReader { geo in
            // Center the frame between the exercise selection and Begin Set button; elongate vertically
            let overlayHeightFraction: CGFloat = 0.60
            let overlayWidthFraction: CGFloat = 0.72
            let centerYFraction: CGFloat = 0.50
            let topFraction = centerYFraction - overlayHeightFraction / 2
            let rect = CGRect(
                x: geo.size.width * (1 - overlayWidthFraction) / 2,
                y: geo.size.height * topFraction,
                width: geo.size.width * overlayWidthFraction,
                height: geo.size.height * overlayHeightFraction
            )
            ZStack {
                cornerPath(for: .topLeft, in: rect)
                cornerPath(for: .topRight, in: rect)
                cornerPath(for: .bottomLeft, in: rect)
                cornerPath(for: .bottomRight, in: rect)
            }
        }
        .allowsHitTesting(false)
    }

    private enum Corner { case topLeft, topRight, bottomLeft, bottomRight }

    private func cornerPath(for corner: Corner, in rect: CGRect) -> some View {
        Path { path in
            switch corner {
            case .topLeft:
                path.move(to: CGPoint(x: rect.minX, y: rect.minY + cornerLength))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cornerRadius))
                path.addQuadCurve(
                    to: CGPoint(x: rect.minX + cornerRadius, y: rect.minY),
                    control: CGPoint(x: rect.minX, y: rect.minY)
                )
                path.addLine(to: CGPoint(x: rect.minX + cornerLength, y: rect.minY))
            case .topRight:
                path.move(to: CGPoint(x: rect.maxX - cornerLength, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY))
                path.addQuadCurve(
                    to: CGPoint(x: rect.maxX, y: rect.minY + cornerRadius),
                    control: CGPoint(x: rect.maxX, y: rect.minY)
                )
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + cornerLength))
            case .bottomLeft:
                path.move(to: CGPoint(x: rect.minX, y: rect.maxY - cornerLength))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - cornerRadius))
                path.addQuadCurve(
                    to: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY),
                    control: CGPoint(x: rect.minX, y: rect.maxY)
                )
                path.addLine(to: CGPoint(x: rect.minX + cornerLength, y: rect.maxY))
            case .bottomRight:
                path.move(to: CGPoint(x: rect.maxX - cornerLength, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.maxX - cornerRadius, y: rect.maxY))
                path.addQuadCurve(
                    to: CGPoint(x: rect.maxX, y: rect.maxY - cornerRadius),
                    control: CGPoint(x: rect.maxX, y: rect.maxY)
                )
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerLength))
            }
        }
        .stroke(color, lineWidth: lineWidth)
    }
}

// MARK: - Track Form Score (tracking state only)

/// Live rep count during a Track set with blue pulsing ring (same visual language as form-score tracking).
struct TrackFormScoreTrackingView: View {
    var repCount: Int
    @Binding var trackingPulseScale: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.4))

            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 6)

            Circle()
                .stroke(Color.primaryPurple.opacity(0.75), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .scaleEffect(trackingPulseScale)
                .opacity(trackingPulseScale == 1.0 ? 0.8 : 1.0)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) {
                        trackingPulseScale = 1.08
                    }
                }
                .onDisappear {
                    trackingPulseScale = 1.0
                }

            VStack(spacing: 0) {
                Text("\(repCount)")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text("REPS")
                    .font(.neueMontrealBold(size: 11))
                    .foregroundColor(.white)
            }
        }
        .frame(width: 104, height: 104)
        .shadow(color: Color.primaryPurple.opacity(0.35), radius: 6)
    }
}

// MARK: - Track Exercise Library Sheet

/// Presents the shared exercise library in selection mode for the Track tab.
/// Owns a NavigationStack and search/category state so the sheet can be dismissed and reopened
/// without losing the user's search or filter. Tapping an exercise calls `onExerciseSelected`;
/// the parent is responsible for closing the sheet.
struct TrackExerciseLibrarySheetView: View {
    /// The exercise currently selected in Track; the library highlights this card (no checkmark).
    var selectedExercise: Exercise?
    var onExerciseSelected: (Exercise) -> Void

    @State private var sheetSearch: String = ""
    @State private var sheetCategory: String? = nil

    var body: some View {
        NavigationStack {
            ExerciseLibraryView(
                onExerciseSelected: onExerciseSelected,
                selectedForSelectionMode: selectedExercise,
                searchBinding: $sheetSearch,
                selectedCategoryBinding: $sheetCategory
            )
        }
    }
}

// MARK: - Exercise Info Sheet Content

struct ExerciseInfoSheetContent: View {
    let exercise: Exercise

    @StateObject private var bodyweightSquatVM = WorkoutViewModel()
    @StateObject private var barbellBackSquatVM = WorkoutViewModel()
    @StateObject private var deadliftVM = WorkoutViewModel()
    @StateObject private var barbellBenchPressVM = WorkoutViewModel()
    @StateObject private var romanianDeadliftVM = WorkoutViewModel()
    @StateObject private var barbellRowVM = WorkoutViewModel()

    var body: some View {
        destinationView(for: exercise)
    }

    @ViewBuilder
    private func destinationView(for exercise: Exercise) -> some View {
        let name = exercise.name
        if name.caseInsensitiveCompare("Bodyweight Squat") == .orderedSame {
            BodyweightSquatOverview(viewModel: bodyweightSquatVM)
        } else if name.caseInsensitiveCompare("Barbell Back Squat") == .orderedSame ||
                  name.caseInsensitiveCompare("Back Squat") == .orderedSame {
            BarbellBackSquatOverview(viewModel: barbellBackSquatVM)
        } else if name.caseInsensitiveCompare("Deadlift") == .orderedSame {
            DeadliftOverview(viewModel: deadliftVM)
        } else if name.caseInsensitiveCompare("Barbell Bench Press") == .orderedSame {
            BarbellBenchPressOverview(viewModel: barbellBenchPressVM)
        } else if name.caseInsensitiveCompare("Romanian Deadlift (RDL)") == .orderedSame {
            RomanianDeadliftOverview(viewModel: romanianDeadliftVM)
        } else if name.caseInsensitiveCompare("Barbell Row") == .orderedSame {
            BarbellRowOverview(viewModel: barbellRowVM)
        } else {
            ExerciseDetailPlaceholderView(exercise: exercise)
        }
    }
}
