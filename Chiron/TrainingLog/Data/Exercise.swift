//
//  Exercise.swift
//  Chiron
//
//  TrainingLog module - Exercise model
//

import SwiftData
import Foundation

@Model
final class Exercise {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var name: String
    var bodyRegion: String?   // optional for future filters
    var targetMuscles: String?
    var difficulty: String?   // Beginner, Intermediate, Advanced
    var imageName: String?    // Name of image asset or system icon
    var createdAt: Date

    init(
        name: String, 
        bodyRegion: String? = nil, 
        targetMuscles: String? = nil,
        difficulty: String? = nil,
        imageName: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = UUID()
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.bodyRegion = bodyRegion
        self.targetMuscles = targetMuscles
        self.difficulty = difficulty
        self.imageName = imageName
        self.createdAt = createdAt
    }
}

