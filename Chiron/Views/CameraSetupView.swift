//
//  CameraSetupView.swift
//  Chiron
//
//  Unified camera setup view that adapts based on exercise type.
//  Handles both setup and workout modes in a single view to maintain camera continuity.
//
//  Architecture:
//  - Accepts exerciseType parameter to adapt text, audio cues, and segmentation algorithm
//  - Toggles between setup and workout modes using state (no navigation)
//  - Maintains same camera preview throughout for seamless video recording
//  - Exercise-specific behavior:
//    - Instruction text and button labels
//    - Audio cues (setup and start workout)
//    - Segmentation processor exercise mode
//    - Pose detection type (squatType)
//

import SwiftUI
import AVFoundation

struct CameraSetupView: View {
    let exerciseType: ExerciseType
    @ObservedObject var viewModel: WorkoutViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var workoutActive: Bool = false
    
    // Segmentation overlay
    @StateObject private var segmentationProcessor = SegmentationProcessor()
    
    // MARK: - Body
    
    private var instructionCard: some View {
        InstructionCard(exerciseType: exerciseType)
    }
    
    var body: some View {
        ZStack {
            // Live camera preview (shared session) - stays visible in both modes
            SetupCameraPreviewRepresentable(processor: segmentationProcessor)
                .ignoresSafeArea()
            
            // Segmentation overlay image (semi-transparent green/yellow/red silhouette)
            // Only show during setup mode
            if !workoutActive {
                SegmentationOverlayView(processor: segmentationProcessor)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            
            if !workoutActive {
                // Setup mode UI
                VStack {
                    // Top navigation bar
                    HStack {
                        Button(action: { dismiss() }) {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.left")
                                Text("Back")
                            }
                            .foregroundColor(.white)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                        }
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                        
                        Spacer()
                    }
                    .padding()
                    
                    Spacer()
                    
                    instructionCard
                        .padding(.horizontal, 20)
                    
                    Spacer()
                    
                    Button(action: startWorkout) {
                        Text(exerciseType.startButtonText)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(width: 280, height: 48)
                            .background(Color.primaryPurple)
                            .cornerRadius(24)
                    }
                    .shadow(color: .black, radius: 2, x: 1, y: 1)
                    .padding(.bottom, 40)
                }
            } else {
                // Workout mode - embed ActiveWorkoutView (maintains same camera preview)
                ActiveWorkoutView(exerciseType: exerciseType, viewModel: viewModel)
                    .background(Color.clear)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { 
            setupCameraForSetupMode()
            segmentationProcessor.stopProcessing()
            segmentationProcessor.setProcessingEnabled(true)
            // Set exercise mode for segmentation scoring
            segmentationProcessor.exerciseMode = exerciseType.squatType
            
            // Add speech feedback for exercise-specific form instructions
            SpeechManager.shared.speak(exerciseType.setupAudioCue)
        }
        .onDisappear { 
            segmentationProcessor.setProcessingEnabled(false)
            // Detach any segmentation delegate to avoid stale callbacks when navigating away
            SharedCameraSessionManager.shared.getVideoDataOutput()?.setSampleBufferDelegate(nil, queue: nil)
        }
    }
    
    // MARK: - Private Methods
    
    /// Configures the camera session for setup mode (segmentation overlay)
    private func setupCameraForSetupMode() {
        if SharedCameraSessionManager.shared.getCaptureSession() == nil {
            SharedCameraSessionManager.shared.setupCameraSession()
        }
        SharedCameraSessionManager.shared.switchToSetupMode()
        
        // Start session if not already running
        if let session = SharedCameraSessionManager.shared.getCaptureSession(), !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
            }
        }
    }
    
    /// Transitions from setup mode to workout mode
    /// Stops segmentation, switches camera to workout mode, and shows ActiveWorkoutView
    private func startWorkout() {
        segmentationProcessor.stopProcessing()
        segmentationProcessor.setProcessingEnabled(false)
        
        SharedCameraSessionManager.shared.poseManager.squatType = exerciseType.squatType
        SharedCameraSessionManager.shared.switchToWorkoutMode()
        
        SpeechManager.shared.speak(exerciseType.startWorkoutAudioCue)
        
        withAnimation(.easeInOut(duration: 0.25)) {
            workoutActive = true
        }
    }
}

// MARK: - Instruction Card
private struct InstructionCard: View {
    let exerciseType: ExerciseType
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Attempt to Place Your Phone:")
                .font(.headline)
                .foregroundColor(.white)
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach(instructions, id: \.text) { instruction in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: instruction.icon)
                            .foregroundColor(.primaryPurple)
                        Text(instruction.text)
                            .foregroundColor(.white)
                    }
                }
            }
            .padding(.leading, 20)
        }
        .padding(16)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color.black.opacity(0.55), Color.black.opacity(0.35)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.primaryPurple.opacity(0.5), Color.white.opacity(0.2)]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ), lineWidth: 1
                )
        )
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)
        .padding(.horizontal, 12)
        .opacity(0.9)
    }
    
    private struct Instruction {
        let icon: String
        let text: String
    }
    
    private var instructions: [Instruction] {
        switch exerciseType {
        case .bodyweightSquat:
            return [
                Instruction(icon: "ruler", text: "6-8' Away"),
                Instruction(icon: "angle", text: "45° to Your Body"),
                Instruction(icon: "person.fill", text: "At Waist to Chest Height"),
                Instruction(icon: "figure.walk", text: "With Feet in View")
            ]
        case .barbellBackSquat:
            return [
                Instruction(icon: "ruler", text: "7-9' Away"),
                Instruction(icon: "angle", text: "45° to the Front of Your Body"),
                Instruction(icon: "person.fill", text: "At Mid-Chest or Slightly Above"),
                Instruction(icon: "figure.walk", text: "Feet + Barbell in Frame")
            ]
        case .barbellRow, .deadlift, .romanianDeadlift, .barbellBenchPress:
            // Default instructions for exercises without specific setup requirements
            return [
                Instruction(icon: "ruler", text: "6-8' Away"),
                Instruction(icon: "angle", text: "45° to Your Body"),
                Instruction(icon: "person.fill", text: "At Waist to Chest Height"),
                Instruction(icon: "figure.walk", text: "With Full Body in View")
            ]
        }
    }
}
