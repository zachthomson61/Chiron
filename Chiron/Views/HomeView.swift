import SwiftUI
import AVFoundation

struct HomeView: View {
    @StateObject private var viewModel = WorkoutViewModel()
    @State private var showCameraSetup = false
    @State private var showWorkoutGoalPicker = false
    @State private var showExerciseSelection = false
    @State private var showFeedback = false
    var body: some View {
        ZStack {
            // Background using soft black
            Color.background
                .ignoresSafeArea()

            VStack(spacing: 32) {
                // Header with gear icon in top right
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Chiron")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.textPrimary)
                        Text("Your personal form coach")
                            .font(.subheadline)
                            .foregroundColor(.textSecondary)
                    }
                    Spacer()
                    HStack(spacing: 16) {
                        Button(action: {
                            showFeedback = true
                        }) {
                            Image(systemName: "text.bubble")
                                .font(.title2)
                                .foregroundColor(.textSecondary)
                                .padding(.top, 4)
                        }
                        
                        Button(action: {
                            // TODO: Navigate to settings
                        }) {
                            Image(systemName: "gearshape")
                                .font(.title2)
                                .foregroundColor(.textSecondary)
                                .padding(.top, 4)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)

                // Stats Cards
                HStack(spacing: 16) {
                    StatCard(
                        title: "Total Reps",
                        value: "\(viewModel.totalReps)",
                        icon: "target",
                        color: .primaryPurple
                    )
                    StatCard(
                        title: "Form Score",
                        value: "\(viewModel.formScore)%",
                        icon: "chart.line.uptrend.xyaxis",
                        color: .green
                    )
                }
                .padding(.horizontal)

                // Play Button
                Button(action: {
                    showExerciseSelection = true
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.primaryPurple)
                            .frame(width: 80, height: 80)
                        Image(systemName: "play.fill")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(.textPrimary)
                    }
                }
                .padding(.top, 8)

                // Ready to train section
                VStack(spacing: 8) {
                    Text("Ready to train?")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.textPrimary)
                    Text("Let's work on your squat form")
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                }
                .padding(.top, 8)

                // Start Workout Button
                Button(action: {
                    showExerciseSelection = true
                }) {
                    Text("Start Workout")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.primaryPurple)
                        .cornerRadius(28)
                }
                .padding(.horizontal)
                .padding(.top, 8)

                // Workout Goal Card
                HStack {
                    Image(systemName: "target")
                        .foregroundColor(.textSecondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Workout Goal")
                            .font(.subheadline)
                            .foregroundColor(.textPrimary)
                        Text(viewModel.workoutGoal)
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                    }
                    Spacer()
                    Button("Change") {
                        showWorkoutGoalPicker = true
                    }
                    .font(.subheadline)
                    .foregroundColor(.primaryPurple)
                }
                .padding()
                .background(Color.white.opacity(0.08))
                .cornerRadius(12)
                .padding(.horizontal)
                .padding(.top, 8)

                // Coaching Style Card
                HStack {
                    Image(systemName: "speaker.wave.2")
                        .foregroundColor(.textSecondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Coaching Style")
                            .font(.subheadline)
                            .foregroundColor(.textPrimary)
                        Text(viewModel.coachingStyle)
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                    }
                    Spacer()
                    Button("Change") {
                        // TODO: Show coaching style picker
                    }
                    .font(.subheadline)
                    .foregroundColor(.primaryPurple)
                }
                .padding()
                .background(Color.white.opacity(0.08))
                .cornerRadius(12)
                .padding(.horizontal)
                .padding(.top, 8)

                Spacer()
            }
            .padding(.top, 32)
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showExerciseSelection) {
            ExerciseSelectionView(viewModel: viewModel)
        }
        .sheet(isPresented: $showWorkoutGoalPicker) {
            WorkoutGoalPickerView(viewModel: viewModel)
        }
        .sheet(isPresented: $showFeedback) {
            FeedbackView(viewModel: viewModel)
        }
    }
}

struct WorkoutGoalPickerView: View {
    @ObservedObject var viewModel: WorkoutViewModel
    @Environment(\.dismiss) private var dismiss
    
    private let workoutGoals = ["Hypertrophy", "Strength", "Injury Prevention"]
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.background
                    .ignoresSafeArea()
                
                VStack(spacing: 20) {
                    Text("Select Workout Goal")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.textPrimary)
                        .padding(.top)
                    
                    LazyVStack(spacing: 12) {
                        ForEach(workoutGoals, id: \.self) { goal in
                            Button(action: {
                                viewModel.workoutGoal = goal
                                dismiss()
                            }) {
                                HStack {
                                    Text(goal)
                                        .font(.headline)
                                        .foregroundColor(.textPrimary)
                                    Spacer()
                                    if viewModel.workoutGoal == goal {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.primaryPurple)
                                    }
                                }
                                .padding()
                                .background(viewModel.workoutGoal == goal ? Color.primaryPurple.opacity(0.2) : Color(.systemGray6).opacity(0.3))
                                .cornerRadius(12)
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    Spacer()
                }
            }
        }
        .preferredColorScheme(.dark)
    }
} 
