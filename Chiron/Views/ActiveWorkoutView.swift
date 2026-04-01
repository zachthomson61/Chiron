//
//  ActiveWorkoutView.swift
//  Chiron
//
//  Unified active workout view that adapts based on exercise type.
//  Same UI layout for all exercises, but exercise-specific pose detection and AI feedback.
//
//  Architecture:
//  - Accepts exerciseType parameter to adapt pose detection and AI feedback
//  - Same UI layout for all exercises: rep counter, back arrow, finish button
//  - Exercise-specific behavior:
//    - Pose detection type (trackedExerciseType: .bodyweight vs .barbell)
//    - AI feedback prompts (exercise-specific coaching cues)
//  - Designed to be embedded in CameraSetupView to maintain camera continuity
//

import SwiftUI
import AVFoundation

struct ActiveWorkoutView: View {
    let exerciseType: ExerciseType
    @ObservedObject var viewModel: WorkoutViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var currentRepCount: Int = 0
    @State private var repUpdateTimer: Timer?
    @State private var lastRepCountSeen: Int = 0 // Used to track rep count changes
    
    var body: some View {
        ZStack {
            // Main content
            VStack {
                // Top navigation bar
                HStack {
                    Button(action: {
                        finishWorkout()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .foregroundColor(.textPrimary)
                    }
                    .shadow(color: .black, radius: 2, x: 1, y: 1)
                    
                    Spacer()
                }
                .padding()
                
                Spacer()
                
                // Bottom Finish button
                Button(action: {
                    finishWorkout()
                }) {
                    Text(exerciseType.finishButtonText)
                        .font(.headline)
                        .fontWeight(.semibold)
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
            
            // Rep Counter in top right corner
            VStack {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Text("\(currentRepCount)")
                            .font(.system(size: 140, weight: .bold, design: .rounded))
                            .foregroundColor(.textPrimary)
                        Text("Reps")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundColor(.textSecondary)
                    }
                    .shadow(color: .black, radius: 2, x: 1, y: 1)
                    .padding(.trailing)
                    .padding(.top)
                }
                Spacer()
            }
        }
        .onAppear {
            ScreenKeepAlive.begin()
            // Set squat type for exercise-specific pose detection
            SharedCameraSessionManager.shared.poseManager.trackedExerciseType = exerciseType.trackedExerciseType
            
            // Ensure we're in workout mode (should already be set by CameraSetupView.startWorkout())
            if SharedCameraSessionManager.shared.isInSetupMode {
                SharedCameraSessionManager.shared.switchToWorkoutMode()
            }
            
            // Start pose analysis and rep counting
            SharedCameraSessionManager.shared.startPoseAnalysis()
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
            
            // Switch back to setup mode but keep camera running
            SharedCameraSessionManager.shared.switchToSetupMode()
        }
    }
    
    /// Starts a timer to periodically update the rep count from the pose manager
    private func startRepCountTimer() {
        stopRepCountTimer()
        lastRepCountSeen = 0
        repUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [self] _ in
            let repCount = SharedCameraSessionManager.shared.poseManager.getCurrentRepCount()
            DispatchQueue.main.async {
                lastRepCountSeen = repCount
                currentRepCount = repCount
            }
        }
    }
    
    private func stopRepCountTimer() {
        repUpdateTimer?.invalidate()
        repUpdateTimer = nil
    }
    
    /// Stops pose analysis, stops the camera, and dismisses the view
    private func finishWorkout() {
        if SharedCameraSessionManager.shared.isAnalyzingPose {
            SharedCameraSessionManager.shared.stopPoseAnalysis()
        }
        SharedCameraSessionManager.shared.stopCamera()
        dismiss()
    }
}

