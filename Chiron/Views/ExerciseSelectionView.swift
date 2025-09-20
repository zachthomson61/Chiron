import SwiftUI
import AVFoundation

/// Lists supported exercises and lets the user select one to start.
/// Designed to be embedded in a tab (no NavigationView), with its own custom header.
struct ExerciseSelectionView: View {
    @ObservedObject var viewModel: WorkoutViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showCameraSetup = false
    @State private var showSquatVariationSelection = false
    @State private var showSquatSetup = false
    @State private var showActiveWorkout = false
    
    private let exercises = [
        Exercise(name: "Squat", icon: "figure.walk", description: "Lower body strength and stability"),
        Exercise(name: "Deadlift", icon: "figure.strengthtraining.traditional", description: "Full body posterior chain"),
        Exercise(name: "Bench Press", icon: "figure.arms.open", description: "Upper body pushing strength"),
        Exercise(name: "Overhead Press", icon: "figure.arms.open", description: "Shoulder and core stability"),
        Exercise(name: "Pull-ups", icon: "figure.arms.open", description: "Upper body pulling strength"),
        Exercise(name: "Plank", icon: "figure.core.training", description: "Core stability and endurance")
    ]
    
    var body: some View {
        ZStack {
            Color.background
                .ignoresSafeArea()
            VStack {
                // Custom header row (Back + Title + spacer for balance)
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
                    Spacer()
                    Text("Select Exercise")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.textPrimary)
                    Spacer()
                    // Invisible button maintains symmetrical layout
                    Button("") { }
                        .opacity(0)
                }
                .padding(.horizontal)
                
                // Exercise Grid
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 16) {
                        ForEach(exercises) { exercise in
                            ExerciseCard(
                                exercise: exercise,
                                isSelected: viewModel.selectedExercise == exercise.name
                            ) {
                                viewModel.selectedExercise = exercise.name
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                
                Spacer()
                
                // Primary CTA
                Button(action: {
                    if viewModel.selectedExercise == "Squat" {
                        showSquatVariationSelection = true
                    } else {
                        showCameraSetup = true
                    }
                }) {
                    Text("Start \(viewModel.selectedExercise)")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.primaryPurple)
                        .cornerRadius(16)
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showCameraSetup) {
            CameraSetupView()
        }
        .fullScreenCover(isPresented: $showSquatSetup) {
            BodyweightSquatOverview(viewModel: viewModel)
        }
        .fullScreenCover(isPresented: $showSquatVariationSelection) {
            SquatVariationSelectionView(viewModel: viewModel)
        }
        .fullScreenCover(isPresented: $showActiveWorkout) {
            ActiveWorkoutView(viewModel: viewModel)
        }
    }
    
}

struct Exercise: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let description: String
}

struct ExerciseCard: View {
    let exercise: Exercise
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.primaryPurple.opacity(0.2) : Color(.systemGray6).opacity(0.3))
                        .frame(width: 60, height: 60)
                    Image(systemName: exercise.icon)
                        .font(.title2)
                        .foregroundColor(isSelected ? .primaryPurple : .textPrimary)
                }
                
                VStack(spacing: 4) {
                    Text(exercise.name)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.textPrimary)
                    Text(exercise.description)
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                }
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.primaryPurple)
                        .font(.title3)
                }
            }
            .padding()
            .background(isSelected ? Color.primaryPurple.opacity(0.1) : Color(.systemGray6).opacity(0.3))
            .cornerRadius(16)
        }
    }
} 