//
//  WorkoutSelectionView.swift
//  Chiron
//
//  Modal view for selecting from predetermined workouts
//

import SwiftUI

/// Modal view that displays available predetermined workouts in a two-column grid.
/// Presented as a sheet from HomeView when "Start Workout" is tapped.
struct WorkoutSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedWorkout: PredeterminedWorkout?
    
    var body: some View {
            ZStack {
                Color.background.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 0) {
                        // Header section
                        VStack(spacing: 8) {
                            Text("Select Workout")
                                .font(.neueMontrealBold(size: 32))
                                .foregroundColor(.textPrimary)
                        }
                        .padding(.top, 20)
                        .padding(.bottom, 24)
                        
                        // Two-column grid of workout cards
                        if WorkoutLibrary.workouts.isEmpty {
                            // Empty state
                            VStack(spacing: 16) {
                                Image(systemName: "figure.strengthtraining.traditional")
                                    .font(.system(size: 48))
                                    .foregroundColor(.textSecondary)
                                
                                Text("Workouts coming soon")
                                    .font(.neueMontrealBold(size: 20))
                                    .foregroundColor(.textPrimary)
                                
                                Text("Preloaded workouts will appear here")
                                    .font(.neueMontrealRegular(size: 14))
                                    .foregroundColor(.textSecondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 80)
                        } else {
                            LazyVGrid(
                                columns: [
                                    GridItem(.flexible(), spacing: 12),
                                    GridItem(.flexible(), spacing: 12)
                                ],
                                spacing: 16
                            ) {
                                ForEach(WorkoutLibrary.workouts) { workout in
                                    Button(action: {
                                        selectedWorkout = workout
                                    }) {
                                        WorkoutCard(workout: workout)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 20)
                        }
                    }
                }
                
                // Close button in top-right
                VStack {
                    HStack {
                        Spacer()
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark")
                                .font(.neueMontrealSemiBold(size: 16))
                                .foregroundColor(.textPrimary)
                                .frame(width: 32, height: 32)
                                .background(Color.white.opacity(0.1))
                                .clipShape(Circle())
                        }
                        .padding(.trailing, 20)
                        .padding(.top, 20)
                    }
                    Spacer()
                }
                .allowsHitTesting(false)
                .overlay(
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.neueMontrealSemiBold(size: 16))
                            .foregroundColor(.textPrimary)
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .padding(.trailing, 20)
                    .padding(.top, 20),
                    alignment: .topTrailing
                )
            }
            .fullScreenCover(item: $selectedWorkout) { workout in
                WorkoutIntroView(workout: workout)
            }
            .preferredColorScheme(.dark)
    }
}

// MARK: - Workout Card Component

/// Card component for displaying a workout in the selection grid.
private struct WorkoutCard: View {
    let workout: PredeterminedWorkout
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Workout name
            Text(workout.name)
                .font(.neueMontrealBold(size: 18))
                .foregroundColor(.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            
            // Description
            Text(workout.description)
                .font(.neueMontrealRegular(size: 13))
                .foregroundColor(.textSecondary)
                .lineLimit(3)
                .lineSpacing(2)
            
            Spacer(minLength: 12)
            
            // Bottom row: Duration and difficulty (anchored at bottom)
            HStack {
                // Duration (kept on one line)
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 12))
                    Text("\(workout.duration) min")
                        .font(.neueMontrealRegular(size: 12))
                        .lineLimit(1)
                }
                .foregroundColor(.textSecondary)
                .fixedSize(horizontal: true, vertical: false)
                
                Spacer()
                
                // Difficulty pill (fixed size so "Intermediate" etc. always fits)
                DifficultyPill(difficulty: workout.difficulty)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(12)
        .frame(height: 158)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primaryPurple.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Difficulty Pill

/// Small pill component showing workout difficulty level.
private struct DifficultyPill: View {
    let difficulty: DifficultyLevel
    
    var body: some View {
        Text(difficulty.rawValue)
            .font(.neueMontrealSemiBold(size: 11))
            .foregroundColor(pillForegroundColor)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(pillBackgroundColor)
            .clipShape(Capsule())
    }
    
    private var pillBackgroundColor: Color {
        switch difficulty {
        case .beginner:
            return Color.brandAccentPurple.opacity(0.18)
        case .intermediate:
            return Color.intermediateYellow.opacity(0.18)
        case .advanced:
            return Color.expertRed.opacity(0.18)
        }
    }
    
    private var pillForegroundColor: Color {
        switch difficulty {
        case .beginner:
            return Color.brandAccentPurple
        case .intermediate:
            return Color.intermediateYellow
        case .advanced:
            return Color.expertRed
        }
    }
}

#Preview {
    WorkoutSelectionView()
        .preferredColorScheme(.dark)
}

