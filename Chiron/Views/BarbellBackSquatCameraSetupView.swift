//
//  BarbellBackSquatCameraSetupView.swift
//  Chiron
//
//  Camera setup view for barbell back squat exercise.
//
//  Purpose:
//  - Guides user to position phone correctly for barbell squats (7-9' away, 45° to front, mid-chest height, feet + barbell in frame)
//  - Displays real-time segmentation overlay with enhanced quality scoring for barbell-specific requirements
//  - Sets exercise mode to .barbell for enhanced segmentation scoring (distance, height, feet visibility)
//  - Navigates to BarbellBackSquatActiveWorkoutView when user taps "Start Barbell Back Squat"
//
//  Architecture:
//  - Uses shared camera session from SharedCameraSessionManager
//  - Uses SegmentationProcessor with exerciseMode = .barbell for enhanced quality scoring
//  - Sets OnDevicePoseManager.squatType = .barbell before navigation
//  - Setup-only view (workout happens in separate active workout view)
//

import SwiftUI
import AVFoundation

struct BarbellBackSquatCameraSetupView: View {
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
            
            // Segmentation overlay image (semi-transparent green/yellow/red silhouette)
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
                
                BarbellInstructionCard()
                    .padding(.horizontal, 20)
                
                Spacer()
                
                Button(action: startWorkout) {
                    Text("Start Barbell Back Squat")
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
            // Set exercise mode for barbell-specific segmentation scoring
            segmentationProcessor.exerciseMode = .barbell
            
            // Add speech feedback for barbell-specific form instructions
            SpeechManager.shared.speak("Position the barbell across your upper traps. Keep the bar path vertical over mid foot. Brace your core before each descent")
        }
        .onDisappear { 
            segmentationProcessor.setProcessingEnabled(false)
            // Detach any segmentation delegate to avoid stale callbacks when navigating away
            SharedCameraSessionManager.shared.getVideoDataOutput()?.setSampleBufferDelegate(nil, queue: nil)
        }
        .fullScreenCover(isPresented: $showActiveWorkout) {
            BarbellBackSquatActiveWorkoutView(viewModel: viewModel)
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
        SharedCameraSessionManager.shared.poseManager.squatType = .barbell
        
        // Add speech feedback
        SpeechManager.shared.speak("Let's get it!")
        
        // Navigate to active workout view
        showActiveWorkout = true
    }
}

// MARK: - Barbell Instruction Card
private struct BarbellInstructionCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Attempt to Place Your Phone:")
                .font(.headline)
                .foregroundColor(.white)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "ruler").foregroundColor(.primaryPurple)
                    Text("7-9' Away")
                        .foregroundColor(.white)
                }
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "angle").foregroundColor(.primaryPurple)
                    Text("45° to the Front of Your Body")
                        .foregroundColor(.white)
                }
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "person.fill").foregroundColor(.primaryPurple)
                    Text("At Mid-Chest or Slightly Above")
                        .foregroundColor(.white)
                }
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "figure.walk").foregroundColor(.primaryPurple)
                    Text("Feet + Barbell in Frame")
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

