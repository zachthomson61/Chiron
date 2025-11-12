import SwiftUI

struct GoalSelectorView: View {
    @ObservedObject var preferencesManager: UserPreferencesManager
    @Binding var isPresented: Bool
    @State private var selectedGoal: PrimaryGoal?
    @State private var hasShownHint = UserDefaults.standard.bool(forKey: "has_shown_goal_hint")
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.background
                    .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Text("What's your primary goal?")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.textPrimary)
                        
                        Text("We'll customize your training to help you achieve it")
                            .font(.subheadline)
                            .foregroundColor(.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)
                    
                    // Goals List
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(PrimaryGoal.allCases) { goal in
                                GoalOptionCard(
                                    goal: goal,
                                    isSelected: selectedGoal == goal,
                                    onTap: {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            selectedGoal = goal
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    // Save Button
                    Button(action: saveGoal) {
                        Text("Save Goal")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                Group {
                                    if selectedGoal != nil {
                                        Color.primaryPurple
                                    } else {
                                        Color.primaryPurple.opacity(0.3)
                                    }
                                }
                            )
                            .cornerRadius(28)
                            .animation(.easeInOut(duration: 0.2), value: selectedGoal)
                    }
                    .disabled(selectedGoal == nil)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.body)
                    .foregroundColor(.textSecondary)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            selectedGoal = preferencesManager.primaryGoal
            AnalyticsManager.shared.trackGoalSelectorOpened(
                currentGoal: preferencesManager.primaryGoal?.rawValue
            )
        }
    }
    
    private func saveGoal() {
        guard let goal = selectedGoal else { return }
        
        // Save the goal
        preferencesManager.primaryGoal = goal
        
        // Mark hint as shown if this was first time
        if !hasShownHint {
            UserDefaults.standard.set(true, forKey: "has_shown_goal_hint")
        }
        
        // Dismiss
        dismiss()
    }
    
    private func dismiss() {
        isPresented = false
    }
}

// MARK: - Goal Option Card
struct GoalOptionCard: View {
    let goal: PrimaryGoal
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(goal.displayName)
                            .font(.headline)
                            .foregroundColor(.textPrimary)
                        
                        Text(goal.description)
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                            .lineLimit(2)
                    }
                    
                    Spacer()
                    
                    // Radio button
                    ZStack {
                        Circle()
                            .strokeBorder(
                                isSelected ? Color.primaryPurple : Color.textSecondary.opacity(0.3),
                                lineWidth: 2
                            )
                            .frame(width: 24, height: 24)
                        
                        if isSelected {
                            Circle()
                                .fill(Color.primaryPurple)
                                .frame(width: 12, height: 12)
                        }
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        isSelected 
                        ? Color.primaryPurple.opacity(0.15)
                        : Color.white.opacity(0.08)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isSelected 
                        ? Color.primaryPurple.opacity(0.3)
                        : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview
struct GoalSelectorView_Previews: PreviewProvider {
    static var previews: some View {
        GoalSelectorView(
            preferencesManager: UserPreferencesManager.shared,
            isPresented: .constant(true)
        )
    }
}

