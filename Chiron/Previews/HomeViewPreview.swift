import SwiftUI

// Preview wrapper for testing HomeView in isolation
struct HomeViewPreview: View {
    var body: some View {
        HomeView()
            .preferredColorScheme(.dark)
    }
}

struct HomeViewPreview_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Standard iPhone
            HomeViewPreview()
                .previewDevice("iPhone 15")
                .previewDisplayName("iPhone 15")
            
            // Smaller device
            HomeViewPreview()
                .previewDevice("iPhone SE (3rd generation)")
                .previewDisplayName("iPhone SE")
            
            // Dynamic Type - Large
            HomeViewPreview()
                .environment(\.sizeCategory, .extraLarge)
                .previewDisplayName("Extra Large Text")
            
            // First Run Experience (no goal set)
            HomeViewPreview()
                .onAppear {
                    UserDefaults.standard.removeObject(forKey: "user_primary_goal")
                    UserDefaults.standard.removeObject(forKey: "has_shown_goal_hint")
                }
                .previewDisplayName("First Run")
        }
    }
}

// Test different goal states
struct GoalStatesPreview: View {
    @StateObject private var preferencesManager = UserPreferencesManager.shared
    
    var body: some View {
        TabView {
            // No goal set
            HomeView()
                .tabItem { Label("No Goal", systemImage: "questionmark.circle") }
                .onAppear {
                    preferencesManager.primaryGoal = nil
                }
            
            // Lose fat goal
            HomeView()
                .tabItem { Label("Lose Fat", systemImage: "flame") }
                .onAppear {
                    preferencesManager.primaryGoal = .loseFat
                }
            
            // Build muscle goal
            HomeView()
                .tabItem { Label("Build Muscle", systemImage: "figure.strengthtraining.traditional") }
                .onAppear {
                    preferencesManager.primaryGoal = .buildMuscle
                }
            
            // Endurance goal
            HomeView()
                .tabItem { Label("Endurance", systemImage: "figure.run") }
                .onAppear {
                    preferencesManager.primaryGoal = .improveEndurance
                }
        }
        .preferredColorScheme(.dark)
    }
}

struct GoalStatesPreview_Previews: PreviewProvider {
    static var previews: some View {
        GoalStatesPreview()
            .previewDisplayName("Goal States")
    }
}



