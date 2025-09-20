import SwiftUI

/// Root tab view that provides the main navigation structure for the app.
/// Contains three tabs: Home, Plans, and Profile, each with their own NavigationStack.
struct RootTabView: View {
    enum Tab: Hashable { 
        case home, plans, profile 
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
        .tint(.primaryPurple)
        .toolbarBackground(Color.background, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(.dark, for: .tabBar)
        .preferredColorScheme(.dark)
        .onChange(of: selectedTab) { _ in
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        }
    }
}

/// Plans screen that displays workout plans and provides access to plan creation.
/// Currently shows an empty state with a call-to-action to create new plans.
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

// MARK: - Preview
#Preview {
    RootTabView()
        .preferredColorScheme(.dark)
}
