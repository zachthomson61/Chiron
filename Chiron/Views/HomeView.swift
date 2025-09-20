import SwiftUI
import AVFoundation

struct HomeScreenSpacing {
    static let topInset: CGFloat = 12
    static let topTitlePad: CGFloat = 8
    static let sectionSpacing: CGFloat = 20
    static let bottomInset: CGFloat = 28
}

struct HomeView: View {
    @StateObject private var viewModel = WorkoutViewModel()
    @State private var showCameraSetup = false
    @State private var showWorkoutGoalPicker = false
    @State private var showExerciseSelection = false
    @State private var showFeedback = false
    @State private var contentHeight: CGFloat = 0
    
    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let h = proxy.size.height
                
                ScrollView {
                    VStack(spacing: HomeScreenSpacing.sectionSpacing) {
                        // HEADER
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Chiron")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .foregroundColor(.textPrimary)
                            Text("Your personal form coach")
                                .font(.subheadline)
                                .foregroundColor(.textSecondary)
                        }
                        .padding(.top, HomeScreenSpacing.topTitlePad)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // CORE
                        VStack(spacing: HomeScreenSpacing.sectionSpacing) {
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

                            // Primary action button - Start Workout
                            // Note: "Build Workout Plan" button moved to Plans tab
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
                        }

                        // FLEX SPACER (shrinks/grows to balance)
                        Spacer()
                            .frame(height: max(0, min(40, h - contentHeight)))
                            .fixedSize()

                        // PREFERENCES
                        VStack(spacing: 12) {
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
                        }
                    }
                    .padding(.horizontal, 20)
                    .background(
                        ViewHeightReader(height: $contentHeight)
                    )
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .scrollDisabled(contentHeight <= h)
                .background(Color.background)
            }
            .safeAreaInset(edge: .top) { 
                Color.clear.frame(height: HomeScreenSpacing.topInset) 
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(action: {
                        showFeedback = true
                    }) {
                        Image(systemName: "text.bubble")
                            .font(.title2)
                            .foregroundColor(.textSecondary)
                    }
                    
                    Button(action: {
                        // TODO: Navigate to settings
                    }) {
                        Image(systemName: "gearshape")
                            .font(.title2)
                            .foregroundColor(.textSecondary)
                    }
                }
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

// Helper to measure the VStack height
struct ViewHeightReader: View {
    @Binding var height: CGFloat
    var body: some View {
        GeometryReader { gp in
            Color.clear
                .preference(key: HeightKey.self, value: gp.size.height)
        }
        .onPreferenceChange(HeightKey.self) { height = $0 }
    }
}

private struct HeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
