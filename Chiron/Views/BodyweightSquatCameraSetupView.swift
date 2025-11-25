//
//  BodyweightSquatCameraSetupView.swift
//  Chiron
//
//  DEPRECATED: This view has been replaced by the unified CameraSetupView.
//  Use CameraSetupView(exerciseType: .bodyweightSquat, viewModel: viewModel) instead.
//
//  This file is kept for reference but should not be used in new code.
//

import SwiftUI
import AVFoundation

struct BodyweightSquatCameraSetupView: View {
    @ObservedObject var viewModel: WorkoutViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showActiveWorkout = false
    
    // Segmentation overlay
    @StateObject private var segmentationProcessor = SegmentationProcessor()
    
    var body: some View {
        ZStack {
            // Live camera preview (shared session)
            SetupCameraPreviewRepresentable(processor: segmentationProcessor)
                .ignoresSafeArea()
            
            // Segmentation overlay image (semi-transparent green silhouette)
            SegmentationOverlayView(processor: segmentationProcessor)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            
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
                
                Spacer()
                
                InstructionCard()
                    .padding(.horizontal, 20)
                
                Spacer()
                
                Button(action: startWorkout) {
                    Text("Start Bodyweight Squat")
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
        }
        .preferredColorScheme(.dark)
        .onAppear { 
            setupCameraForSetupMode()
            segmentationProcessor.stopProcessing()
            segmentationProcessor.setProcessingEnabled(true)
            // Set exercise mode for segmentation scoring
            segmentationProcessor.exerciseMode = .bodyweight
            
            // Add speech feedback for form instructions
            SpeechManager.shared.speak("Go slow and controlled on the way down. Keep your chest tall and core tight")
        }
        .onDisappear { 
            segmentationProcessor.setProcessingEnabled(false)
            // Detach any segmentation delegate to avoid stale callbacks when navigating away
            SharedCameraSessionManager.shared.getVideoDataOutput()?.setSampleBufferDelegate(nil, queue: nil)
        }
        .fullScreenCover(isPresented: $showActiveWorkout) {
            BodyweightSquatActiveWorkoutView(viewModel: viewModel)
        }
    }
    
    private func setupCameraForSetupMode() {
        // Ensure shared session exists and is properly configured
        if SharedCameraSessionManager.shared.getCaptureSession() == nil {
            SharedCameraSessionManager.shared.setupCameraSession()
        }
        SharedCameraSessionManager.shared.switchToSetupMode()
        
        // Ensure session is running for immediate preview
        if let session = SharedCameraSessionManager.shared.getCaptureSession(), !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
            }
        }
    }
    
    private func startWorkout() {
        // Stop segmentation processing before switching to workout mode
        segmentationProcessor.stopProcessing()
        segmentationProcessor.setProcessingEnabled(false)
        
        // Set squat type before navigation
        SharedCameraSessionManager.shared.poseManager.squatType = .bodyweight
        
        // Add speech feedback
        SpeechManager.shared.speak("Let's get it!")
        
        // Navigate to active workout view
        showActiveWorkout = true
    }
}

// MARK: - Instruction Card
private struct InstructionCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Attempt to Place Your Phone:")
                .font(.headline)
                .foregroundColor(.white)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "ruler").foregroundColor(.primaryPurple)
                    Text("6-8' Away")
                        .foregroundColor(.white)
                }
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "angle").foregroundColor(.primaryPurple)
                    Text("45° to Your Body")
                        .foregroundColor(.white)
                }
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "person.fill").foregroundColor(.primaryPurple)
                    Text("At Waist to Chest Height")
                        .foregroundColor(.white)
                }
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "figure.walk").foregroundColor(.primaryPurple)
                    Text("With Feet in View")
                        .foregroundColor(.white)
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
}

