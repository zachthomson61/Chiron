import SwiftUI
import SwiftData

/// Root tab view that provides the main navigation structure for the app.
/// Tabs (left→right): Home, Track, Research, Profile.
/// Each tab is wrapped in its own `NavigationStack` to isolate toolbars and preserve scroll position.
/// Optimized: Views are lazily loaded only when their tab is first selected.
struct RootTabView: View {
    enum Tab: Hashable {
        case home, track, research, profile
    }

    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab: Tab = .home
    @State private var loadedTabs: Set<Tab> = [.home] // Track which tabs have been loaded
    @State private var hasPreloadedData = false
    /// Global PR celebration publisher. Mounting the confetti overlay at the
    /// tab-view root means any workout flow (Track tab, predetermined
    /// workouts) fires into the same surface without needing to own its own
    /// overlay. The view is non-hit-testing so it doesn't block interaction.
    @ObservedObject private var prCelebration = PRCelebrationCenter.shared

    var body: some View {
        ZStack {
        TabView(selection: $selectedTab) {
            // MARK: - Home Tab
            NavigationStack {
                HomeView {
                    // "Start Training" hops directly to the Track tab so the
                    // tab bar stays in place while the camera-driven session
                    // mounts inside its own NavigationStack.
                    selectedTab = .track
                }
            }
            .tabItem {
                Image(systemName: "house.fill")
                Text("Home")
            }
            .tag(Tab.home)
            .accessibilityLabel("Home")

            // MARK: - Track Tab
            NavigationStack {
                if loadedTabs.contains(.track) {
                    TrackView()
                } else {
                    Color.clear.onAppear { loadedTabs.insert(.track) }
                }
            }
            .tabItem {
                Image(systemName: "figure.run")
                Text("Track")
            }
            .tag(Tab.track)
            .accessibilityLabel("Track")

            // MARK: - Research Tab (Exercise Library)
            NavigationStack {
                if loadedTabs.contains(.research) {
                    ExerciseLibraryView()
                } else {
                    Color.clear.onAppear { loadedTabs.insert(.research) }
                }
            }
            .tabItem {
                Image(systemName: "magnifyingglass")
                Text("Research")
            }
            .tag(Tab.research)
            .accessibilityLabel("Research")

            // MARK: - Profile Tab
            NavigationStack {
                if loadedTabs.contains(.profile) {
                    ProfileView()
                } else {
                    Color.clear.onAppear { loadedTabs.insert(.profile) }
                }
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
        .task {
            guard !hasPreloadedData else { return }
            hasPreloadedData = true

            do {
                try ExerciseSeeder.seedIfNeeded(context: modelContext)
            } catch {
            }
        }
        .onChange(of: selectedTab) {
            // Ensure the tab is marked as loaded when selected
            loadedTabs.insert(selectedTab)

            // `TrackView.onAppear` may not run again when returning to this tab; coached workouts leave the shared session in setup mode, which blocks `captureOutput` and rep tracking until we re-attach the workout delegate.
            if selectedTab == .track {
                SharedCameraSessionManager.shared.switchToWorkoutMode()
            }

            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred() // Light haptic on tab switch
            #endif
        }

            // PR celebration — rendered above the tab bar so the burst covers
            // the whole screen. `ConfettiView` clears itself when its burst
            // finishes, flipping `isShowingConfetti` back to false.
            ConfettiView(isActive: $prCelebration.isShowingConfetti)
                .allowsHitTesting(false)

            // Badge unlock celebration — sits above the rest of the UI like
            // the PR confetti so any flow that awards a badge (TrackView's
            // endSet, the onboarding hand-off) animates into the same surface
            // without needing per-screen plumbing.
            BadgeUnlockOverlay()
        }
    }
}

// MARK: - Preview
#Preview {
    RootTabView()
        .modelContainer(for: Exercise.self, inMemory: true)
        .preferredColorScheme(.dark)
}
