import SwiftUI

// MARK: - Plan Field Model

struct PlanField: Identifiable, Codable {
    let id: String
    let label: String
    var value: String?
    var isRevealed: Bool

    static func defaultFields() -> [PlanField] {
        [
            PlanField(id: "primary_goal", label: "Goal", value: nil, isRevealed: false),
            PlanField(id: "experience", label: "Experience", value: nil, isRevealed: false),
            PlanField(id: "environment", label: "Environment", value: nil, isRevealed: false),
            PlanField(id: "coaching_style", label: "Coaching Style", value: nil, isRevealed: false),
            PlanField(id: "focus", label: "Focus", value: nil, isRevealed: false),
            PlanField(id: "safety_mode", label: "Safety Mode", value: nil, isRevealed: false),
            PlanField(id: "ai_coach", label: "AI Coach", value: nil, isRevealed: false),
        ]
    }
}

// MARK: - Plan Reveal Card View

struct PlanRevealCardView: View {
    let revealProgress: CGFloat
    let fields: [PlanField]
    let isComplete: Bool

    @State private var cardScale: CGFloat = 1.0
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(revealProgress: CGFloat, fields: [PlanField], isComplete: Bool = false) {
        self.revealProgress = revealProgress
        self.fields = fields
        self.isComplete = isComplete
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Your Plan")
                    .font(.neueMontrealSemiBold(size: 15))
                    .foregroundColor(Color.pureWhite)
                Spacer()
                if revealProgress < 1.0 {
                    Text("\(Int(revealProgress * 100))%")
                        .font(.neueMontrealRegular(size: 13))
                        .foregroundColor(Color.textSecondary)
                }
            }
            .padding(.bottom, 4)

            ForEach(fields) { field in
                PlanFieldRow(field: field)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.08))
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    borderColor,
                    lineWidth: 1
                )
        )
        .padding(.horizontal, 16)
        .scaleEffect(cardScale)
        .onAppear {
            guard !appeared else { return }
            appeared = true
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var borderColor: Color {
        revealProgress >= 1.0
            ? Color.primaryPurple.opacity(0.6)
            : Color.primaryPurple.opacity(0.2)
    }

    private var accessibilityDescription: String {
        let revealedFields = fields.filter { $0.isRevealed }
        let fieldDescriptions = revealedFields.compactMap { field -> String? in
            guard let value = field.value else { return nil }
            return "\(field.label): \(value)"
        }
        let percent = Int(revealProgress * 100)
        return "Your plan, \(percent) percent complete. \(fieldDescriptions.joined(separator: ". "))"
    }

    func triggerCompletionPulse() -> some View {
        self.onAppear {
            guard !reduceMotion else { return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                cardScale = 1.03
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                    cardScale = 1.0
                }
            }
        }
    }
}

// MARK: - Plan Field Row

private struct PlanFieldRow: View {
    let field: PlanField
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack {
            Text(field.label)
                .font(.neueMontrealRegular(size: 14))
                .foregroundColor(Color.textSecondary)
                .frame(width: 100, alignment: .leading)

            Spacer()

            if field.isRevealed, let value = field.value {
                Text(value)
                    .font(.neueMontrealSemiBold(size: 14))
                    .foregroundColor(Color.pureWhite)
                    .transition(.opacity)
            } else {
                // Skeleton placeholder
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.4))
                    .frame(width: 80, height: 14)
                    .blur(radius: 8)
            }
        }
        .frame(height: 24)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(field.isRevealed ? "\(field.label): \(field.value ?? "")" : "\(field.label): not yet revealed")
    }
}

// MARK: - Preview

#if DEBUG
struct PlanRevealCardView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.softBlack.ignoresSafeArea()
            PlanRevealCardView(
                revealProgress: 0.45,
                fields: [
                    PlanField(id: "primary_goal", label: "Goal", value: "Build muscle", isRevealed: true),
                    PlanField(id: "experience", label: "Experience", value: "1-3 years", isRevealed: true),
                    PlanField(id: "environment", label: "Environment", value: nil, isRevealed: false),
                    PlanField(id: "coaching_style", label: "Coaching Style", value: nil, isRevealed: false),
                    PlanField(id: "focus", label: "Focus", value: nil, isRevealed: false),
                    PlanField(id: "safety_mode", label: "Safety Mode", value: nil, isRevealed: false),
                    PlanField(id: "ai_coach", label: "AI Coach", value: nil, isRevealed: false),
                ]
            )
        }
    }
}
#endif
