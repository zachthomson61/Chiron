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

    private var isAddDisabled: Bool {
        newName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .count < 2
    }
    
    private let categories = ["Compound", "Push", "Pull", "Bodyweight"]

    var filtered: [Exercise] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return q.isEmpty ? exercises : exercises.filter { $0.name.lowercased().contains(q) }
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
                        ForEach(filtered) { ex in
                            NavigationLink {
                                ExerciseDetailPlaceholderView(exercise: ex)
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
            }
        }
        .preferredColorScheme(.dark)
    }
    
    @ViewBuilder
    private func exerciseCard(for exercise: Exercise) -> some View {
        HStack(spacing: 16) {
            // Left side: Text information
            VStack(alignment: .leading, spacing: 8) {
                Text(exercise.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.leading)
                
                if let targetMuscles = exercise.targetMuscles {
                    Text(targetMuscles)
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                }
                
                if let difficulty = exercise.difficulty {
                    Text(difficulty)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(difficultyColor(for: difficulty).opacity(0.3))
                        .cornerRadius(16)
                }
            }
            
            Spacer()
            
            // Right side: Exercise image
            ZStack {
                if let imageName = exercise.imageName {
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
        .padding(20)
        .background(Color.white.opacity(0.06))
        .cornerRadius(16)
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
    
    private func difficultyColor(for difficulty: String) -> Color {
        switch difficulty.lowercased() {
        case "beginner":
            return Color.green
        case "intermediate":
            return Color.primaryPurple
        case "advanced":
            return Color.orange
        default:
            return Color.textSecondary
        }
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
    }
}

#Preview {
    ExerciseLibraryView()
        .modelContainer(for: Exercise.self, inMemory: true)
}

