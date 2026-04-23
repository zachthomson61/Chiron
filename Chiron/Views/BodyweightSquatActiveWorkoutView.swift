//
//  BodyweightSquatActiveWorkoutView.swift
//  Chiron
//
//  DEPRECATED: This view has been replaced by the unified ActiveWorkoutView.
//  Use ActiveWorkoutView(exerciseType: .bodyweightSquat, viewModel: viewModel) instead.
//
//  This file is kept for reference but should not be used in new code.
//

import SwiftUI
import AVFoundation

struct BodyweightSquatActiveWorkoutView: View {
    @ObservedObject var viewModel: WorkoutViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showSetComplete = false
    @State private var showSpeechControl = false
    @State private var isReadingAnalysis = false
    @State private var currentRepCount = 0
    @State private var updateTimer: Timer?
    @State private var shouldDismissToExerciseSelection = false
    @State private var showPoseVisualization = false
    @State private var restTimeRemaining: TimeInterval = 0
    @State private var restTimer: Timer?
    // Completed set summaries (rep counts per set)
    @State private var completedSetReps: [Int] = []
    @State private var totalRepsAtLastSetEnd: Int = 0
    
    // Callback to navigate back to exercise selection
    var onFinishExercise: (() -> Void)?
    
    // Initialize with automatic set detection
    init(viewModel: WorkoutViewModel, onFinishExercise: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.onFinishExercise = onFinishExercise
    }
    
    var body: some View {
        ZStack {
            // Camera view fills entire screen
            ActiveWorkoutCameraView()
                .ignoresSafeArea()
            
            // Pose Visualization Overlay (for testing)
            if showPoseVisualization {
                PoseVisualizationOverlay()
                    .allowsHitTesting(false) // Don't block touch events
            }
            
            // UI overlay on top of camera
            VStack {
                // Navigation Header
                HStack {
                    Button(action: {
                        dismiss()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .foregroundColor(.textPrimary)
                    }
                    .shadow(color: .black, radius: 2, x: 1, y: 1)
                    Spacer()
                    
                    // Completed Sets Display (to the left of rep counter)
                    if !completedSetReps.isEmpty {
                        HStack(spacing: 12) {
                            ForEach(Array(completedSetReps.enumerated()), id: \.offset) { idx, reps in
                                VStack(spacing: 4) {
                                    Text("\(reps)")
                                        .font(.neueMontrealBold(size: 42))
                                        .foregroundColor(.white)
                                    Text("Set \(idx + 1)")
                                        .font(.neueMontrealSemiBold(size: 14))
                                        .foregroundColor(.white.opacity(0.8))
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 16)
                                .background(
                                    LinearGradient(
                                        colors: [Color.green.opacity(0.6), Color.green.opacity(0.4)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(
                                            LinearGradient(
                                                colors: [Color.green, Color.green.opacity(0.7)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 2
                                        )
                                )
                                .cornerRadius(20)
                                .scaleEffect(idx == completedSetReps.count - 1 ? 1.05 : 1.0) // Slightly larger for most recent set
                                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: completedSetReps.count)
                            }
                        }
                        .transition(.scale.combined(with: .opacity))
                        .shadow(color: .green.opacity(0.3), radius: 8, x: 0, y: 4)
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                    
                    // Large Rep Counter in Header
                    VStack(spacing: 8) {
                        Text("\(currentRepCount)")
                            .font(.neueMontrealBold(size: 140))
                            .foregroundColor(.textPrimary)
                        Text("Reps")
                            .font(.neueMontrealSemiBold(size: 28))
                            .foregroundColor(.textSecondary)
                    }
                    .shadow(color: .black, radius: 2, x: 1, y: 1)
                    
                    Spacer()
                    // Invisible button for balance
                    Button("") { }
                        .opacity(0)
                }
                .padding()
                Spacer()
                
                // Rest Timer Clock Overlay (Center of Screen)
                if OnDevicePoseManager.shared.workoutState == .resting {
                    RestTimerClockView(restTimeRemaining: restTimeRemaining)
                        .transition(.opacity.combined(with: .scale))
                }
                
                Spacer()
                
                // Bottom Controls
                HStack(spacing: 40) {
                    Button(action: {
                        showSpeechControl = true
                    }) {
                        Image(systemName: SpeechManager.shared.isSpeaking ? "speaker.wave.2.fill" : "speaker.wave.2")
                            .font(.neueMontrealBold(size: 22))
                            .foregroundColor(SpeechManager.shared.isSpeaking ? .green : .gray)
                    }
                    .shadow(color: .black, radius: 2, x: 1, y: 1)
                    
                    // Pose Visualization Toggle (for testing)
                    Button(action: {
                        showPoseVisualization.toggle()
                    }) {
                        Image(systemName: showPoseVisualization ? "eye.fill" : "eye")
                            .font(.neueMontrealBold(size: 22))
                            .foregroundColor(showPoseVisualization ? .green : .gray)
                    }
                    .shadow(color: .black, radius: 2, x: 1, y: 1)
                    
                    // Automatic Status Display
                    VStack(spacing: 4) {
                        Text(getWorkoutStatusText())
                            .font(OnDevicePoseManager.shared.workoutState == .waiting ? .neueMontrealRegular(size: 15) : .neueMontrealBold(size: 17))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                        
                        if OnDevicePoseManager.shared.workoutState == .resting {
                            Text("Rest: \(formatRestTime())")
                                .font(.neueMontrealRegular(size: 15))
                                .foregroundColor(.gray)
                        }
                    }
                    .frame(width: 140, height: 48)
                    .background(getWorkoutStatusColor())
                    .cornerRadius(24)
                    .shadow(color: .black, radius: 2, x: 1, y: 1)
                    
                    Button(action: {
                        // TODO: Reset current set
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.neueMontrealBold(size: 22))
                            .foregroundColor(.gray)
                    }
                    .shadow(color: .black, radius: 2, x: 1, y: 1)
                }
                .padding(.bottom, 20)
                
                // Finish Exercise Button
                Button(action: {
                    finishExercise()
                }) {
                    Text("Finish Bodyweight Squat")
                        .font(.neueMontrealSemiBold(size: 17))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.orange)
                        .cornerRadius(24)
                }
                .shadow(color: .black, radius: 2, x: 1, y: 1)
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            ScreenKeepAlive.begin()
            // Set squat type for bodyweight squat
            SharedCameraSessionManager.shared.poseManager.trackedExerciseType = .bodyweight
            
            // Start automatic pose analysis
            // Clear any previous workout data
            completedSetReps = []
            totalRepsAtLastSetEnd = 0
            currentRepCount = 0
            setInProgress = false
            lastRepCountSeen = 0
            SharedCameraSessionManager.shared.switchToWorkoutMode()
            SharedCameraSessionManager.shared.startPoseAnalysis()
            
            // Start rep count timer
            startRepCountTimer()
        }
        .onDisappear {
            ScreenKeepAlive.end()
            // Stop pose analysis when leaving workout
            if SharedCameraSessionManager.shared.isAnalyzingPose {
                SharedCameraSessionManager.shared.stopPoseAnalysis()
            }
            // Stop timer
            stopRepCountTimer()
            stopRestTimer()
            
            // Switch back to setup mode but keep camera running
            SharedCameraSessionManager.shared.switchToSetupMode()
        }
        .sheet(isPresented: $showSpeechControl) {
            SpeechControlView()
        }
    }
    
    // MARK: - Helper Functions
    
    private func getWorkoutStatusText() -> String {
        let poseManager = OnDevicePoseManager.shared
        
        switch poseManager.workoutState {
        case .waiting:
            return "Ready"  // More subtle message
        case .exercising:
            return "Set \(poseManager.currentSet)\nRep —"
        case .resting:
            return "Set complete!\nRest for \(formatRestTime())"
        case .finished:
            return "Workout complete!"
        }
    }
    
    private func getWorkoutStatusColor() -> Color {
        let poseManager = OnDevicePoseManager.shared
        
        switch poseManager.workoutState {
        case .waiting:
            return Color.primaryPurple.opacity(0.6)  // More subtle color
        case .exercising:
            return Color.green
        case .resting:
            return Color.orange
        case .finished:
            return Color.gray
        }
    }
    
    private func formatRestTime() -> String {
        let remaining = max(0, Int(restTimeRemaining))
        return "\(remaining)s"
    }
    
    private func startRestTimer() {
        restTimeRemaining = 60.0 // 60 seconds rest period
        
        restTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if restTimeRemaining > 0 {
                restTimeRemaining -= 1.0
            } else {
                timer.invalidate()
                restTimer = nil
            }
        }
    }
    
    private func stopRestTimer() {
        restTimer?.invalidate()
        restTimer = nil
        restTimeRemaining = 0
    }
    
    // End-of-set detection state
    @State private var setInProgress: Bool = false
    @State private var lastRepCountSeen: Int = 0
    @State private var lastActivityTime: TimeInterval = Date().timeIntervalSince1970
    @State private var feedbackCooldownUntil: TimeInterval = 0
    private let inactivityThresholdSeconds: TimeInterval = 5.0
    private let feedbackCooldownSeconds: TimeInterval = 6.0

    private func startRepCountTimer() {
        // Update rep count every 0.5 seconds and monitor inactivity
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            _ = OnDevicePoseManager.shared
            let now = Date().timeIntervalSince1970

            // Current rep count (now resets between sets)
            let reps = SharedCameraSessionManager.shared.poseManager.getCurrentRepCount()
            currentRepCount = reps

            // Activity based only on rep changes
            if reps != lastRepCountSeen {
                lastRepCountSeen = reps
                lastActivityTime = now
                if reps > 0 { setInProgress = true }
            }

            // Detect end of set via inactivity
            if setInProgress,
               now - lastActivityTime >= inactivityThresholdSeconds,
               reps > 0,
               now >= feedbackCooldownUntil {
                setInProgress = false
                feedbackCooldownUntil = now + feedbackCooldownSeconds
                handleEndOfSetFeedback()
            }

        }
    }

    private func handleEndOfSetFeedback() {
        // Append set summary bubble and start rest timer
        // Use the current rep count as the completed reps for this set
        if currentRepCount > 0 {
            completedSetReps.append(currentRepCount)
            totalRepsAtLastSetEnd = currentRepCount
        }
        
        // Reset rep counter to 0 for next set
        currentRepCount = 0
        lastRepCountSeen = 0
        
        // Reset the pose manager's rep count state
        OnDevicePoseManager.shared.resetRepCount()
        
        startRestTimer()
        // Get latest form analysis snapshot (if available)
        if let analysis = OnDevicePoseManager.shared.currentFormAnalysis {
            let metrics = OnDevicePoseManager.shared.aggregatedMetricsSnapshot()
            OpenAICoachingManager.shared.generateSetEndFeedback(
                formAnalysis: analysis,
                aggregatedMetrics: metrics,
                exerciseType: .bodyweight
            ) { feedback in
                if !feedback.spokenText.isEmpty {
                    SpeechManager.shared.speak(feedback.spokenText, priority: .high)
                }
            }
        } else {
            // Fallback if no analysis available - single natural sentence
            let fallback = "Nice control there, but let's aim for a little more depth next set."
            SpeechManager.shared.speakCoachingFeedback(fallback)
        }
    }
    
    private func stopRepCountTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
    
    private func finishExercise() {
        isReadingAnalysis = true
        viewModel.currentFeedback = ""
        
        // Stop pose analysis and camera
        if SharedCameraSessionManager.shared.isAnalyzingPose {
            SharedCameraSessionManager.shared.stopPoseAnalysis()
        }
        SharedCameraSessionManager.shared.stopCamera()
        
        // Check if any reps were completed (sum of all completed sets)
        let totalReps = completedSetReps.reduce(0, +) + currentRepCount
        
        if totalReps == 0 {
            DispatchQueue.main.async {
                self.isReadingAnalysis = false
                // Navigate back immediately if no reps were completed
                onFinishExercise?()
            }
        } else {
            // Get detailed coaching feedback for end of workout (API-generated only)
            // Note: We need to implement this method in SharedCameraSessionManager
            // For now, just navigate back
            DispatchQueue.main.async {
                self.isReadingAnalysis = false
                onFinishExercise?()
            }
        }

    }
}

