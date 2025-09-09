 import SwiftUI

struct SquatVariationSelectionView: View {
    @ObservedObject var viewModel: WorkoutViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedVariation: String = "Bodyweight Squats"
    @State private var showSquatOverview = false
    
    private let variations: [String] = [
        "Bodyweight",
        "Goblet",
        "Front",
        "Back"
    ]
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.background
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header with Back and centered title
                    HStack {
                        Button(action: { dismiss() }) {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.left")
                                Text("Back")
                            }
                            .foregroundColor(.textPrimary)
                        }
                        Spacer()
                        Text("Squat Type")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.textPrimary)
                        Spacer()
                        // Invisible spacer to balance the back button
                        Button(action: {}) {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.left")
                                Text("Back")
                            }
                            .foregroundColor(.clear)
                        }
                        .disabled(true)
                    }
                    .padding()
                    
                    Text("Choose your squat variation to get started")
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .padding(.top, 4)
                    
                    ScrollView {
                        VStack(spacing: 16) {
                            VariationCard(
                                leadingIcon: "figure.strengthtraining.functional",
                                title: "Bodyweight Squats",
                                subtitle: "No equipment needed -\nperfect form focus",
                                isSelected: selectedVariation == "Bodyweight Squats",
                                isLocked: false
                            ) {
                                selectedVariation = "Bodyweight Squats"
                            }
                            
                            VariationCard(
                                leadingIcon: "figure.strengthtraining.traditional",
                                title: "Barbell Back Squats",
                                subtitle: "Coming soon",
                                isSelected: selectedVariation == "Barbell Back Squats",
                                isLocked: true
                            ) {
                                // locked
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 12)
                    }
                    
                    Button(action: {
                        showSquatOverview = true
                    }) {
                        Text("Start Bodyweight Squats")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.primaryPurple)
                            .cornerRadius(16)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 20)
                }
            }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showSquatOverview) {
            BodyweightSquatOverview(viewModel: viewModel)
        }
    }
}

private struct VariationCard: View {
    let leadingIcon: String
    let title: String
    let subtitle: String
    let isSelected: Bool
    let isLocked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: {
            guard !isLocked else { return }
            action()
        }) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(isLocked ? Color.white.opacity(0.1) : Color.primaryPurple.opacity(0.25))
                        .frame(width: 56, height: 56)
                    Image(systemName: leadingIcon)
                        .foregroundColor(isLocked ? .textSecondary : .primaryPurple)
                        .font(.title3)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.textPrimary)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundColor(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer()
                
                if isLocked {
                    Image(systemName: "lock.fill")
                        .foregroundColor(.textSecondary)
                } else if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.primaryPurple)
                }
            }
            .padding()
            .background(
                isLocked
                ? Color(.systemGray6).opacity(0.2)
                : (isSelected ? Color.primaryPurple.opacity(0.2) : Color(.systemGray6).opacity(0.3))
            )
            .cornerRadius(16)
        }
        .disabled(isLocked)
        .opacity(isLocked ? 0.6 : 1)
    }
}

 
