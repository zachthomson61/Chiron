import SwiftUI
import SwiftData

/// Root tab view that provides the main navigation structure for the app.
/// Tabs (left→right): Home, Plans, Research, Profile.
/// Each tab is wrapped in its own `NavigationStack` to isolate toolbars and preserve scroll position.
/// Optimized: Views are lazily loaded only when their tab is first selected.
struct RootTabView: View {
    enum Tab: Hashable { 
        case home, research, plans, profile 
    }
    
    @EnvironmentObject private var planStore: PlanStore
    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab: Tab = .home
    @State private var loadedTabs: Set<Tab> = [.home] // Track which tabs have been loaded
    @State private var hasPreloadedData = false

    var body: some View {
        TabView(selection: $selectedTab) {
            // MARK: - Home Tab
            NavigationStack {
                HomeView {
                    // Keep the tab bar visible by hopping directly to Research,
                    // which already hosts the shared ExerciseLibrary experience.
                    selectedTab = .research
                }
            }
            .tabItem {
                Image(systemName: "house.fill")
                Text("Home")
            }
            .tag(Tab.home)
            .accessibilityLabel("Home")

            // MARK: - Plans Tab
            NavigationStack {
                if loadedTabs.contains(.plans) {
                    PlansScreen()
                } else {
                    Color.clear.onAppear { loadedTabs.insert(.plans) }
                }
            }
            .tabItem {
                Image(systemName: "list.bullet.rectangle")
                Text("Plans")
            }
            .tag(Tab.plans)
            .accessibilityLabel("Plans")

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
                    ProfileScreen()
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
            
            planStore.loadPlansIfNeeded()
            
            do {
                try ExerciseSeeder.seedIfNeeded(context: modelContext)
            } catch {
                print("Exercise seeding failed: \(error)")
            }
        }
        .onChange(of: selectedTab) {
            // Ensure the tab is marked as loaded when selected
            loadedTabs.insert(selectedTab)
            
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
        List {
            Section {
                VStack(spacing: 16) {
                    VStack(spacing: 8) {
                        Text("Plans")
                            .font(.title.bold())
                            .foregroundColor(.textPrimary)
                        Text("Create and manage your workout programs")
                            .font(.subheadline)
                            .foregroundColor(.textSecondary)
                    }
                    
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
                }
                .padding(.vertical, 8)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            
            if !planStore.savedPlans.isEmpty {
                Section {
                    ForEach(planStore.savedPlans) { plan in
                    Button(action: {
                        // Keep the pinned plan consistent so the home card knows what to show.
                        planStore.markPlanSelected(plan)
                        selectedPlan = plan
                    }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(plan.name)
                                        .font(.title3)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.textPrimary)
                                    
                                    if !plan.goals.isEmpty {
                                        Text(plan.goals.map { $0.rawValue }.joined(separator: ", "))
                                            .font(.subheadline)
                                            .foregroundColor(.textSecondary)
                                    }
                                    
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
                                    .stroke(Color.primaryPurple.opacity(0.5), lineWidth: 2)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                planStore.deletePlan(withId: plan.id)
                                if selectedPlan?.id == plan.id {
                                    selectedPlan = nil
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                } header: {
                    Text("Saved Plans")
                        .font(.headline)
                        .foregroundColor(.textPrimary)
                        .padding(.bottom, 4)
                }
            } else {
                Section {
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
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 80)
                }
                .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.background)
        .onAppear {
            // Load plans lazily when view appears
            planStore.loadPlansIfNeeded()
        }
        .navigationDestination(isPresented: $showPlanBuilder) {
            PlanBuilderView(isPresented: $showPlanBuilder)
        }
        // Navigate to a simple plan preview when a saved plan is tapped.
        // This uses the existing `TrainingPlan` model from the builder and
        // shows details via `PlanPreviewView` without altering Plans UI.
        .navigationDestination(isPresented: Binding(
            get: { selectedPlan != nil },
            set: { if !$0 { selectedPlan = nil } }
        )) {
            if let plan = selectedPlan {
                PlanPreviewView(plan: plan, source: .savedList)
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
            Section(header: Text("Training")) {
                NavigationLink("Training Log") {
                    ExerciseLibraryView()
                }
            }
        }
        .navigationTitle("Profile")
    }
}

// MARK: - Preview
#Preview {
    RootTabView()
        .modelContainer(for: Exercise.self, inMemory: true)
        .preferredColorScheme(.dark)
}
