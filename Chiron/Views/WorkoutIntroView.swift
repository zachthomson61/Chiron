//
//  WorkoutIntroView.swift
//  Chiron
//
//  Full-screen intro view for a predetermined workout, similar to "Trust the Process" design
//

import SwiftUI
import AVKit
import AVFoundation

/// Full-screen intro view for a predetermined workout.
/// Displays workout information with video background, matching the "Trust the Process" design.
struct WorkoutIntroView: View {
    let workout: PredeterminedWorkout
    @Environment(\.dismiss) private var dismiss
    @State private var showProgression = false
    @State private var showSettings = false
    
    var body: some View {
        ZStack {
            // Background video
            if let videoName = workout.videoName {
                CroppedDemoVideoHeader(videoName: videoName)
                    .ignoresSafeArea()
            } else {
                Color.background.ignoresSafeArea()
            }
            
            // Gradient overlay for readability
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.black.opacity(0.0),
                    Color.black.opacity(0.2),
                    Color.black.opacity(0.4),
                    Color.black.opacity(0.6)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack {
                // Top navigation bar
                HStack {
                    Button(action: { dismiss() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .font(.neueMontrealSemiBold(size: 16))
                        .foregroundColor(.white)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                    }
                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                    
                    Spacer()
                    
                    // Settings button
                    Button(action: {
                        showSettings = true
                    }) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)
                
                Spacer()
                
                // Content overlay
                VStack(alignment: .leading, spacing: 0) {
                    // Title and subtitle
                    VStack(alignment: .leading, spacing: 8) {
                        Text(workout.name)
                            .font(.neueMontrealBold(size: 36))
                            .foregroundColor(.textPrimary)
                            .shadow(color: .black.opacity(0.6), radius: 6, x: 0, y: 2)
                        
                        HStack(spacing: 6) {
                            Image(systemName: "figure.strengthtraining.traditional")
                                .font(.system(size: 14))
                            Text(workout.description)
                                .font(.neueMontrealRegular(size: 16))
                        }
                        .foregroundColor(.textPrimary)
                        .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                    
                    // Info card overlay
                    VStack(alignment: .leading, spacing: 12) {
                        // Duration
                        Text("\(workout.duration) min")
                            .font(.neueMontrealBold(size: 18))
                            .foregroundColor(.textPrimary)
                        
                        // Equipment list
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(workout.equipment, id: \.self) { item in
                                Text(item)
                                    .font(.neueMontrealRegular(size: 14))
                                    .foregroundColor(.textPrimary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.black.opacity(0.6))
                            .background(.ultraThinMaterial)
                    )
                    .cornerRadius(16)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                    
                    // Bottom action bar
                    HStack(spacing: 16) {
                        // List button
                        Button(action: {
                            showProgression = true
                        }) {
                            Image(systemName: "list.bullet")
                                .font(.neueMontrealSemiBold(size: 18))
                                .foregroundColor(.textPrimary)
                                .frame(width: 50, height: 50)
                                .background(Color.white.opacity(0.1))
                                .clipShape(Circle())
                        }
                        
                        // Start button
                        Button(action: {
                            // TODO: Navigate to workout start flow
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "play.fill")
                                    .font(.neueMontrealBold(size: 16))
                                Text("Start")
                                    .font(.neueMontrealSemiBold(size: 17))
                            }
                            .foregroundColor(.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.primaryPurple)
                            .cornerRadius(28)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showProgression) {
            WorkoutProgressionView(workout: workout)
        }
        .sheet(isPresented: $showSettings) {
            WorkoutSettingsView()
        }
    }
}

#Preview {
    WorkoutIntroView(workout: WorkoutLibrary.pythonWrangler)
        .preferredColorScheme(.dark)
}

