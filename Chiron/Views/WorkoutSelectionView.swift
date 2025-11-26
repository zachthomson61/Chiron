import SwiftUI

/// Workout selection menu presented as a sheet modal from HomeView.
///
/// This view allows users to select from preloaded workouts when they tap
/// "Start Workout" from the home screen. Currently displays a placeholder
/// empty state - workout data will be populated in a future update.
///
/// **Accessibility:** Only accessible from HomeView via sheet presentation.
struct WorkoutSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.background
                    .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    // Header Section
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
                    
                    // Empty State Placeholder
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

