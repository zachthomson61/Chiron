import SwiftUI

struct PlanPreviewView: View {
    let plan: TrainingPlan
    @Environment(\.dismiss) private var dismiss
    @State private var selectedWeek: Int = 1
    @State private var expandedDays: Set<UUID> = []
    @State private var showShareSheet = false
    @State private var exportURL: URL?
    
    var body: some View {
        ZStack {
            // Background
            Color.planBackground
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    // Plan Header
                    planHeader
                    
                    // Plan Stats
                    planStats
                    
                    // Week Selector
                    weekSelector
                    
                    // Week Content
                    if let week = plan.weeks.first(where: { $0.weekNumber == selectedWeek }) {
                        weekContent(week)
                    }
                    
                    // Export Section
                    exportSection
                }
                .padding()
            }
        }
        .navigationTitle(plan.name)
        .navigationBarTitleDisplayMode(.large)
        .preferredColorScheme(.dark)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: backToPlans) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text("Plans")
                    }
                    .foregroundColor(.planTextPrimary)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: shareplan) {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundColor(.planAccent)
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = exportURL {
                ShareSheet(activityItems: [url])
            }
        }
    }
    
    private func backToPlans() {
        // First dismiss PlanPreviewView
        dismiss()
        // Then dismiss the PlanBuilder screen after a tick to reveal Plans home
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            dismiss()
        }
    }
    
    // MARK: - Section Views
    
    private var planHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Created", systemImage: "calendar")
                    .font(.caption)
                    .foregroundColor(.planTextSecondary)
                Spacer()
                Text(plan.createdAt, style: .date)
                    .font(.caption)
                    .foregroundColor(.planTextSecondary)
            }
            
            // Target Muscles
            if !plan.targetMuscles.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(plan.targetMuscles, id: \.self) { muscle in
                            HStack(spacing: 4) {
                                Image(systemName: muscle.icon)
                                    .font(.caption)
                                Text(muscle.rawValue)
                                    .font(.caption)
                            }
                            .foregroundColor(.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.planAccent)
                            .cornerRadius(12)
                        }
                    }
                }
            }
        }
        .planCardStyle()
    }
    
    private var planStats: some View {
        HStack(spacing: 16) {
            StatBox(
                title: "Duration",
                value: "\(plan.duration)",
                unit: "weeks"
            )
            
            StatBox(
                title: "Frequency",
                value: "\(plan.daysPerWeek)",
                unit: "days/week"
            )
            
            StatBox(
                title: "Split",
                value: plan.split.rawValue,
                unit: nil
            )
        }
    }
    
    private var weekSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(plan.weeks, id: \.weekNumber) { week in
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedWeek = week.weekNumber
                        }
                    }) {
                        VStack(spacing: 4) {
                            Text("Week")
                                .font(.caption)
                            Text("\(week.weekNumber)")
                                .font(.headline)
                                .fontWeight(.bold)
                        }
                        .frame(width: 60, height: 60)
                    }
                    .foregroundColor(selectedWeek == week.weekNumber ? .textPrimary : .planTextPrimary)
                    .background(
                        selectedWeek == week.weekNumber ?
                        Color.planAccent :
                        Color.planCardBackground
                    )
                    .cornerRadius(16)
                }
            }
        }
    }
    
    private func weekContent(_ week: TrainingWeek) -> some View {
        VStack(spacing: 12) {
            ForEach(week.days) { day in
                DayCard(
                    day: day,
                    isExpanded: expandedDays.contains(day.id),
                    onToggle: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            if expandedDays.contains(day.id) {
                                expandedDays.remove(day.id)
                            } else {
                                expandedDays.insert(day.id)
                            }
                        }
                    }
                )
            }
        }
    }
    
    private var exportSection: some View {
        VStack(spacing: 16) {
            Button(action: shareplan) {
                Label("Export Plan", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(PlanButtonStyle(isPrimary: false))
            
            Button(action: {
                dismiss()
            }) {
                Text("Back to Home")
            }
            .buttonStyle(PlanButtonStyle(isPrimary: true))
        }
        .padding(.top, 20)
    }
    
    // MARK: - Actions
    
    private func shareplan() {
        Task {
            do {
                let url = try await PlanPersistence.shared.exportToFile(plan)
                await MainActor.run {
                    self.exportURL = url
                    self.showShareSheet = true
                }
            } catch {
                print("Export failed: \(error)")
            }
        }
    }
}

// MARK: - Supporting Views

struct StatBox: View {
    let title: String
    let value: String
    let unit: String?
    
    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.planTextSecondary)
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primaryPurple)
            if let unit = unit {
                Text(unit)
                    .font(.caption2)
                    .foregroundColor(.planTextSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.planCardBackground)
        .cornerRadius(12)
    }
}

struct DayCard: View {
    let day: TrainingDay
    let isExpanded: Bool
    let onToggle: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            Button(action: onToggle) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Day \(day.dayNumber): \(day.name)")
                            .font(.headline)
                            .foregroundColor(.planTextPrimary)
                        
                        HStack(spacing: 12) {
                            Label("\(day.duration) min", systemImage: "clock")
                                .font(.caption)
                                .foregroundColor(.planTextSecondary)
                            
                            Label(day.difficulty.rawValue, systemImage: "flame")
                                .font(.caption)
                                .foregroundColor(difficultyColor(day.difficulty))
                        }
                    }
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.planAccent)
                        .font(.caption)
                }
            }
            
            // Exercises (expanded)
            if isExpanded {
                Divider()
                    .background(Color.planAccent.opacity(0.3))
                
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(day.exercises) { exercise in
                        ExerciseRow(exercise: exercise)
                    }
                }
            }
        }
        .padding()
        .background(Color.planCardBackground)
        .cornerRadius(16)
    }
    
    private func difficultyColor(_ difficulty: DifficultyLevel) -> Color {
        switch difficulty {
        case .beginner: return .green
        case .intermediate: return .orange
        case .advanced: return .primaryPurple
        }
    }
}

struct ExerciseRow: View {
    let exercise: WorkoutExercise
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(exercise.name)
                        .font(.subheadline)
                        .foregroundColor(.planTextPrimary)
                    
                    if exercise.isSuperset {
                        Text(exercise.notes ?? "")
                            .font(.caption2)
                            .foregroundColor(.planAccent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.planAccent.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
                
                HStack(spacing: 8) {
                    Text("\(exercise.sets) × \(exercise.reps)")
                        .font(.caption)
                        .foregroundColor(.planTextSecondary)
                    
                    if exercise.restTime > 0 {
                        Text("• Rest: \(exercise.restTime)s")
                            .font(.caption)
                            .foregroundColor(.planTextSecondary)
                    }
                }
            }
            
            Spacer()
            
            Text(exercise.category.rawValue)
                .font(.caption2)
                .foregroundColor(.planTextSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.planCardBackground)
                .cornerRadius(6)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
