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
    @State private var selectedWorkoutId: UUID?
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.background.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 0) {
                        // Header section
                        VStack(spacing: 8) {
                            Text("Select Workout")
                                .font(.neueMontrealBold(size: 32))
                                .foregroundColor(.textPrimary)
                            
                            Text("Choose a workout to get started")
                                .font(.neueMontrealRegular(size: 16))
                                .foregroundColor(.textSecondary)
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
                                    NavigationLink(value: workout.id) {
                                        WorkoutCard(workout: workout)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 20)
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
            .navigationDestination(for: UUID.self) { workoutId in
                if let workout = WorkoutLibrary.workouts.first(where: { $0.id == workoutId }) {
                    WorkoutIntroView(workout: workout)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Workout Card Component

/// Card component for displaying a workout in the selection grid.
private struct WorkoutCard: View {
    let workout: PredeterminedWorkout
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Workout name
            Text(workout.name)
                .font(.neueMontrealBold(size: 18))
                .foregroundColor(.textPrimary)
                .lineLimit(2)
            
            // Description
            Text(workout.description)
                .font(.neueMontrealRegular(size: 13))
                .foregroundColor(.textSecondary)
                .lineLimit(2)
            
            Spacer()
            
            // Bottom row: Duration and difficulty
            HStack {
                // Duration
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 12))
                    Text("\(workout.duration) min")
                        .font(.neueMontrealRegular(size: 12))
                }
                .foregroundColor(.textSecondary)
                
                Spacer()
                
                // Difficulty pill
                DifficultyPill(difficulty: workout.difficulty)
            }
        }
        .padding(16)
        .frame(height: 140)
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

