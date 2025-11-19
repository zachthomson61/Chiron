//
//  ExerciseLibraryView.swift
//  Chiron
//
//  TrainingLog module - Exercise library UI
//

import SwiftUI
import SwiftData

struct ExerciseLibraryView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Exercise.name, order: .forward) private var exercises: [Exercise]

    @State private var search: String = ""
    @State private var newName: String = ""
    @State private var error: String?
    @State private var selectedCategory: String? = nil
    // MARK: - View Models
    
    @StateObject private var bodyweightSquatViewModel = WorkoutViewModel()
    @StateObject private var barbellBackSquatViewModel = WorkoutViewModel()
    @StateObject private var deadliftViewModel = WorkoutViewModel()
    
    // MARK: - Exercise Name Constants
    
    private let bodyweightSquatName = "Bodyweight Squat"
    private let barbellBackSquatName = "Barbell Back Squat"
    private let backSquatName = "Back Squat" // Legacy name variant
    private let deadliftName = "Deadlift"

    private var isAddDisabled: Bool {
        newName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .count < 2
    }
    
    private let categories = ["Compound", "Push", "Pull", "Bodyweight"]

    private var normalizedQuery: String {
        search
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
    
    // MARK: - Exercise Queries
    
    /// Finds the bodyweight squat exercise in the database
    private var bodyweightSquatExercise: Exercise? {
        exercises.first(where: isBodyweightSquat(_:))
    }
    
    /// Finds the barbell back squat exercise in the database (handles both "Barbell Back Squat" and legacy "Back Squat" names)
    private var barbellBackSquatExercise: Exercise? {
        exercises.first { exercise in
            exercise.name.caseInsensitiveCompare(barbellBackSquatName) == .orderedSame ||
            exercise.name.caseInsensitiveCompare(backSquatName) == .orderedSame
        }
    }
    
    /// Finds the deadlift exercise in the database.
    /// Used to display the deadlift card separately from the general exercise list.
    private var deadliftExercise: Exercise? {
        exercises.first(where: isDeadlift(_:))
    }
    
    private var shouldShowBodyweightSquatCard: Bool {
        guard bodyweightSquatExercise != nil else { return false }
        let query = normalizedQuery
        return query.isEmpty || bodyweightSquatName.lowercased().contains(query)
    }
    
    /// Determines if the deadlift card should be displayed.
    /// Shows the card if the exercise exists and matches the search query (if any).
    private var shouldShowDeadliftCard: Bool {
        guard deadliftExercise != nil else { return false }
        let query = normalizedQuery
        return query.isEmpty || deadliftName.lowercased().contains(query)
    }
    
    var filtered: [Exercise] {
        let query = normalizedQuery
        let base = query.isEmpty ? exercises : exercises.filter { $0.name.lowercased().contains(query) }
        return base.filter { !isBodyweightSquat($0) && !isDeadlift($0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Header section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Exercise Library")
                            .font(.largeTitle.bold())
                            .foregroundStyle(Color.textPrimary)
                        
                        Text("Browse and learn every movement")
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 16)
                    
                    // Search bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(Color.textSecondary)
                        
                        TextField("Search exercises", text: $search)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .foregroundStyle(Color.textPrimary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                    
                    // Category filters
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(categories, id: \.self) { category in
                                Button(action: {
                                    if selectedCategory == category {
                                        selectedCategory = nil
                                    } else {
                                        selectedCategory = category
                                    }
                                }) {
                                    Text(category)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(selectedCategory == category ? Color.textPrimary : Color.textSecondary)
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 10)
                                        .background(selectedCategory == category ? Color.primaryPurple.opacity(0.3) : Color.white.opacity(0.06))
                                        .cornerRadius(20)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.bottom, 24)
                    
                    // Exercise cards
                    LazyVStack(spacing: 12) {
                        if shouldShowBodyweightSquatCard, let squat = bodyweightSquatExercise {
                            NavigationLink {
                                BodyweightSquatOverview(viewModel: bodyweightSquatViewModel)
                            } label: {
                                exerciseCard(for: squat)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        if shouldShowDeadliftCard, let deadlift = deadliftExercise {
                            NavigationLink {
                                DeadliftOverview(viewModel: deadliftViewModel)
                            } label: {
                                exerciseCard(for: deadlift)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        ForEach(filtered) { ex in
                            NavigationLink {
                                destinationView(for: ex)
                            } label: {
                                exerciseCard(for: ex)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .background(Color.background)
            .task {
                // Seed exercises if needed (fast - only runs once on first launch)
                try? ExerciseSeeder.seedIfNeeded(context: ctx)
                ensureBodyweightSquatCard()
                ensureBarbellBackSquatCard()
                ensureDeadliftCard()
            }
        }
        .preferredColorScheme(.dark)
    }
    
    @ViewBuilder
    private func exerciseCard(for exercise: Exercise) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(displayName(for: exercise))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                
                Text(exercise.targetsLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                Pill(text: exercise.difficulty.rawValue, difficulty: exercise.difficulty)
            }
            
            Spacer(minLength: 12)
            
            ExerciseThumbnail(imageName: exercise.imageName)
        }
        .padding(20)
        .background(Color.white.opacity(0.06))
        .cornerRadius(16)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(exercise.accessibilitySummary)
    }
    
    // MARK: - Navigation
    
    /// Routes to the appropriate detail view based on exercise name
    @ViewBuilder
    private func destinationView(for exercise: Exercise) -> some View {
        if exercise.name.caseInsensitiveCompare(bodyweightSquatName) == .orderedSame {
            BodyweightSquatOverview(viewModel: bodyweightSquatViewModel)
        } else if exercise.name.caseInsensitiveCompare(barbellBackSquatName) == .orderedSame || 
                  exercise.name.caseInsensitiveCompare(backSquatName) == .orderedSame {
            BarbellBackSquatOverview(viewModel: barbellBackSquatViewModel)
        } else if exercise.name.caseInsensitiveCompare(deadliftName) == .orderedSame {
            DeadliftOverview(viewModel: deadliftViewModel)
        } else {
            ExerciseDetailPlaceholderView(exercise: exercise)
        }
    }
    
    // MARK: - Exercise Data Migration
    
    /// Ensures bodyweight squat exercise exists with correct primary targets.
    /// Updates existing exercises to match current schema (primary targets only, includes adductors).
    private func ensureBodyweightSquatCard() {
        if let existing = bodyweightSquatExercise {
            let expectedTargets: Set<MuscleGroup> = [.quadriceps, .glutes, .adductors]
            let currentTargets = Set(existing.primaryTargets)
            if currentTargets != expectedTargets {
                existing.primaryTargets = [.quadriceps, .glutes, .adductors]
                existing.secondaryTargets = []
                try? ctx.save()
            }
            return
        }
        
        // Create if it doesn't exist
        let squat = Exercise(
            name: bodyweightSquatName,
            primaryTargets: [.quadriceps, .glutes, .adductors],
            secondaryTargets: [],
            difficulty: .beginner,
            imageName: "figure.strengthtraining.traditional"
        )
        ctx.insert(squat)
        try? ctx.save()
    }
    
    /// Ensures barbell back squat exercise exists with correct primary targets and difficulty.
    /// Updates existing exercises to match current schema (primary targets only, includes adductors, intermediate difficulty).
    private func ensureBarbellBackSquatCard() {
        if let existing = barbellBackSquatExercise {
            let expectedTargets: Set<MuscleGroup> = [.quadriceps, .glutes, .adductors]
            let currentTargets = Set(existing.primaryTargets)
            if currentTargets != expectedTargets || existing.difficulty != .intermediate {
                existing.primaryTargets = [.quadriceps, .glutes, .adductors]
                existing.secondaryTargets = []
                existing.difficulty = .intermediate
                try? ctx.save()
            }
            return
        }
        
        // If it doesn't exist, ExerciseSeeder will create it on first launch
    }
    
    /// Ensures deadlift exercise exists with correct primary targets and difficulty.
    /// Updates existing exercises to match current schema (primary targets: hamstrings, glutes, back, erectors, expert difficulty).
    private func ensureDeadliftCard() {
        if let existing = deadliftExercise {
            let expectedTargets: Set<MuscleGroup> = [.hamstrings, .glutes, .back, .erectors]
            let currentTargets = Set(existing.primaryTargets)
            if currentTargets != expectedTargets || existing.difficulty != .expert {
                existing.primaryTargets = [.hamstrings, .glutes, .back, .erectors]
                existing.secondaryTargets = []
                existing.difficulty = .expert
                try? ctx.save()
            }
            return
        }
        
        // Create if it doesn't exist
        let deadlift = Exercise(
            name: deadliftName,
            primaryTargets: [.hamstrings, .glutes, .back, .erectors],
            secondaryTargets: [],
            difficulty: .expert,
            imageName: "figure.strengthtraining.traditional"
        )
        ctx.insert(deadlift)
        try? ctx.save()
    }

    private func addExercise() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.count >= 2 && name.count <= 40 else {
            error = "Name must be 2 to 40 characters."
            return
        }
        let exists = exercises.contains { $0.name.compare(name, options: .caseInsensitive) == .orderedSame }
        guard !exists else {
            error = "That name already exists."
            return
        }
        ctx.insert(Exercise(name: name))
        try? ctx.save()
        newName = ""
        error = nil
    }

    private func promptRename(_ ex: Exercise) {
        // Simple inline approach: put current name into the add field
        newName = ex.name
        error = "Type a new name above and tap Add. The old entry will be removed."
        // On Add, if the old name matches, replace it:
        // For simplicity, we do not auto-bind. Keep v1 minimal.
    }

    private func delete(_ ex: Exercise) {
        ctx.delete(ex)
        try? ctx.save()
    }

    private func deleteOffsets(_ offsets: IndexSet) {
        for i in offsets { ctx.delete(filtered[i]) }
        try? ctx.save()
    }
    
    // MARK: - Helpers
    
    /// Checks if an exercise is a bodyweight squat
    private func isBodyweightSquat(_ exercise: Exercise) -> Bool {
        exercise.name.caseInsensitiveCompare(bodyweightSquatName) == .orderedSame
    }
    
    /// Checks if an exercise is a deadlift.
    /// Used to filter deadlift from the general exercise list since it has a dedicated card.
    private func isDeadlift(_ exercise: Exercise) -> Bool {
        exercise.name.caseInsensitiveCompare(deadliftName) == .orderedSame
    }
    
    /// Normalizes exercise names for display.
    /// Converts legacy "Back Squat" to "Barbell Back Squat" for consistency.
    private func displayName(for exercise: Exercise) -> String {
        if exercise.name.caseInsensitiveCompare(backSquatName) == .orderedSame {
            return barbellBackSquatName
        }
        return exercise.name
    }
}

struct ExerciseDetailPlaceholderView: View {
    let exercise: Exercise
    var body: some View {
        VStack(spacing: 12) {
            Text(exercise.name).font(.title2).bold()
            Text("Logging and charts coming next.")
                .foregroundStyle(.secondary)
        }
        .padding()
        .navigationTitle(exercise.name)
        .toolbar(.hidden, for: .tabBar)
    }
}

private struct ExerciseThumbnail: View {
    let imageName: String?
    
    /// Keeps the right-hand artwork consistent while the left stack compresses.
    var body: some View {
        ZStack {
            if let imageName {
                Image(systemName: imageName)
                    .font(.system(size: 48))
                    .foregroundStyle(Color.white.opacity(0.8))
            } else {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
        }
        .frame(width: 100, height: 100)
        .background(Color.white.opacity(0.12))
        .cornerRadius(12)
    }
}

/// Difficulty badge component for exercise cards.
/// Uses color coding: purple for beginner/advanced, yellow for intermediate, red for expert.
private struct Pill: View {
    let text: String
    let difficulty: Difficulty

    var body: some View {
        let (backgroundColor, foregroundColor) = colorForDifficulty(difficulty)
        
        Text(text)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(backgroundColor)
            .foregroundStyle(foregroundColor)
            .clipShape(Capsule())
    }
    
    /// Returns background and foreground colors based on difficulty level.
    /// - Beginner/Advanced: Purple badge
    /// - Intermediate: Yellow badge (visual distinction)
    /// - Expert: Red badge (visual distinction)
    private func colorForDifficulty(_ difficulty: Difficulty) -> (Color, Color) {
        switch difficulty {
        case .beginner, .advanced:
            return (Color.brandAccentPurple.opacity(0.18), Color.brandAccentPurple)
        case .intermediate:
            return (Color.intermediateYellow.opacity(0.18), Color.intermediateYellow)
        case .expert:
            return (Color.expertRed.opacity(0.18), Color.expertRed)
        }
    }
}

#if DEBUG
/// Preview-friendly sample entries so the revamped layout renders in Xcode previews.
private let sampleExercises: [Exercise] = [
    Exercise(
        name: "Bodyweight Squat",
        primaryTargets: [.quadriceps, .glutes, .adductors],
        secondaryTargets: [],
        difficulty: .beginner,
        imageName: "figure.strengthtraining.traditional"
    ),
    Exercise(
        name: "Barbell Back Squat",
        primaryTargets: [.quadriceps, .glutes, .adductors],
        secondaryTargets: [],
        difficulty: .intermediate,
        imageName: "figure.strengthtraining.traditional"
    ),
    Exercise(
        name: "Barbell Row",
        primaryTargets: [.back, .lats],
        secondaryTargets: [.rearDelts, .biceps],
        difficulty: .intermediate,
        imageName: "figure.strengthtraining.traditional"
    ),
    Exercise(
        name: "Bench Press",
        primaryTargets: [.chest],
        secondaryTargets: [.triceps, .frontDelts],
        difficulty: .beginner,
        imageName: "figure.strengthtraining.traditional"
    )
]
#endif

#Preview {
#if DEBUG
    do {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Exercise.self, configurations: configuration)
        sampleExercises.forEach { container.mainContext.insert($0) }
        return ExerciseLibraryView()
            .modelContainer(container)
    } catch {
        return ExerciseLibraryView()
            .modelContainer(for: Exercise.self, inMemory: true)
    }
#else
    ExerciseLibraryView()
        .modelContainer(for: Exercise.self, inMemory: true)
#endif
}


