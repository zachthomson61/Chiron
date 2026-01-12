//
//  ExerciseSetLog.swift
//  Chiron
//
//  TrainingLog module - ExerciseSetLog model for Firebase Firestore
//
//  Represents a single set performed during a workout. Each set creates
//  one ExerciseSetLog document in the `exerciseSetLogs` collection.
//

import Foundation
import FirebaseFirestore

/// Represents an individual set log for an exercise, stored in Firebase Firestore.
///
/// Each set the user completes creates one ExerciseSetLog document.
/// Multiple sets for the same exercise in the same workout are tracked via `setNumber`.
struct ExerciseSetLog: Codable, Identifiable {
    /// Firestore document ID (auto-generated when created)
    var id: String
    
    /// Reference to the parent WorkoutLog document
    var workoutLogId: String
    
    /// User ID who performed this set (device-based identifier)
    var userId: String
    
    /// Name of the exercise (e.g., "Barbell Back Squat")
    var exerciseName: String
    
    /// Set number within the exercise (1, 2, 3, etc.)
    var setNumber: Int
    
    /// Weight used in pounds (nil for bodyweight exercises)
    var weight: Double?
    
    /// Number of reps completed
    var reps: Int?
    
    /// Whether the user experienced pain during this set
    var flaggedPain: Bool
    
    /// Whether the user felt not in control during this set
    var flaggedNotInControl: Bool
    
    /// When this set was logged
    var timestamp: Date
    
    init(
        id: String = UUID().uuidString,
        workoutLogId: String,
        userId: String,
        exerciseName: String,
        setNumber: Int,
        weight: Double? = nil,
        reps: Int? = nil,
        flaggedPain: Bool = false,
        flaggedNotInControl: Bool = false,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.workoutLogId = workoutLogId
        self.userId = userId
        self.exerciseName = exerciseName
        self.setNumber = setNumber
        self.weight = weight
        self.reps = reps
        self.flaggedPain = flaggedPain
        self.flaggedNotInControl = flaggedNotInControl
        self.timestamp = timestamp
    }
    
    // MARK: - Firestore Serialization
    
    /// Converts the model to a Firestore-compatible dictionary.
    /// Converts Swift Date to Firestore Timestamp for storage.
    /// Only includes weight/reps if they have values (nil fields are omitted).
    func toFirestoreData() -> [String: Any] {
        var data: [String: Any] = [
            "workoutLogId": workoutLogId,
            "userId": userId,
            "exerciseName": exerciseName,
            "setNumber": setNumber,
            "flaggedPain": flaggedPain,
            "flaggedNotInControl": flaggedNotInControl,
            "timestamp": Timestamp(date: timestamp)
        ]
        
        if let weight = weight {
            data["weight"] = weight
        }
        
        if let reps = reps {
            data["reps"] = reps
        }
        
        return data
    }
    
    /// Creates an ExerciseSetLog from a Firestore document.
    /// Converts Firestore Timestamp back to Swift Date.
    /// Note: userId is optional for backward compatibility with existing documents.
    static func fromFirestore(id: String, data: [String: Any]) -> ExerciseSetLog? {
        guard let workoutLogId = data["workoutLogId"] as? String,
              let exerciseName = data["exerciseName"] as? String,
              let setNumber = data["setNumber"] as? Int,
              let flaggedPain = data["flaggedPain"] as? Bool,
              let flaggedNotInControl = data["flaggedNotInControl"] as? Bool,
              let timestamp = data["timestamp"] as? Timestamp else {
            return nil
        }
        
        // userId is optional for backward compatibility (existing documents may not have it)
        // For new documents, userId should always be present
        let userId = data["userId"] as? String ?? ""
        
        var log = ExerciseSetLog(
            id: id,
            workoutLogId: workoutLogId,
            userId: userId,
            exerciseName: exerciseName,
            setNumber: setNumber,
            flaggedPain: flaggedPain,
            flaggedNotInControl: flaggedNotInControl,
            timestamp: timestamp.dateValue()
        )
        
        if let weight = data["weight"] as? Double {
            log.weight = weight
        }
        
        if let reps = data["reps"] as? Int {
            log.reps = reps
        }
        
        return log
    }
}
