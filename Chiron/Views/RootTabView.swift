import SwiftUI

/// Root tab view that provides the main navigation structure for the app.
/// Tabs (left→right): Home, Plans, Research, Profile.
/// Each tab is wrapped in its own `NavigationStack` to isolate toolbars and preserve scroll position.
struct RootTabView: View {
    enum Tab: Hashable { 
        case home, research, plans, profile 
    }
    
    @State private var selectedTab: Tab = .home

    var body: some View {
        TabView(selection: $selectedTab) {
            // MARK: - Home Tab
            NavigationStack {
                HomeView()
            }
            .tabItem {
                Image(systemName: "house.fill")
                Text("Home")
            }
            .tag(Tab.home)
            .accessibilityLabel("Home")

            // MARK: - Plans Tab
            NavigationStack {
                PlansScreen()
            }
            .tabItem {
                Image(systemName: "list.bullet.rectangle")
                Text("Plans")
            }
            .tag(Tab.plans)
            .accessibilityLabel("Plans")

            // MARK: - Research Tab
            NavigationStack {
                ResearchScreen()
            }
            .tabItem {
                Image(systemName: "magnifyingglass")
                Text("Research")
            }
            .tag(Tab.research)
            .accessibilityLabel("Research")

            // MARK: - Profile Tab
            NavigationStack {
                ProfileScreen()
            }
            .tabItem {
                Image(systemName: "person.crop.circle")
                Text("Profile")
            }
            .tag(Tab.profile)
            .accessibilityLabel("Profile")
        }
        // Brand and appearance
        .tint(.primaryPurple) // Selected tab tint uses app brand purple
        .toolbarBackground(Color.background, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(.dark, for: .tabBar)
        .preferredColorScheme(.dark)
        .onChange(of: selectedTab) {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred() // Light haptic on tab switch
            #endif
        }
    }
}

/// Plans screen displays saved plans and provides access to plan creation.
/// Currently an empty state with a primary CTA to build a plan.
struct PlansScreen: View {
    @State private var showPlanBuilder = false
    @EnvironmentObject private var planStore: PlanStore
    @State private var selectedPlan: TrainingPlan?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header section
                VStack(spacing: 8) {
                    Text("Plans")
                        .font(.title.bold())
                        .foregroundColor(.textPrimary)
                    Text("Create and manage your workout programs")
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                }
                
                // Primary action button
                Button(action: {
                    showPlanBuilder = true
                }) {
                    Text("Build Workout Plan")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.primaryPurple)
                        .cornerRadius(28)
                }
                .padding(.horizontal)
                
                // Saved Plans Section
                if !planStore.savedPlans.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Saved Plans")
                            .font(.headline)
                            .foregroundColor(.textPrimary)
                            .padding(.horizontal)
                        
                        LazyVStack(spacing: 12) {
                            ForEach(planStore.savedPlans) { plan in
                                Button(action: {
                                    selectedPlan = plan
                                }) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(plan.name)
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                                .foregroundColor(.textPrimary)
                                            
                                            HStack(spacing: 8) {
                                                Text("\(plan.duration) weeks")
                                                    .font(.caption)
                                                    .foregroundColor(.textSecondary)
                                                
                                                Text("•")
                                                    .font(.caption)
                                                    .foregroundColor(.textSecondary)
                                                
                                                Text("\(plan.daysPerWeek) days/week")
                                                    .font(.caption)
                                                    .foregroundColor(.textSecondary)
                                                
                                                Text("•")
                                                    .font(.caption)
                                                    .foregroundColor(.textSecondary)
                                                
                                                Text(plan.createdAt, style: .date)
                                                    .font(.caption)
                                                    .foregroundColor(.textSecondary)
                                            }
                                        }
                                        
                                        Spacer()
                                        
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundColor(.textSecondary)
                                    }
                                    .padding()
                                    .background(Color.background)
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.primaryPurple.opacity(0.3), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.horizontal)
                    }
                } else {
                    // Empty state when no plans
                    VStack(spacing: 16) {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.system(size: 48))
                            .foregroundColor(.textSecondary)
                        
                        Text("No plans yet")
                            .font(.headline)
                            .foregroundColor(.textPrimary)
                        
                        Text("Create a program to get started with structured training")
                            .font(.subheadline)
                            .foregroundColor(.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 40)
                }
            }
            .padding()
        }
        .background(Color.background)
        .navigationDestination(isPresented: $showPlanBuilder) {
            PlanBuilderView()
        }
        // Navigate to a simple plan preview when a saved plan is tapped.
        // This uses the existing `TrainingPlan` model from the builder and
        // shows details via `PlanPreviewView` without altering Plans UI.
        .navigationDestination(isPresented: Binding(
            get: { selectedPlan != nil },
            set: { if !$0 { selectedPlan = nil } }
        )) {
            if let plan = selectedPlan {
                PlanPreviewView(plan: plan)
            }
        }
    }
}

/// Profile screen placeholder for user settings and account management.
struct ProfileScreen: View {
    var body: some View {
        Form {
            Section(header: Text("Account")) {
                Text("Name")
                Text("Email")
            }
            Section(header: Text("Preferences")) {
                Toggle("Haptics", isOn: .constant(true))
            }
        }
        .navigationTitle("Profile")
    }
}

/// Research screen provides exercise selection without navigation controls.
/// Replicates ExerciseSelectionView layout but removes back button for tab context.
struct ResearchScreen: View {
    @StateObject private var viewModel = WorkoutViewModel()
    
    // Same exercise data as ExerciseSelectionView
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
            Color.background.ignoresSafeArea()
            
            VStack {
                // Centered title (no back button for tab context)
                Text("Select Exercise")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.textPrimary)
                    .padding(.horizontal)
                
                // Exercise selection grid
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
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
                
                // Start exercise button
                Button(action: {
                    // TODO: Implement exercise start flow
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
        .navigationBarHidden(true)
    }
}


// MARK: - Preview
#Preview {
    RootTabView()
        .preferredColorScheme(.dark)
}
