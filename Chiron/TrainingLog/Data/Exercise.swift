//
//  Exercise.swift
//  Chiron
//
//  TrainingLog module - Exercise model
//

import SwiftData
import Foundation

/// User-friendly difficulty levels surfaced in the exercise library.
enum Difficulty: String, CaseIterable, Codable {
    case beginner = "Beginner"
    case intermediate = "Intermediate"
    case advanced = "Advanced"
}

/// SwiftData-backed exercise record. The legacy `targetMuscles` string remains for old UI,
/// while the new primary/secondary arrays drive the richer presentation.
@Model
final class Exercise {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var name: String
    var bodyRegion: String?   // optional for future filters
    var targetMuscles: String? // legacy summary for backwards compatibility
    var imageName: String?    // Name of image asset or system icon
    var createdAt: Date
    
    // SwiftData cannot persist arrays of enums just yet, so we stash the raw enum values
    // in a lightweight pipe-delimited string. The helpers below keep the computed APIs clean.
    private var primaryTargetsStorage: String = ""
    private var secondaryTargetsStorage: String = ""
    @Attribute var difficultyRawValue: String = Difficulty.beginner.rawValue
    
    /// Muscle groups that should always be surfaced for the movement (e.g., quads for a back squat).
    var primaryTargets: [MuscleGroup] {
        get { Exercise.decodeTargets(from: primaryTargetsStorage) }
        set {
            primaryTargetsStorage = Exercise.encodeTargets(newValue)
            targetMuscles = Exercise.formattedTargets(primary: newValue, secondary: secondaryTargets)
        }
    }
    
    /// Supporting muscle groups that appear in the short caption.
    var secondaryTargets: [MuscleGroup] {
        get { Exercise.decodeTargets(from: secondaryTargetsStorage) }
        set {
            secondaryTargetsStorage = Exercise.encodeTargets(newValue)
            targetMuscles = Exercise.formattedTargets(primary: primaryTargets, secondary: newValue)
        }
    }
    
    /// Human readable badge content for the new difficulty pill.
    var difficulty: Difficulty {
        get { Difficulty(rawValue: difficultyRawValue) ?? .beginner }
        set { difficultyRawValue = newValue.rawValue }
    }
    
    init(
        id: UUID = UUID(),
        name: String,
        bodyRegion: String? = nil,
        primaryTargets: [MuscleGroup] = [],
        secondaryTargets: [MuscleGroup] = [],
        difficulty: Difficulty = .beginner,
        imageName: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.bodyRegion = bodyRegion
        self.imageName = imageName
        self.createdAt = createdAt
        self.primaryTargetsStorage = Exercise.encodeTargets(primaryTargets)
        self.secondaryTargetsStorage = Exercise.encodeTargets(secondaryTargets)
        self.difficultyRawValue = difficulty.rawValue
        self.targetMuscles = Exercise.formattedTargets(primary: primaryTargets, secondary: secondaryTargets)
    }
    
    // MARK: - Derived values
    
    var targetsLine: String {
        let primary = primaryTargets.map(\.displayName).joined(separator: ", ")
        let secondary = secondaryTargets.map(\.displayName).joined(separator: ", ")
        
        if primary.isEmpty && secondary.isEmpty {
            return targetMuscles ?? "Targets coming soon"
        }
        
        if secondary.isEmpty {
            return primary
        }
        
        return "\(primary) • \(secondary)"
    }
    
    /// Spoken summary that keeps VoiceOver aligned with the new visual hierarchy.
    var accessibilitySummary: String {
        "\(name). Targets: \(targetsLine). Difficulty: \(difficulty.rawValue)"
    }
    
    private static func formattedTargets(primary: [MuscleGroup], secondary: [MuscleGroup]) -> String? {
        let primaryString = primary.map(\.displayName).joined(separator: ", ")
        guard !primaryString.isEmpty else { return nil }
        let secondaryString = secondary.map(\.displayName).joined(separator: ", ")
        guard !secondaryString.isEmpty else { return primaryString }
        return "\(primaryString) • \(secondaryString)"
    }
    
    /// Serialises raw enum values into a compact stored representation.
    private static func encodeTargets(_ targets: [MuscleGroup]) -> String {
        targets.map(\.rawValue).joined(separator: "|")
    }
    
    /// Rehydrates the stored string into `[MuscleGroup]` while ignoring unknown values safely.
    private static func decodeTargets(from string: String) -> [MuscleGroup] {
        guard !string.isEmpty else { return [] }
        return string
            .split(separator: "|")
            .compactMap { MuscleGroup(rawValue: String($0)) }
    }
}

