//
//  ExerciseSetLog.swift
//  Chiron
//
//  TrainingLog module - ExerciseSetLog model for Firebase Firestore
//

import Foundation
import FirebaseFirestore

/// Represents an individual set log for an exercise, stored in Firestore
struct ExerciseSetLog: Codable, Identifiable {
    var id: String // Firestore document ID
    var workoutLogId: String
    var exerciseName: String
    var setNumber: Int
    var weight: Double? // Optional for bodyweight exercises
    var reps: Int?
    var flaggedPain: Bool
    var flaggedNotInControl: Bool
    var timestamp: Date
    
    init(
        id: String = UUID().uuidString,
        workoutLogId: String,
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
        self.exerciseName = exerciseName
        self.setNumber = setNumber
        self.weight = weight
        self.reps = reps
        self.flaggedPain = flaggedPain
        self.flaggedNotInControl = flaggedNotInControl
        self.timestamp = timestamp
    }
    
    /// Convert to Firestore-compatible dictionary
    func toFirestoreData() -> [String: Any] {
        var data: [String: Any] = [
            "workoutLogId": workoutLogId,
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
    
    /// Create from Firestore document
    static func fromFirestore(id: String, data: [String: Any]) -> ExerciseSetLog? {
        guard let workoutLogId = data["workoutLogId"] as? String,
              let exerciseName = data["exerciseName"] as? String,
              let setNumber = data["setNumber"] as? Int,
              let flaggedPain = data["flaggedPain"] as? Bool,
              let flaggedNotInControl = data["flaggedNotInControl"] as? Bool,
              let timestamp = data["timestamp"] as? Timestamp else {
            return nil
        }
        
        var log = ExerciseSetLog(
            id: id,
            workoutLogId: workoutLogId,
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
