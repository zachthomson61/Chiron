import SwiftUI

// MARK: - Custom Split View

struct CustomSplitView: View {
    @StateObject private var viewModel: CustomSplitViewModel
    @Environment(\.dismiss) private var dismiss
    
    init(input: PlanBuilderInput, onSave: @escaping (CustomSplit) -> Void) {
        self._viewModel = StateObject(wrappedValue: CustomSplitViewModel(input: input, onSave: onSave))
    }
    
    var body: some View {
        ZStack {
            // Background
            Color.planBackground
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                headerSection
                
                // Day Pills
                dayPillsSection
                
                // Content
                ScrollView {
                    VStack(spacing: 24) {
                        // Intent Selection
                        intentSelectionSection
                        
                        // Custom Muscles (if selected)
                        if viewModel.currentDayIntent == .customMuscles {
                            MuscleMultiSelectView(
                                selected: viewModel.currentDayCustomMuscles,
                                onToggle: viewModel.toggleCustomMuscle
                            )
                        }
                        
                        // Bottom padding
                        Color.clear.frame(height: 100)
                    }
                    .padding()
                }
                
                // Footer
                footerSection
            }
        }
        .navigationTitle("Build Your Custom Split")
        .navigationBarTitleDisplayMode(.large)
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Text("Customize each training day")
                .font(.subheadline)
                .foregroundColor(.planTextSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }
    
    // MARK: - Day Pills Section
    
    private var dayPillsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(0..<viewModel.days, id: \.self) { index in
                    DayPill(
                        dayNumber: index + 1,
                        isSelected: viewModel.selectedDayIndex == index,
                        onTap: { viewModel.selectDay(index) }
                    )
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 16)
    }
    
    // MARK: - Intent Selection Section
    
    private var intentSelectionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            PlanSectionHeader(
                title: "Day \(viewModel.selectedDayIndex + 1) Focus",
                subtitle: "What type of workout is this?"
            )
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                ForEach(DayIntent.allCases, id: \.self) { intent in
                    IntentCard(
                        intent: intent,
                        isSelected: viewModel.currentDayIntent == intent,
                        onTap: { viewModel.currentDayIntent = intent }
                    )
                }
            }
        }
        .planCardStyle()
    }
    
    // MARK: - Footer Section
    
    private var footerSection: some View {
        VStack {
            HStack(spacing: 16) {
                // Back button
                Button("Back") {
                    dismiss()
                }
                .buttonStyle(PlanButtonStyle(isPrimary: false))
                
                // Save button
                Button("Save Split") {
                    viewModel.save()
                }
                .buttonStyle(PlanButtonStyle(isPrimary: true))
                .disabled(!viewModel.canSave)
                .opacity(viewModel.canSave ? 1.0 : 0.6)
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .background(
            Color.planBackground
                .shadow(color: .primaryPurple.opacity(0.1), radius: 10, x: 0, y: -5)
        )
    }
}

// MARK: - Day Pill Component

struct DayPill: View {
    let dayNumber: Int
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            Text("Day \(dayNumber)")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(isSelected ? .textPrimary : .planTextPrimary)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(isSelected ? Color.planAccent : Color.planCardBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(isSelected ? Color.clear : Color.planAccent.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(PlainButtonStyle())
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - Intent Card Component

struct IntentCard: View {
    let intent: DayIntent
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                Text(intent.rawValue)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.planTextPrimary)
                    .multilineTextAlignment(.leading)
                
                Text(intent.description)
                    .font(.caption)
                    .foregroundColor(.planTextSecondary)
                    .multilineTextAlignment(.leading)
                
                Spacer()
                
                if isSelected {
                    HStack {
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.planAccent)
                            .font(.title3)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.planCardBackgroundSelected : Color.planCardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.planAccent : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - Preview

#Preview {
    NavigationView {
        CustomSplitView(
            input: {
                var input = PlanBuilderInput()
                input.daysPerWeek = 4
                return input
            }(),
            onSave: { _ in }
        )
    }
    .preferredColorScheme(.dark)
}
