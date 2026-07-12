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
import Combine

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
    /// Rotating index into `cleanSetAffirmations` so back-to-back clean sets
    /// don't repeat the same affirmation on the card / in history.
    @State private var cleanCueRotation: Int = 0

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
    /// Snapshot of the view state captured when the info sheet opens so we can restore pose
    /// tracking / rep counting to the exact mode that was running before the sheet paused the camera.
    @State private var trackViewStateBeforeInfoSheet: TrackViewState?
    /// Pending framing-reminder speech scheduled 2s after a dropdown exercise
    /// selection. Cancelled on re-selection or view disappear so navigation
    /// and quick re-picks don't trigger stale speech.
    @State private var pendingFramingSpeech: DispatchWorkItem?

    // MARK: - Weight / History Logging State

    /// Weight the user has dialed in for the current set (persists across sets
    /// of the same exercise so they don't re-enter it every time). Stays nil
    /// until the user saves a value in the weight picker — the button label
    /// shows "Weight" until that happens even if `suggestedWeight` is populated.
    @State private var currentWeight: Double?
    /// Most recently logged weight for the selected exercise, pulled from
    /// UserDefaults cache and refreshed from Firestore history. Used only to
    /// pre-fill the weight picker; it does NOT drive the weight button label
    /// so a freshly selected exercise still reads "Weight" until the user
    /// confirms a value.
    @State private var suggestedWeight: Double?
    /// Presentation toggle for the scroller-based weight picker.
    @State private var showWeightScroller: Bool = false
    /// Presentation toggle for the Firestore-backed exercise history sheet.
    @State private var showHistorySheet: Bool = false
    /// Firestore workout-log document id for this Track session. Created lazily
    /// on the first saved set and reused for subsequent sets in this session.
    @State private var trackWorkoutLogId: String?
    /// Per-exercise set counter so saved logs get sequential setNumbers.
    @State private var setNumbersByExercise: [String: Int] = [:]
    /// Wall-clock start of the current set. Captured in `beginSet` and read in
    /// `endSet` so the badge evaluator can credit Heavy Hour minutes without
    /// relying on workoutLog.endTime (Track sessions don't write one).
    @State private var currentSetStart: Date?

    /// Presentation toggle for the AI-tracking accuracy flag sheet (rep
    /// count off / coach feedback wrong / both-or-other). Distinct from the
    /// pain / not-in-control flag — different audience, different storage.
    @State private var showAccuracyFlagSheet: Bool = false
    /// Phase the flag was raised in. `.duringSet` snapshots live pose state,
    /// `.afterSet` replays the recorded end-of-set snapshot.
    @State private var accuracyFlagPhase: AccuracyFlagPhase = .afterSet

    @ObservedObject private var cameraManager = SharedCameraSessionManager.shared
    /// Rep count is published here; `cameraManager` alone does not trigger redraws when reps change.
    @ObservedObject private var poseManager = OnDevicePoseManager.shared
    @ObservedObject private var coachingManager = OpenAICoachingManager.shared

    private let lastTrackedExerciseKey = "lastTrackedExerciseName"
    /// UserDefaults key for the last-used weight per exercise, stored as
    /// `[exerciseName: Double]`. Survives app relaunches and exercise switches
    /// so the weight picker opens at the value the user last logged for that
    /// specific exercise.
    private let lastWeightByExerciseKey = "lastWeightByExercise"

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
                        // Leading: pose overlay toggle, tempo-coaching toggle stacked below it
                        HStack {
                            VStack(spacing: 10) {
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
                                /// Intra-set tempo-coaching toggle (eccentric + stretch-pause cues).
                                /// Green metronome when on, slashed + gray when off. Flipping it
                                /// rebuilds the coaching config immediately (takes effect this set).
                                Button {
                                    poseManager.intraSetTempoCoachingEnabled.toggle()
                                } label: {
                                    Image(systemName: poseManager.intraSetTempoCoachingEnabled ? "metronome.fill" : "metronome")
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundColor(poseManager.intraSetTempoCoachingEnabled ? .green : .textPrimary)
                                        .frame(width: 40, height: 40)
                                        .background(Color.black.opacity(0.3))
                                        .clipShape(Circle())
                                }
                                .accessibilityLabel("Tempo coaching")
                                .accessibilityValue(poseManager.intraSetTempoCoachingEnabled ? "On" : "Off")
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
                            VStack(spacing: 10) {
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
                                // Accuracy flag button — visible while the set is
                                // running (flag mid-set) and right after it ends
                                // (flag the just-completed set). The store knows
                                // which snapshot to read from `accuracyFlagPhase`.
                                if shouldShowAccuracyFlagButton {
                                    Button {
                                        accuracyFlagPhase = (trackViewState == .tracking) ? .duringSet : .afterSet
                                        showAccuracyFlagSheet = true
                                    } label: {
                                        Image(systemName: "flag.fill")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(.expertRed)
                                            .frame(width: 40, height: 40)
                                            .background(Color.black.opacity(0.3))
                                            .clipShape(Circle())
                                    }
                                    .accessibilityLabel("Flag this set")
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
        .onChange(of: trackViewState) { _, newValue in
            VolumeTriggerCoordinator.shared.setActive(newValue != .idle)
        }
        .onReceive(VolumeTriggerCoordinator.shared.$actionRequestCounter.dropFirst()) { _ in
            // Ignore Begin Set presses while the camera is paused (another tab is
            // selected, a sheet covers the preview, or a foreground resume is still in
            // flight) — otherwise a press from elsewhere begins a phantom set that
            // records zero frames against a stopped session. End Set (.tracking) is
            // always honored: mid-set the user must be able to close the set (and its
            // recording/telemetry/keep-alive) even during the async resume window
            // right after re-foregrounding.
            guard trackViewState == .tracking
                    || cameraManager.getCaptureSession()?.isRunning == true else { return }
            handlePrimaryAction()
        }
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
        .sheet(isPresented: $showWeightScroller) {
            WeightScrollerSheet(
                isPresented: $showWeightScroller,
                initialWeight: currentWeight ?? suggestedWeight,
                onSave: { weight in
                    // Local-only update. Firestore is not written here —
                    // the set log (weight + reps + date/time + cues) is
                    // persisted exclusively from `endSet` when the user
                    // presses End Set, so the history sheet only ever sees
                    // completed sets.
                    currentWeight = weight
                    if let name = selectedExercise?.name {
                        persistLastWeight(weight, for: name)
                    }
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
        .sheet(isPresented: $showAccuracyFlagSheet) {
            AccuracyFlagSheet(
                isPresented: $showAccuracyFlagSheet,
                phase: accuracyFlagPhase,
                onSubmitted: nil
            )
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

    /// True when there's something flagging-able on screen — a live set (`.tracking`)
    /// or a just-completed set being recapped (`.armed` with completed sets).
    /// The store separately decides whether it has data to send; the button just
    /// stays hidden in the dead states (no exercise picked, no set ever started).
    private var shouldShowAccuracyFlagButton: Bool {
        guard selectedExercise != nil else { return false }
        switch trackViewState {
        case .tracking:
            return true
        case .armed:
            return setsCompletedInSession > 0
        case .idle:
            return false
        }
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

    /// First-set-of-exercise intent cue: ties the user's primary goal to the
    /// exercise pattern they're about to train. Spoken before the affirmation
    /// on the first set only (subsequent sets speak the prior set's cue).
    /// Returns nil if the user has no goal set — caller falls back to just
    /// the affirmation.
    private static func firstSetGoalCue(for exerciseType: TrackedExerciseType) -> String? {
        guard let goal = UserPreferencesManager.shared.primaryGoal else { return nil }
        switch exerciseType {
        case .bodyweight, .barbell:
            return squatIntentCue(for: goal)
        case .benchPress, .closeGripBenchPress:
            return benchIntentCue(for: goal)
        case .deadlift:
            return deadliftIntentCue(for: goal)
        case .romanianDeadlift:
            return rdlIntentCue(for: goal)
        case .row:
            return rowIntentCue(for: goal)
        }
    }

    private static func squatIntentCue(for goal: PrimaryGoal) -> String {
        switch goal {
        case .buildMuscle:
            return "Sit deep and pause at the bottom — that stretch is where your muscle grows."
        case .getStronger:
            return "Brace hard, control the descent, drive through the floor."
        case .enhanceAthleticPerformance:
            return "Slow down, then explode up — this is your power builder."
        case .rehabPreventInjury:
            return "Move slow through the full range, no bouncing at the bottom."
        case .loseFat, .getToned:
            return "Steady pace, tight form, feel every rep."
        case .improveEndurance:
            return "Find a clean, repeatable rhythm for the whole set."
        case .improveHealthLongevity:
            return "Full range of motion, controlled all the way."
        }
    }

    private static func benchIntentCue(for goal: PrimaryGoal) -> String {
        switch goal {
        case .buildMuscle:
            return "Slow on the way down, pause at your chest — that's where the chest grows."
        case .getStronger:
            return "Lock in tight, control the bar down, press with intent."
        case .enhanceAthleticPerformance:
            return "Control down, press up fast and powerful."
        case .rehabPreventInjury:
            return "Smooth and controlled, no bouncing off your chest."
        case .loseFat, .getToned:
            return "Steady tempo, tight form, squeeze the chest on every press."
        case .improveEndurance:
            return "Clean reps at a consistent tempo."
        case .improveHealthLongevity:
            return "Full range of motion, move the bar with control."
        }
    }

    private static func deadliftIntentCue(for goal: PrimaryGoal) -> String {
        switch goal {
        case .buildMuscle:
            return "Control the descent and feel your back and legs loading up."
        case .getStronger:
            return "Push the floor away — this is your whole-body strength builder."
        case .enhanceAthleticPerformance:
            return "Explosive off the floor — hip drive is raw power."
        case .rehabPreventInjury:
            return "Set your back, move slow, keep the bar close to your body."
        case .loseFat, .getToned:
            return "Tight form, controlled pulls, whole-body engagement."
        case .improveEndurance:
            return "Repeatable clean reps — never sacrifice form."
        case .improveHealthLongevity:
            return "Neutral spine, smooth from the floor to lockout."
        }
    }

    private static func rdlIntentCue(for goal: PrimaryGoal) -> String {
        switch goal {
        case .buildMuscle:
            return "Hinge deep and feel that hamstring stretch — let it load the muscle."
        case .getStronger:
            return "Control the hinge, load the hamstrings, drive your hips forward."
        case .enhanceAthleticPerformance:
            return "Load the hamstrings deep, fire your hips on the way up."
        case .rehabPreventInjury:
            return "Soft knees, flat back, hinge only as far as control allows."
        case .loseFat, .getToned:
            return "Tight core, clean hinge, steady pace."
        case .improveEndurance:
            return "Smooth hinge, consistent rhythm, don't rush it."
        case .improveHealthLongevity:
            return "Controlled hinge to keep your spine safe."
        }
    }

    private static func rowIntentCue(for goal: PrimaryGoal) -> String {
        switch goal {
        case .buildMuscle:
            return "Pull with your back, squeeze at the top — feel the muscle working."
        case .getStronger:
            return "Solid hinge, drive the elbows back, own every rep."
        case .enhanceAthleticPerformance:
            return "Pull hard, stay tight, transfer power through your back."
        case .rehabPreventInjury:
            return "Flat back, no jerking, control both directions."
        case .loseFat, .getToned:
            return "Controlled pulls, tight form, no momentum."
        case .improveEndurance:
            return "Clean reps, steady pace, keep form through fatigue."
        case .improveHealthLongevity:
            return "Tall chest, flat back, move with control."
        }
    }

    private static func nextBeginSetAffirmation() -> String {
        let phrase = beginSetAffirmations[beginSetAffirmationIndex % beginSetAffirmations.count]
        beginSetAffirmationIndex += 1
        return phrase
    }

    private func exitTrackView() {
        if trackViewState == .tracking {
            cameraManager.stopPoseAnalysis()
        }
        // Clear a stale `.exercising` so the decimator doesn't treat the next
        // framing session as an active set (see endSet).
        poseManager.endManualSet()
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

        let exerciseType = TrackedExerciseType.from(exerciseName: exercise.name)

        // First set of each exercise: goal-specific intent cue + affirmation.
        // Subsequent sets: supportive phrase followed by the prior set's cue.
        if setsCompletedInSession == 0 {
            let affirmation = Self.nextBeginSetAffirmation()
            let spoken: String
            if let intent = Self.firstSetGoalCue(for: exerciseType) {
                spoken = "\(intent) \(affirmation)"
            } else {
                spoken = affirmation
            }
            SpeechManager.shared.speak(
                spoken,
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

        cameraManager.poseManager.trackedExerciseType = exerciseType
        // Keep pose pipeline on (already from `startPoseTrackingOnly`) without `startPoseAnalysis()`, which
        // calls `resetRepCountingState()` and async-sets `workoutState = .waiting` — that can race after
        // `startManualSet()` and break rep/set state.
        if !cameraManager.isAnalyzingPose {
            cameraManager.startPoseTrackingOnly()
        }
        cameraManager.poseManager.resetRepCount()
        cameraManager.poseManager.startManualSet()
        currentSetStart = Date()
        // Open an accuracy-flag capture window so an in-progress or after-set
        // flag has the set id, exercise, and weight already recorded.
        AccuracyFlagStore.shared.beginSet(
            exerciseType: exerciseType,
            exerciseName: exercise.name,
            currentWeight: currentWeight,
            setIndexInSession: setsCompletedInSession + 1
        )
        // Debug logging + screen recording exist solely to feed the telemetry pipeline,
        // so both follow its consent flag. Previously they ran unconditionally — when
        // telemetry was off, ReplayKit still hardware-encoded the full screen for the
        // whole set and the mp4 was then discarded: pure wasted battery and heat.
        let telemetryOn = TelemetryPreferencesManager.shared.shareDataToImproveChiron
        SquatRepDebugLogger.shared.reset()
        poseManager.debugLoggerEnabled = telemetryOn
        // Screen recording captures the full on-screen experience (camera + overlay) so
        // the CSV trace can be replayed alongside the video. iOS prompts the first time.
        // Skipped under thermal pressure / Low Power Mode: the encode stacks on top of
        // camera + inference exactly when the device needs to shed load. The CSV (much
        // cheaper) still uploads, so a set is never entirely unobserved.
        if telemetryOn && ThermalGovernor.shared.allowsScreenRecording {
            ScreenRecorder.shared.start()
        }
        // Open a telemetry session if the user has opted in (no-op otherwise).
        // Coordinator owns CSV writer and parks a video recorder for the
        // ScreenRecorder.stop callback in `exportDebugCSV` to attach.
        TelemetryCoordinator.shared.startSession(exerciseType: exerciseType)
        // Suppress rep counting for 1 second so the user can step back from the camera
        // after pressing the button. Without this delay, the pose detector may see a
        // partial/close-up pose and erroneously count a rep during the transition.
        cameraManager.suppressRepCounting = true
        cameraManager.trackExplicitSetActive = true
        // Hold the screen on for the duration of the set so the device doesn't lock
        // mid-rep — the user's hands are on the bar, not the phone.
        ScreenKeepAlive.begin()
        trackViewState = .tracking
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak cameraManager] in
            cameraManager?.suppressRepCounting = false
        }
    }

    private func endSet() {
        // Do not call `stopPoseAnalysis()` here — it clears `isAnalyzingPose` and freezes the overlay until the next set.
        cameraManager.trackExplicitSetActive = false
        cameraManager.suppressRepCounting = true
        ScreenKeepAlive.end()

        // Retroactive phantom-rep filter: remove the last counted rep if it was
        // validated within 3 seconds of pressing End Set (likely the user reaching
        // toward the phone, not an actual squat).
        poseManager.retroactiveEndSetFilter(window: 3.0)

        cameraManager.endTrackSetKeepingPoseActive()
        // Leave `.exercising` explicitly — suppressRepCounting stays true between Track
        // sets, which blocks the inactivity path that would otherwise do this, and the
        // frame decimator runs full-rate for as long as the state reads `.exercising`.
        poseManager.endManualSet()
        trackViewState = .armed

        // Close the telemetry session. CSV is finalized + queued; the video
        // recorder is parked, awaiting the mp4 from `finalizeScreenRecording`'s
        // ScreenRecorder.stop callback below.
        TelemetryCoordinator.shared.endSession()

        // Stop debug logging and hand the screen-recording mp4 to telemetry
        // for R2 upload. The per-frame debug CSV is no longer exported locally —
        // SessionCSVWriter writes its own CSV directly into the upload pipeline.
        poseManager.debugLoggerEnabled = false
        finalizeScreenRecording()

        // Record an initial accuracy-flag snapshot even on zero-rep sets so
        // an after-set flag can still report "the app counted 0 but I did
        // reps". The coach feedback (if any) overrides this snapshot below.
        let endMetrics = poseManager.aggregatedMetricsSnapshot()
        let endAnalysis = cameraManager.poseManager.currentFormAnalysis
            ?? cameraManager.poseManager.lastRepFormAnalysis
        AccuracyFlagStore.shared.recordSetEnd(
            formAnalysis: endAnalysis,
            aggregatedMetrics: endMetrics,
            feedback: nil,
            displayedRepCount: poseManager.repCount
        )

        // If no reps were completed, treat the set as if it never happened:
        // skip analysis, audio feedback, and session bookkeeping.
        guard poseManager.repCount > 0 else { return }

        setsCompletedInSession += 1

        let formAnalysis = cameraManager.poseManager.currentFormAnalysis
            ?? cameraManager.poseManager.lastRepFormAnalysis

        // The short cue is no longer computed here from the raw primary issue.
        // A raw cue bypasses the Stage-2 gate, so history used to store a
        // critical cue even when the live card showed "Dialed in". The cue is
        // now derived from the gated `feedback` inside the coaching callback
        // below (see `resolvedSetCue`) and used for BOTH the card and history,
        // so the two can never disagree.

        // Detect PR against prior history BEFORE writing this set, then fan
        // out: save the set, fire confetti on PR, and call coaching with the
        // PR info so the spoken line celebrates (and form cues stay silent
        // unless a safety-critical issue fires).
        if let exercise = selectedExercise {
            let exerciseName = exercise.name
            let weightForSet = currentWeight
            let repsForSet = poseManager.repCount
            let isBodyweight = isCurrentExerciseBodyweight
            let userId = UserManager.shared.getUserId()
            let metrics = poseManager.aggregatedMetricsSnapshot()

            WorkoutLogService.shared.getHistoryForExercise(exerciseName, userId: userId) { result in
                let prInfo: PersonalRecord.Info?
                if case .success(let history) = result {
                    prInfo = PersonalRecord.check(
                        exerciseName: exerciseName,
                        isBodyweight: isBodyweight,
                        weight: weightForSet,
                        reps: repsForSet,
                        history: history
                    )
                } else {
                    prInfo = nil
                }

                DispatchQueue.main.async {
                    // PR confetti is dropped from inside the LLM-speech `onStart` below so the
                    // visual lands together with the audio. Firing it here (~3–5s before the LLM
                    // returns) made the confetti seem unrelated to the spoken announcement.

                    // Badge evaluation: read the in-memory form metrics for
                    // this set (Form Quality / Set Closer / Tempo Master),
                    // then trigger the history pass for streak / mastery /
                    // volume rules. The center handles dedupe — already-earned
                    // badges short-circuit silently.
                    let setDuration: TimeInterval? = currentSetStart.map { Date().timeIntervalSince($0) }
                    BadgeCenter.shared.evaluateAfterSet(
                        exerciseName: exerciseName,
                        isBodyweight: isBodyweight,
                        reps: repsForSet,
                        formAnalysis: formAnalysis,
                        aggregatedMetrics: metrics,
                        setDurationSeconds: setDuration,
                        userId: userId
                    )
                    currentSetStart = nil

                    if let analysis = formAnalysis {
                        let exerciseType = TrackedExerciseType.from(exerciseName: exerciseName)
                        let prToCelebrate = prInfo
                        coachingManager.generateSetEndFeedback(
                            formAnalysis: analysis,
                            aggregatedMetrics: metrics,
                            exerciseType: exerciseType,
                            currentWeight: weightForSet,
                            personalRecord: prToCelebrate
                        ) { feedback in
                            // Replace the placeholder snapshot taken at end-of-set with
                            // one that includes the coach line — that's the line a tester
                            // would actually be flagging.
                            AccuracyFlagStore.shared.recordSetEnd(
                                formAnalysis: analysis,
                                aggregatedMetrics: metrics,
                                feedback: feedback,
                                displayedRepCount: repsForSet
                            )
                            // When this set is a PR, drop confetti at the moment the LLM line
                            // begins playing so visual + audio land together.
                            let onStart: (() -> Void)? = prToCelebrate == nil ? nil : {
                                PRCelebrationCenter.shared.fireConfetti()
                            }
                            SpeechManager.shared.speak(feedback.spokenText, onStart: onStart)

                            // Single source of truth for this set's short cue: the
                            // gated `feedback`. The exact same string is shown on the
                            // card AND written to history, so the live view and the
                            // History tab can never disagree. A clean set gets a
                            // rotating affirmation instead of a critical cue.
                            let setCue = resolvedSetCue(from: feedback)
                            saveCompletedSetToFirestore(
                                exerciseName: exerciseName,
                                weight: weightForSet,
                                reps: repsForSet,
                                cues: setCue
                            )
                            // Fade in the correct card contents for this set's outcome.
                            withAnimation(.easeInOut(duration: 0.35)) {
                                primaryCueText = setCue
                            }
                        }
                    } else {
                        // Degenerate set (reps counted but no form analysis): still
                        // persist the set so it appears in history, with no cue.
                        saveCompletedSetToFirestore(
                            exerciseName: exerciseName,
                            weight: weightForSet,
                            reps: repsForSet,
                            cues: nil
                        )
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
            // New exercise → button label resets to "Weight" until the user
            // confirms a value. The last-logged weight hydrates `suggestedWeight`
            // so the picker still opens at the right number. Keep
            // setNumbersByExercise so re-selecting an exercise resumes the
            // same set numbering.
            currentWeight = nil
            suggestedWeight = loadLastWeight(for: exercise.name)
            fetchLastWeightFromHistory(for: exercise.name)
        }
        if trackViewState == .idle {
            trackViewState = .armed
        }
        scheduleFramingReminder()
    }

    /// Speak the framing setup instructions 2s after a dropdown exercise
    /// selection. Only fires from this path — onAppear's `restoreLastTrackedExercise`
    /// does not call `didSelectExercise`, so re-entering the tab stays silent.
    /// Cancels any previously scheduled reminder so rapid re-selection or
    /// leaving the view doesn't produce stale speech.
    private func scheduleFramingReminder() {
        pendingFramingSpeech?.cancel()
        let work = DispatchWorkItem {
            SpeechManager.shared.speak(
                "Prop your phone about four to six feet away. Ensure it's either in front of you or at about a 45 degree angle. Face it towards you, and step back until you see a green skeleton filter. When you're ready for your set, enter the weight you're lifting and press begin set.",
                priority: .high,
                context: .instruction
            )
        }
        pendingFramingSpeech = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }

    // MARK: - Lifecycle

    private func onAppear() {
        cameraManager.setupCameraSession()
        // Other flows call `switchToSetupMode()`; re-selecting this tab does not always rerun `onAppear`, so `RootTabView` also calls `switchToWorkoutMode` when Track is selected.
        cameraManager.switchToWorkoutMode()
        // Serialized start (not a raw global-queue startRunning): a stale start racing
        // `onDisappear`'s pause could otherwise leave the camera running behind another tab.
        cameraManager.resumeCaptureSession()
        cameraSessionReady = true
        // Start pose tracking immediately so overlay/smoothing run before user presses Begin Set.
        cameraManager.suppressRepCounting = true
        cameraManager.startPoseTrackingOnly()
        restoreLastTrackedExercise()
    }

    private func onDisappear() {
        cameraManager.suppressRepCounting = false
        cameraManager.trackExplicitSetActive = false
        pendingFramingSpeech?.cancel()
        pendingFramingSpeech = nil
        if trackViewState == .tracking {
            cameraManager.stopPoseAnalysis()
            // Balance the `ScreenKeepAlive.begin()` paired with the missing `endSet()`
            // so the screen-on lock doesn't outlive the view.
            ScreenKeepAlive.end()
            // Clear `.exercising` so the decimator sees an idle pipeline when the
            // user returns to the tab (see endSet).
            poseManager.endManualSet()
            trackViewState = .armed
        }
        // Stop the camera hardware + inference while the tab is hidden. RootTabView keeps
        // this view mounted after first visit, so without this the camera and MediaPipe
        // ran at full rate while the user browsed Home/Research/Profile. RootTabView's
        // tab-change handler restores tracking when the user returns (onAppear may not
        // re-fire on tab re-selection).
        cameraManager.pauseCaptureSession()
    }

    // MARK: - Screen Recording Finalize

    /// Stops the ReplayKit recording started in `beginSet` and hands the temp
    /// mp4 to `TelemetryCoordinator.attachRecordedVideo(...)` so the upload
    /// pipeline can move it to `Pending/` and queue it for R2 alongside the
    /// session CSV. No local share sheet — both files now ship to R2 directly.
    private func finalizeScreenRecording() {
        let basename = makeRecordingBasename()
        ScreenRecorder.shared.stop(basename: basename) { videoURL in
            TelemetryCoordinator.shared.attachRecordedVideo(at: videoURL)
        }
    }

    /// `<exercise_slug>_<yyyy-MM-dd_HHmmss>` — slug lowercases the exercise name, swaps spaces
    /// for underscores, and drops anything that isn't a letter/number/underscore/hyphen so the
    /// filename is safe in the temporary directory and in any inbox if telemetry is disabled.
    private func makeRecordingBasename() -> String {
        let slug: String = {
            guard let raw = selectedExercise?.name, !raw.isEmpty else { return "set" }
            let underscored = raw.lowercased().replacingOccurrences(of: " ", with: "_")
            let filtered = underscored.filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
            return filtered.isEmpty ? "set" : filtered
        }()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        return "\(slug)_\(formatter.string(from: Date()))"
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
            // Button label stays "Weight" on restore — the user hasn't
            // confirmed a value for this session yet. Suggestion hydrates
            // from cache + Firestore so the picker opens at the right number.
            currentWeight = nil
            suggestedWeight = loadLastWeight(for: match.name)
            fetchLastWeightFromHistory(for: match.name)
            trackViewState = .armed
        }
    }

    /// Reads the last-used weight for a specific exercise out of UserDefaults,
    /// or returns nil if the user has never saved a weight for that movement.
    private func loadLastWeight(for exerciseName: String) -> Double? {
        let stored = UserDefaults.standard.dictionary(forKey: lastWeightByExerciseKey) as? [String: Double]
        return stored?[exerciseName]
    }

    /// Persists the given weight as the last-used value for `exerciseName` so
    /// the weight picker pre-fills with it on the next open (even across app
    /// relaunches and exercise switches).
    private func persistLastWeight(_ weight: Double, for exerciseName: String) {
        var stored = (UserDefaults.standard.dictionary(forKey: lastWeightByExerciseKey) as? [String: Double]) ?? [:]
        stored[exerciseName] = weight
        UserDefaults.standard.set(stored, forKey: lastWeightByExerciseKey)
    }

    /// Pulls the most recent Firestore-logged weight for `exerciseName` and
    /// applies it to `suggestedWeight` so the picker pre-fills at the right
    /// number. Does not touch `currentWeight` — the button label stays
    /// "Weight" until the user confirms a value. Silently no-ops if the
    /// fetch fails or every returned log is weightless (bodyweight).
    private func fetchLastWeightFromHistory(for exerciseName: String) {
        let userId = UserManager.shared.getUserId()
        WorkoutLogService.shared.getHistoryForExercise(exerciseName, userId: userId, limit: 10) { result in
            guard case .success(let logs) = result else { return }
            guard let latestWeight = logs.first(where: { $0.weight != nil })?.weight else { return }
            DispatchQueue.main.async {
                // Only apply if the user is still on this exercise.
                guard selectedExercise?.name == exerciseName else { return }
                suggestedWeight = latestWeight
                persistLastWeight(latestWeight, for: exerciseName)
            }
        }
    }

    // MARK: - Set-end cue

    /// Short, literal affirmations for a clean set. Rotated (not random) so
    /// consecutive clean sets don't repeat the same word. Kept literal — no
    /// similes — to match the spoken-cue language rules. "Dialed in" stays in
    /// the pool; it's just no longer the only thing users ever see.
    private static let cleanSetAffirmations = [
        "Dialed in",
        "Perfect",
        "Clean set",
        "Locked in",
        "Nailed it",
        "Textbook",
        "On point",
        "Strong set"
    ]

    /// The short cue for a finished set — the single source of truth for both
    /// the on-screen card and the persisted `cues` in history. A surfaced
    /// critique (from the gated Stage-2 plan) wins; otherwise a clean set gets
    /// a rotating affirmation; a corrective set with no short cue gets nil.
    ///
    /// Because both the live card and the history write call this, the two
    /// always show the same thing. Mutating `cleanCueRotation` here is safe
    /// from the escaping coaching callback — `@State`'s setter is nonmutating.
    private func resolvedSetCue(from feedback: SetEndFeedback) -> String? {
        if let cue = feedback.displayShortCue {
            return cue
        }
        guard feedback.tone == .clean else { return nil }
        let pool = Self.cleanSetAffirmations
        let affirmation = pool[cleanCueRotation % pool.count]
        cleanCueRotation += 1
        return affirmation
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
                .stroke(Color.white.opacity(0.08), lineWidth: 6)

            Circle()
                .stroke(Color.accentGradient, style: StrokeStyle(lineWidth: 6, lineCap: .round))
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
    @State private var sheetCategories: Set<String> = []
    @State private var sheetDifficulties: Set<Difficulty> = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.background.ignoresSafeArea()

            NavigationStack {
                ExerciseLibraryView(
                    onExerciseSelected: onExerciseSelected,
                    selectedForSelectionMode: selectedExercise,
                    searchBinding: $sheetSearch,
                    selectedCategoriesBinding: $sheetCategories,
                    selectedDifficultiesBinding: $sheetDifficulties
                )
            }
            .padding(.top, 52)

            Button {
                dismiss()
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
