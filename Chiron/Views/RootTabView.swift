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
        .onChange(of: selectedTab) { _ in
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
    
    var body: some View {
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
            
            // Empty state
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
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
        }
        .padding()
        .background(Color.background)
        .navigationTitle("Plans")
        .navigationDestination(isPresented: $showPlanBuilder) {
            PlanBuilderView()
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

/// Research screen hosts exercise selection and experimentation tools.
/// The navigation bar is hidden so the content sits flush to the top of the tab.
struct ResearchScreen: View {
    @StateObject private var viewModel = WorkoutViewModel()

    var body: some View {
        ExerciseSelectionView(viewModel: viewModel)
            .navigationBarHidden(true)
    }
}

// MARK: - Preview
#Preview {
    RootTabView()
        .preferredColorScheme(.dark)
}
