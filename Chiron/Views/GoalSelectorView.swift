import SwiftUI

struct GoalSelectorView: View {
    @ObservedObject var preferencesManager: UserPreferencesManager
    @Binding var isPresented: Bool
    @State private var selectedGoal: PrimaryGoal?
    @State private var hasShownHint = UserDefaults.standard.bool(forKey: "has_shown_goal_hint")
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.background
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // Leave room for the dismiss chevron overlay.
                Spacer().frame(height: 48)

                // Header
                VStack(spacing: 8) {
                    Text("What's your primary goal?")
                        .font(.neueMontrealBold(size: 22))
                        .foregroundColor(.textPrimary)

                    Text("We'll customize your training to help you achieve it")
                        .font(.neueMontrealRegular(size: 15))
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                }

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
                        .font(.neueMontrealSemiBold(size: 17))
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

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(Color.black.opacity(0.35))
                    .clipShape(Circle())
            }
            .padding(.leading, 16)
            .padding(.top, 12)
            .accessibilityLabel("Dismiss")
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
                            .font(.neueMontrealBold(size: 17))
                            .foregroundColor(.textPrimary)
                        
                        Text(goal.description)
                            .font(.neueMontrealRegular(size: 12))
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




