import SwiftUI

// MARK: - Muscle Multi-Select Component

struct MuscleMultiSelectView: View {
    let selected: Set<MuscleGroup>
    let onToggle: (MuscleGroup) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PlanSectionHeader(
                title: "Select Muscles",
                subtitle: "Choose the muscle groups for this day"
            )
            
            MuscleGroupGrid(
                muscles: MuscleGroup.allCases,
                selected: selected,
                onToggle: onToggle
            )
        }
        .planCardStyle()
    }
}

// MARK: - Preview

#Preview {
    MuscleMultiSelectView(
        selected: [.chest, .back],
        onToggle: { _ in }
    )
    .padding()
    .background(Color.planBackground)
    .preferredColorScheme(.dark)
}
