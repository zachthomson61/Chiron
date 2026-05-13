//
//  ExerciseLibraryView.swift
//  Chiron
//
//  TrainingLog module - Exercise library UI
//

import SwiftUI
import SwiftData

/// Reusable exercise library: scrollable list of exercise cards with search and category filters.
/// Can be used in two modes:
/// - **Browse mode** (default): cards are NavigationLinks to detail overviews. Used on the Research tab.
/// - **Selection mode**: when `onExerciseSelected` is set, tapping a card calls the callback instead of navigating.
///   Used in the Track tab sheet; the current selection is highlighted with a purple stroke (no checkmark).
struct ExerciseLibraryView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Exercise.name, order: .forward) private var exercises: [Exercise]

    /// When non-nil, selection mode: tap calls this instead of pushing a detail view. Parent typically dismisses sheet.
    var onExerciseSelected: ((Exercise) -> Void)?
    /// In selection mode, the exercise to show as selected (highlighted card only).
    var selectedForSelectionMode: Exercise?

    /// When provided, the parent owns search/category state so it persists when the sheet is dismissed and reopened.
    var searchBinding: Binding<String>?
    var selectedCategoriesBinding: Binding<Set<String>>?
    var selectedDifficultiesBinding: Binding<Set<Difficulty>>?

    @State private var _internalSearch: String = ""
    @State private var _internalCategories: Set<String> = []
    @State private var _internalDifficulties: Set<Difficulty> = []
    @State private var newName: String = ""
    @State private var error: String?

    private var search: Binding<String> {
        searchBinding ?? $_internalSearch
    }
    private var selectedCategories: Binding<Set<String>> {
        selectedCategoriesBinding ?? $_internalCategories
    }
    private var selectedDifficulties: Binding<Set<Difficulty>> {
        selectedDifficultiesBinding ?? $_internalDifficulties
    }

    // MARK: - View Models
    
    @StateObject private var bodyweightSquatViewModel = WorkoutViewModel()
    @StateObject private var barbellBackSquatViewModel = WorkoutViewModel()
    @StateObject private var deadliftViewModel = WorkoutViewModel()
    @StateObject private var barbellBenchPressViewModel = WorkoutViewModel()
    @StateObject private var romanianDeadliftViewModel = WorkoutViewModel()
    @StateObject private var barbellRowViewModel = WorkoutViewModel()
    
    // MARK: - Exercise Name Constants
    
    private let bodyweightSquatName = "Bodyweight Squat"
    private let barbellBackSquatName = "Barbell Back Squat"
    private let backSquatName = "Back Squat" // Legacy name variant
    private let deadliftName = "Deadlift"
    private let barbellBenchPressName = "Barbell Bench Press"
    private let romanianDeadliftName = "Romanian Deadlift (RDL)"
    private let barbellRowName = "Barbell Row"

    private var isAddDisabled: Bool {
        newName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .count < 2
    }
    
    private let categories = ["Compound", "Push", "Pull", "Bodyweight", "Barbell"]
    private let difficulties: [Difficulty] = [.beginner, .intermediate, .expert]

    private var normalizedQuery: String {
        search.wrappedValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private var isSelectionMode: Bool { onExerciseSelected != nil }
    
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
    
    /// Finds the barbell bench press exercise in the database.
    /// Returns the exercise if it exists, nil otherwise.
    private var barbellBenchPressExercise: Exercise? {
        exercises.first(where: isBarbellBenchPress(_:))
    }
    
    /// Finds the Romanian Deadlift exercise in the database.
    /// Used to display the Romanian Deadlift card separately from the general exercise list.
    private var romanianDeadliftExercise: Exercise? {
        exercises.first(where: isRomanianDeadlift(_:))
    }
    
    /// Finds the barbell row exercise in the database.
    /// Used to display the barbell row card separately from the general exercise list.
    private var barbellRowExercise: Exercise? {
        exercises.first(where: isBarbellRow(_:))
    }
    
    var filtered: [Exercise] {
        let query = normalizedQuery
        let visible = exercises.filter { !isBarbellBenchPress($0) }
        let base = query.isEmpty ? visible : visible.filter { $0.name.lowercased().contains(query) }
        return base.filter {
            matchesSelectedCategory($0) && matchesSelectedDifficulty($0)
        }
    }

    /// Returns true only if the exercise matches EVERY currently-selected category (or no category is selected).
    /// Multiple selected categories narrow the result set (intersection), so "Push" + "Barbell" shows only barbell push movements.
    private func matchesSelectedCategory(_ exercise: Exercise) -> Bool {
        let selected = selectedCategories.wrappedValue
        guard !selected.isEmpty else { return true }
        return selected.allSatisfy { matchesCategory(exercise, category: $0) }
    }

    /// Rule for a single category chip.
    /// - Compound: targets two or more primary muscle groups (multi-joint movement).
    /// - Push: primary targets include chest, front delts, shoulders, or triceps.
    /// - Pull: primary targets include back, lats, traps, rear delts, biceps, or posterior chain (hamstrings, lower back).
    /// - Bodyweight: exercise name contains "bodyweight" (no external load).
    /// - Barbell: exercise name contains "barbell".
    private func matchesCategory(_ exercise: Exercise, category: String) -> Bool {
        let primary = Set(exercise.primaryTargets)
        let lowerName = exercise.name.lowercased()
        switch category {
        case "Compound":
            return exercise.primaryTargets.count >= 2
        case "Push":
            return !primary.isDisjoint(with: Self.pushMuscles)
        case "Pull":
            return !primary.isDisjoint(with: Self.pullMuscles)
        case "Bodyweight":
            return lowerName.contains("bodyweight")
        case "Barbell":
            return lowerName.contains("barbell")
        default:
            return true
        }
    }

    private static let pushMuscles: Set<MuscleGroup> = [.chest, .frontDelts, .shoulders, .triceps]
    private static let pullMuscles: Set<MuscleGroup> = [.back, .lats, .traps, .rearDelts, .biceps, .hamstrings, .lowerBack]

    /// Difficulty chips act as an OR within the row (an exercise has one difficulty),
    /// but combine with the category row as AND so "Push" + "Beginner" only shows beginner push movements.
    private func matchesSelectedDifficulty(_ exercise: Exercise) -> Bool {
        let selected = selectedDifficulties.wrappedValue
        guard !selected.isEmpty else { return true }
        return selected.contains(exercise.difficulty)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header section — adapts text based on selection vs browse mode
                VStack(alignment: .leading, spacing: 8) {
                    Text(isSelectionMode ? "Select Exercise" : "Exercise Library")
                        .font(.largeTitle.bold())
                        .foregroundStyle(Color.textPrimary)
                    
                    Text(isSelectionMode
                         ? "Receive expert coaching on every movement"
                         : "Browse and learn every movement")
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
                    
                    TextField("Search exercises", text: search)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundStyle(Color.textPrimary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.surface)
                .cornerRadius(12)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
                
                // Category filters
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(categories, id: \.self) { category in
                            let isSelected = selectedCategories.wrappedValue.contains(category)
                            Button(action: {
                                if isSelected {
                                    selectedCategories.wrappedValue.remove(category)
                                } else {
                                    selectedCategories.wrappedValue.insert(category)
                                }
                            }) {
                                Text(category)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(isSelected ? Color.textPrimary : Color.textSecondary)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)
                                    .background(isSelected ? Color.primaryPurple.opacity(0.3) : Color.surface)
                                    .cornerRadius(20)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 12)

                // Difficulty filters
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(difficulties, id: \.self) { difficulty in
                            let isSelected = selectedDifficulties.wrappedValue.contains(difficulty)
                            Button(action: {
                                if isSelected {
                                    selectedDifficulties.wrappedValue.remove(difficulty)
                                } else {
                                    selectedDifficulties.wrappedValue.insert(difficulty)
                                }
                            }) {
                                Text(difficulty.rawValue)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(isSelected ? Color.textPrimary : Color.textSecondary)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)
                                    .background(isSelected ? Color.primaryPurple.opacity(0.3) : Color.surface)
                                    .cornerRadius(20)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 24)

                // Exercise cards — all go through exerciseRow for consistent routing
                LazyVStack(spacing: 12) {
                    ForEach(filtered) { ex in
                        exerciseRow(for: ex)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .dottedTabBackground(corners: [.bottomTrailing])
        .preferredColorScheme(.dark)
        .task {
            try? ExerciseSeeder.seedIfNeeded(context: ctx)
            ensureBodyweightSquatCard()
            ensureBarbellBackSquatCard()
            ensureDeadliftCard()
            ensureRomanianDeadliftCard()
            ensureBarbellRowCard()
        }
    }
    
    /// One exercise card: name, targets, difficulty pill, and thumbnail. Optionally shows a purple stroke when selected (selection mode).
    @ViewBuilder
    private func exerciseCard(for exercise: Exercise, isSelected: Bool = false) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(displayName(for: exercise))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(exercise.targetsLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                
                Pill(text: exercise.difficulty.rawValue, difficulty: exercise.difficulty)
            }
            
            Spacer(minLength: 12)

            ExerciseThumbnail(imageName: exercise.imageName)
        }
        .padding(20)
        .background(Color.surface)
        .cornerRadius(16)
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.accentGradient, lineWidth: 1.5)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(exercise.accessibilitySummary)
    }

    /// One row for an exercise: in selection mode a Button (callback only); in browse mode a NavigationLink to destinationView(for:).
    @ViewBuilder
    private func exerciseRow(for exercise: Exercise) -> some View {
        if let callback = onExerciseSelected {
            Button {
                callback(exercise)
            } label: {
                exerciseCard(for: exercise, isSelected: selectedForSelectionMode?.id == exercise.id)
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                destinationView(for: exercise)
            } label: {
                exerciseCard(for: exercise)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Navigation

    /// Single router: by exercise name returns the matching overview (BodyweightSquat, Deadlift, etc.) or ExerciseDetailPlaceholderView for unknown names.
    @ViewBuilder
    private func destinationView(for exercise: Exercise) -> some View {
        if exercise.name.caseInsensitiveCompare(bodyweightSquatName) == .orderedSame {
            BodyweightSquatOverview(viewModel: bodyweightSquatViewModel)
        } else if exercise.name.caseInsensitiveCompare(barbellBackSquatName) == .orderedSame || 
                  exercise.name.caseInsensitiveCompare(backSquatName) == .orderedSame {
            BarbellBackSquatOverview(viewModel: barbellBackSquatViewModel)
        } else if exercise.name.caseInsensitiveCompare(deadliftName) == .orderedSame {
            DeadliftOverview(viewModel: deadliftViewModel)
        } else if exercise.name.caseInsensitiveCompare(barbellBenchPressName) == .orderedSame {
            BarbellBenchPressOverview(viewModel: barbellBenchPressViewModel)
        } else if exercise.name.caseInsensitiveCompare(romanianDeadliftName) == .orderedSame {
            RomanianDeadliftOverview(viewModel: romanianDeadliftViewModel)
        } else if exercise.name.caseInsensitiveCompare(barbellRowName) == .orderedSame {
            BarbellRowOverview(viewModel: barbellRowViewModel)
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
            let expectedImageName = "BodyweightSquat"
            let needsUpdate = currentTargets != expectedTargets || existing.imageName != expectedImageName
            
            if needsUpdate {
                existing.primaryTargets = [.quadriceps, .glutes, .adductors]
                existing.secondaryTargets = []
                existing.imageName = expectedImageName
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
            imageName: "BodyweightSquat"
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
            let expectedImageName = "BarbellBackSquat"
            let needsUpdate = currentTargets != expectedTargets
                || existing.difficulty != .intermediate
                || existing.imageName != expectedImageName
            if needsUpdate {
                existing.primaryTargets = [.quadriceps, .glutes, .adductors]
                existing.secondaryTargets = []
                existing.difficulty = .intermediate
                existing.imageName = expectedImageName
                try? ctx.save()
            }
            return
        }

        // If it doesn't exist, ExerciseSeeder will create it on first launch
    }
    
    /// Ensures deadlift exercise exists with correct primary targets and difficulty.
    /// Updates existing exercises to match current schema (primary targets: glutes, hamstrings, lowerBack, expert difficulty).
    private func ensureDeadliftCard() {
        if let existing = deadliftExercise {
            let expectedTargets: Set<MuscleGroup> = [.glutes, .hamstrings, .lowerBack]
            let currentTargets = Set(existing.primaryTargets)
            let expectedImageName = "Deadlift"
            let needsUpdate = currentTargets != expectedTargets || existing.difficulty != .expert || existing.imageName != expectedImageName
            
            if needsUpdate {
                existing.primaryTargets = [.glutes, .hamstrings, .lowerBack]
                existing.secondaryTargets = []
                existing.difficulty = .expert
                existing.imageName = expectedImageName
                try? ctx.save()
            }
            return
        }
        
        // Create if it doesn't exist
        let deadlift = Exercise(
            name: deadliftName,
            primaryTargets: [.glutes, .hamstrings, .lowerBack],
            secondaryTargets: [],
            difficulty: .expert,
            imageName: "Deadlift"
        )
        ctx.insert(deadlift)
        try? ctx.save()
    }
    
    /// Ensures barbell bench press exercise exists with correct configuration.
    /// 
    /// - Updates existing exercises to match current schema:
    ///   - Primary targets: chest, frontDelts, triceps
    ///   - Secondary targets: none
    ///   - Difficulty: intermediate
    /// - Creates the exercise if it doesn't exist.
    private func ensureBarbellBenchPressCard() {
        if let existing = barbellBenchPressExercise {
            let expectedPrimaryTargets: Set<MuscleGroup> = [.chest, .frontDelts, .triceps]
            let expectedSecondaryTargets: Set<MuscleGroup> = []
            let currentPrimaryTargets = Set(existing.primaryTargets)
            let currentSecondaryTargets = Set(existing.secondaryTargets)
            let expectedImageName = "BarbellBenchPress"
            let needsUpdate = currentPrimaryTargets != expectedPrimaryTargets || 
               currentSecondaryTargets != expectedSecondaryTargets || 
               existing.difficulty != .intermediate ||
               existing.imageName != expectedImageName
            
            if needsUpdate {
                existing.primaryTargets = [.chest, .frontDelts, .triceps]
                existing.secondaryTargets = []
                existing.difficulty = .intermediate
                existing.imageName = expectedImageName
                try? ctx.save()
            }
            return
        }
        
        // Create if it doesn't exist
        let benchPress = Exercise(
            name: barbellBenchPressName,
            primaryTargets: [.chest, .frontDelts, .triceps],
            secondaryTargets: [],
            difficulty: .intermediate,
            imageName: "BarbellBenchPress"
        )
        ctx.insert(benchPress)
        try? ctx.save()
    }
    
    /// Ensures Romanian Deadlift exercise exists with correct configuration.
    /// 
    /// - Updates existing exercises to match current schema:
    ///   - Primary targets: glutes, hamstrings, lowerBack
    ///   - Secondary targets: none
    ///   - Difficulty: intermediate
    /// - Creates the exercise if it doesn't exist.
    private func ensureRomanianDeadliftCard() {
        if let existing = romanianDeadliftExercise {
            let expectedTargets: Set<MuscleGroup> = [.glutes, .hamstrings, .lowerBack]
            let currentTargets = Set(existing.primaryTargets)
            let expectedImageName = "RomanianDeadlift"
            let needsUpdate = currentTargets != expectedTargets || existing.difficulty != .intermediate || existing.imageName != expectedImageName
            
            if needsUpdate {
                existing.primaryTargets = [.glutes, .hamstrings, .lowerBack]
                existing.secondaryTargets = []
                existing.difficulty = .intermediate
                existing.imageName = expectedImageName
                try? ctx.save()
            }
            return
        }
        
        // Create if it doesn't exist
        let rdl = Exercise(
            name: romanianDeadliftName,
            primaryTargets: [.glutes, .hamstrings, .lowerBack],
            secondaryTargets: [],
            difficulty: .intermediate,
            imageName: "RomanianDeadlift"
        )
        ctx.insert(rdl)
        try? ctx.save()
    }
    
    /// Ensures barbell row exercise exists with correct configuration.
    ///
    /// Updates existing exercises to match current schema:
    /// - Primary targets: `.lats, .back` (order matters - Lats displays first)
    /// - Secondary targets: `.rearDelts, .biceps`
    /// - Difficulty: `.intermediate`
    ///
    /// Creates the exercise if it doesn't exist.
    private func ensureBarbellRowCard() {
        if let existing = barbellRowExercise {
            let expectedPrimaryTargets: [MuscleGroup] = [.lats, .back]
            let expectedSecondaryTargets: Set<MuscleGroup> = [.rearDelts, .biceps]
            let currentPrimaryTargets = existing.primaryTargets
            let currentSecondaryTargets = Set(existing.secondaryTargets)
            let expectedImageName = "BarbellRow"

            // Array comparison preserves order (ensures Lats appears before Middle Back)
            if currentPrimaryTargets != expectedPrimaryTargets ||
               currentSecondaryTargets != expectedSecondaryTargets ||
               existing.difficulty != .intermediate ||
               existing.imageName != expectedImageName {
                existing.primaryTargets = [.lats, .back]
                existing.secondaryTargets = [.rearDelts, .biceps]
                existing.difficulty = .intermediate
                existing.imageName = expectedImageName
                try? ctx.save()
            }
            return
        }

        // Create if it doesn't exist
        let row = Exercise(
            name: barbellRowName,
            primaryTargets: [.lats, .back],
            secondaryTargets: [.rearDelts, .biceps],
            difficulty: .intermediate,
            imageName: "BarbellRow"
        )
        ctx.insert(row)
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
    
    /// Checks if an exercise is a barbell bench press.
    /// Used to filter it from the general exercise list since it has a dedicated card.
    private func isBarbellBenchPress(_ exercise: Exercise) -> Bool {
        exercise.name.caseInsensitiveCompare(barbellBenchPressName) == .orderedSame
    }
    
    /// Checks if an exercise is a Romanian Deadlift.
    /// Used to filter it from the general exercise list since it has a dedicated card.
    private func isRomanianDeadlift(_ exercise: Exercise) -> Bool {
        exercise.name.caseInsensitiveCompare(romanianDeadliftName) == .orderedSame
    }
    
    /// Checks if an exercise is a barbell row.
    /// Used to filter it from the general exercise list since it has a dedicated card.
    private func isBarbellRow(_ exercise: Exercise) -> Bool {
        exercise.name.caseInsensitiveCompare(barbellRowName) == .orderedSame
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
                // Check if it's a system icon (contains a dot, typical of SF Symbols)
                if imageName.contains(".") && !imageName.hasSuffix(".jpg") && !imageName.hasSuffix(".png") {
                    Image(systemName: imageName)
                        .font(.system(size: 48))
                        .foregroundStyle(Color.white.opacity(0.8))
                } else {
                    // Regular image file - use robust loading approach
                    loadedImage(for: imageName)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipped()
                }
            } else {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
        }
        .frame(width: 100, height: 100)
        .background(Color.white.opacity(0.12))
        .cornerRadius(12)
        .clipped()
    }
    
    /// Robust image loading that searches asset catalogs and bundle resources
    private func loadedImage(for name: String) -> Image {
        #if os(iOS)
        // Remove extension if present for asset catalog lookup
        let baseName = name.replacingOccurrences(of: ".jpg", with: "").replacingOccurrences(of: ".png", with: "")
        
        // Try standard UIImage(named:) which searches asset catalogs and bundle images
        if let ui = UIImage(named: baseName) {
            return Image(uiImage: ui).renderingMode(.original)
        }
        // Try with original name (in case it's in bundle with extension)
        if let ui = UIImage(named: name) {
            return Image(uiImage: ui).renderingMode(.original)
        }
        // Try explicit .jpg in main bundle
        if let url = Bundle.main.url(forResource: baseName, withExtension: "jpg"),
           let ui = UIImage(contentsOfFile: url.path) {
            return Image(uiImage: ui).renderingMode(.original)
        }
        // Try explicit .png in main bundle
        if let url = Bundle.main.url(forResource: baseName, withExtension: "png"),
           let ui = UIImage(contentsOfFile: url.path) {
            return Image(uiImage: ui).renderingMode(.original)
        }
        // Try with JPG extension in name
        if name.hasSuffix(".jpg"), let url = Bundle.main.url(forResource: baseName, withExtension: "jpg"),
           let ui = UIImage(contentsOfFile: url.path) {
            return Image(uiImage: ui).renderingMode(.original)
        }
        // Fallback placeholder - use a visible system icon
        return Image(systemName: "figure.strengthtraining.traditional")
        #else
        let baseName = name.replacingOccurrences(of: ".jpg", with: "").replacingOccurrences(of: ".png", with: "")
        return Image(baseName)
        #endif
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
    /// - Beginner: Green badge
    /// - Advanced: Purple badge
    /// - Intermediate: Yellow badge
    /// - Expert: Red badge
    private func colorForDifficulty(_ difficulty: Difficulty) -> (Color, Color) {
        switch difficulty {
        case .beginner:
            return (Color.beginnerGreen.opacity(0.24), Color.beginnerGreen)
        case .advanced:
            return (Color.brandAccentPurple.opacity(0.24), Color.brandAccentPurple)
        case .intermediate:
            return (Color.intermediateYellow.opacity(0.24), Color.intermediateYellow)
        case .expert:
            return (Color.expertRed.opacity(0.24), Color.expertRed)
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
        name: "Barbell Bench Press",
        primaryTargets: [.chest, .frontDelts, .triceps],
        secondaryTargets: [],
        difficulty: .intermediate,
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


