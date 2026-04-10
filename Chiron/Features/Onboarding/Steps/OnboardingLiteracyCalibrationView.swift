import SwiftUI

// MARK: - Quiz Option Model (file-private)

private struct LiteracyQuizOption: Identifiable {
    let id: String
    let label: String
    let description: String
    let angleDegrees: String
}

// MARK: - Screen 09: Literacy Calibration (Visual Quiz)

struct OnboardingLiteracyCalibrationView: View, OnboardingScreen {
    let screenId = "screen_09"
    @ObservedObject var coordinator: OnboardingCoordinator
    @State private var selectedAnswer: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let options: [LiteracyQuizOption] = [
        LiteracyQuizOption(id: "quarter_squat", label: "A", description: "Standing, knees barely bent", angleDegrees: "~160"),
        LiteracyQuizOption(id: "half_squat", label: "B", description: "Hips above knee level", angleDegrees: "~120"),
        LiteracyQuizOption(id: "parallel_squat", label: "C", description: "Hip crease at knee level", angleDegrees: "~90"),
        LiteracyQuizOption(id: "atg_squat", label: "D", description: "Hips well below knees", angleDegrees: "~70"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Spacer().frame(height: 24)

                Text("Which image shows a squat at parallel depth?")
                    .font(.neueMontrealBold(size: 28))
                    .foregroundColor(Color.pureWhite)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 16)

                Text("Tap the one you think is right. This helps us speak your language.")
                    .font(.neueMontrealRegular(size: 17))
                    .foregroundColor(Color.textSecondary)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 16)

                // 2x2 grid of visual options
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                ], spacing: 12) {
                    ForEach(options) { option in
                        SquatImageTile(
                            option: option,
                            isSelected: selectedAnswer == option.id,
                            isDimmed: selectedAnswer != nil && selectedAnswer != option.id,
                            action: {
                                guard selectedAnswer == nil else { return }
                                handleSelection(option.id)
                            }
                        )
                    }
                }
                .padding(.horizontal, 16)

                Spacer()
            }
        }
        .accessibilityHint("Four squat position illustrations are shown. Tap the one that shows a squat at parallel depth, where the hip crease is level with the knee.")
    }

    private func handleSelection(_ answerId: String) {
        withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.12)) {
            selectedAnswer = answerId
        }

        coordinator.setLiteracyCalibration(answerId: answerId)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            coordinator.showAffirmationToast("That tells us a lot.", forScreen: screenId)
        }

        // Slightly longer delay for visual quiz
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            coordinator.completeScreen(screenId, answer: answerId)
        }
    }
}

// MARK: - Squat Image Tile

private struct SquatImageTile: View {
    let option: LiteracyQuizOption
    let isSelected: Bool
    let isDimmed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                // Silhouette placeholder (SF Symbol approximation)
                VStack(spacing: 8) {
                    Image(systemName: "figure.stand")
                        .font(.system(size: 44))
                        .foregroundColor(Color.pureWhite.opacity(0.6))
                        .rotationEffect(.degrees(rotationForOption))

                    Text(option.description)
                        .font(.neueMontrealRegular(size: 11))
                        .foregroundColor(Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 140)
                .background(Color.white.opacity(0.06))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            isSelected ? Color.primaryPurple : Color.clear,
                            lineWidth: 3
                        )
                )
                .opacity(isDimmed ? 0.5 : 1.0)

                // Label badge
                Text(option.label)
                    .font(.neueMontrealBold(size: 14))
                    .foregroundColor(Color.pureWhite)
                    .frame(width: 28, height: 28)
                    .background(Color.primaryPurple.opacity(isSelected ? 1.0 : 0.4))
                    .cornerRadius(6)
                    .padding(8)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel("Option \(option.label): \(option.description)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Provides a visual rotation hint for different squat depths.
    private var rotationForOption: Double {
        switch option.id {
        case "quarter_squat": return 0
        case "half_squat": return -10
        case "parallel_squat": return -20
        case "atg_squat": return -30
        default: return 0
        }
    }
}
