import SwiftUI

// MARK: - Affirmation Toast View

struct AffirmationToastView: View {
    let text: String
    @Binding var isVisible: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if isVisible {
            Text(text)
                .font(.neueMontrealSemiBold(size: 15))
                .foregroundColor(Color.pureWhite)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.primaryPurple.opacity(0.15))
                .cornerRadius(12)
                .frame(maxWidth: 280)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .move(edge: .top).combined(with: .opacity)
                )
                .accessibilityLabel(text)
                .accessibilityAddTraits(.isStaticText)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct AffirmationToastView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.softBlack.ignoresSafeArea()
            VStack {
                AffirmationToastView(
                    text: "Strong choice.",
                    isVisible: .constant(true)
                )
                Spacer()
            }
            .padding(.top, 60)
        }
    }
}
#endif
