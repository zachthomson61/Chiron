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

    @State private var showExerciseSelector = false
    @State private var showExerciseInfo = false
    @State private var showPoseOverlay = false
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

    @ObservedObject private var cameraManager = SharedCameraSessionManager.shared
    /// Rep count is published here; `cameraManager` alone does not trigger redraws when reps change.
    @ObservedObject private var poseManager = OnDevicePoseManager.shared
    @ObservedObject private var coachingManager = OpenAICoachingManager.shared

    private let lastTrackedExerciseKey = "lastTrackedExerciseName"

    var body: some View {
        ZStack {
            TrackCameraPreviewRepresentable(session: cameraManager.getCaptureSession())
                .ignoresSafeArea()

            if showPoseOverlay {
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
                            Button {
                                showPoseOverlay.toggle()
                            } label: {
                                Image(systemName: showPoseOverlay ? "eye.fill" : "eye")
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
                                    HStack(spacing: 6) {
                                        Text(selectedExercise?.name ?? "Select Exercise")
                                            .font(.title3.weight(.semibold))
                                            .foregroundColor(.textPrimary)
                                            .multilineTextAlignment(.center)
                                            .lineLimit(3)
                                        Image(systemName: "chevron.down")
                                            .font(.headline.weight(.semibold))
                                            .foregroundColor(.textSecondary)
                                    }
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 12)
                                    .fixedSize(horizontal: true, vertical: false)
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
                .frame(height: 72)
                .padding(.top, 8)

                Spacer()
            }

            // Framing overlay + message bar + action button
            VStack {
                Spacer()

                if trackViewState == .armed {
                    FramingOverlayView()
                        .transition(.opacity)
                }

                Spacer()

                if trackViewState == .armed {
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
                    .padding(.bottom, 30)
                    .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: trackViewState)
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
        .sheet(isPresented: $showDebugCSVShare) {
            if let url = debugCSVURL {
                SquatRepShareSheet(url: url)
            }
        }
    }

    // MARK: - Computed

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

    private func exitTrackView() {
        if trackViewState == .tracking {
            cameraManager.stopPoseAnalysis()
        }
        cameraManager.suppressRepCounting = false
        cameraManager.trackExplicitSetActive = false
        trackViewState = .idle
        selectedExercise = nil
        setsCompletedInSession = 0
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
        setsCompletedInSession += 1
        trackViewState = .armed

        // Stop debug logging and export CSV for analysis.
        poseManager.debugLoggerEnabled = false
        exportDebugCSV()

        let formAnalysis = cameraManager.poseManager.currentFormAnalysis
            ?? cameraManager.poseManager.lastRepFormAnalysis

        if let analysis = formAnalysis, let exercise = selectedExercise {
            let exerciseType = TrackedExerciseType.from(exerciseName: exercise.name)
            coachingManager.analyzeAndGetNaturalFeedback(
                formAnalysis: analysis,
                exerciseType: exerciseType
            ) { feedback in
                SpeechManager.shared.speak(feedback)
            }
        }

        persistLastTrackedExercise()
    }

    private func didSelectExercise(_ exercise: Exercise) {
        selectedExercise = exercise
        persistLastTrackedExercise()
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
        }
        return view
    }

    func updateUIView(_ uiView: TrackCameraPreviewUIView, context: Context) {
        if let session = session {
            uiView.setSession(session)
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
            return
        }
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        self.layer.addSublayer(layer)
        previewLayer = layer
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
                .stroke(Color.gray.opacity(0.3), lineWidth: 5)

            Circle()
                .stroke(Color.blue.opacity(0.6), style: StrokeStyle(lineWidth: 5, lineCap: .round))
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
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text("REPS")
                    .font(.neueMontrealBold(size: 7))
                    .foregroundColor(.blue.opacity(0.85))
            }
        }
        .frame(width: 64, height: 64)
        .shadow(color: Color.blue.opacity(0.3), radius: 4)
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
