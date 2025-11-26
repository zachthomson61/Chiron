import SwiftUI

/// Workout selection menu for users to choose from preloaded workouts.
/// Currently displays a minimal placeholder structure - workouts will be populated later.
struct WorkoutSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.background
                    .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Text("Select Workout")
                            .font(.neueMontrealBold(size: 22))
                            .foregroundColor(.textPrimary)
                        
                        Text("Choose a workout to get started")
                            .font(.neueMontrealRegular(size: 15))
                            .foregroundColor(.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)
                    
                    // Placeholder content area
                    VStack(spacing: 16) {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(.system(size: 48))
                            .foregroundColor(.textSecondary)
                        
                        Text("Workouts coming soon")
                            .font(.neueMontrealBold(size: 18))
                            .foregroundColor(.textPrimary)
                        
                        Text("Preloaded workouts will appear here")
                            .font(.neueMontrealRegular(size: 15))
                            .foregroundColor(.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.textSecondary)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    WorkoutSelectionView()
}

