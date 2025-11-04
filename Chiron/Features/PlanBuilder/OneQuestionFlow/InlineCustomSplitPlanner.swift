import SwiftUI

/// Inline week planner that appears when the user selects "Custom" split.
/// Lets users set a focus per day (Upper/Lower/Arms/Push/Pull/Legs/Full Body)
/// and optionally choose specific muscles for a day.
/// This view is UI-only (no persistence); generation uses overall split choice.
struct InlineCustomSplitPlanner: View {
    private let days = ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"]

    @State private var selectedDayIndex: Int = 0
    @State private var intents: [DayIntent] = Array(repeating: .fullBody, count: 7)
    @State private var customMuscles: [Int: Set<MuscleGroup>] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(days.indices, id: \.self) { i in
                        Button(action: { selectedDayIndex = i }) {
                            VStack(spacing: 4) {
                                Text(days[i])
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(selectedDayIndex == i ? .textPrimary : .planTextPrimary)
                                Text(intentLabel(for: intents[i]))
                                    .font(.caption2)
                                    .foregroundColor(.planTextSecondary)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(selectedDayIndex == i ? Color.planAccent : Color.planCardBackground)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Day \(selectedDayIndex + 1) Focus")
                    .font(.headline)
                    .foregroundColor(.planTextPrimary)

                let options: [DayIntent] = [.upper, .lower, .arms, .push, .pull, .legs, .fullBody, .customMuscles]
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 10) {
                    ForEach(options, id: \.self) { intent in
                        Button(action: {
                            intents[selectedDayIndex] = intent
                            if intent != .customMuscles { customMuscles[selectedDayIndex] = nil }
                        }) {
                            HStack {
                                Text(intent.rawValue)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.planTextPrimary)
                                Spacer()
                                if intents[selectedDayIndex] == intent {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.planAccent)
                                }
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(intents[selectedDayIndex] == intent ? Color.planCardBackgroundSelected : Color.planCardBackground)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }

                if intents[selectedDayIndex] == .customMuscles {
                    MuscleGroupGrid(
                        muscles: MuscleGroup.allCases,
                        selected: customMuscles[selectedDayIndex] ?? [],
                        onToggle: { m in
                            var set = customMuscles[selectedDayIndex] ?? []
                            if set.contains(m) { set.remove(m) } else { set.insert(m) }
                            customMuscles[selectedDayIndex] = set
                        }
                    )
                    .padding(.top, 4)
                }
            }
            .padding()
            .background(Color.planCardBackground)
            .cornerRadius(12)
        }
    }

    private func intentLabel(for intent: DayIntent) -> String {
        switch intent {
        case .upper: return "Upper"
        case .lower: return "Lower"
        case .arms: return "Arms"
        case .push: return "Push"
        case .pull: return "Pull"
        case .legs: return "Legs"
        case .fullBody: return "Full Body"
        case .customMuscles: return "Specific"
        }
    }
}
