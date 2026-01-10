//
//  WorkoutLog.swift
//  Chiron
//
//  TrainingLog module - WorkoutLog model for Firebase Firestore
//
//  Represents a workout session in Firestore. Created when a workout starts,
//  updated with endDate when the workout completes.
//

import Foundation
import FirebaseFirestore

/// Represents a workout session log stored in Firebase Firestore.
///
/// Each workout session creates one WorkoutLog document in the `workoutLogs` collection.
/// Multiple ExerciseSetLog documents reference this workout via `workoutLogId`.
struct WorkoutLog: Codable, Identifiable {
    /// Firestore document ID (auto-generated when created)
    var id: String
    
    /// Name of the workout (e.g., "Python Wrangler")
    var workoutName: String
    
    /// Optional user ID for future multi-user support
    var userId: String?
    
    /// When the workout session started
    var startDate: Date
    
    /// When the workout session ended (nil if still in progress)
    var endDate: Date?
    
    init(id: String = UUID().uuidString, workoutName: String, userId: String? = nil, startDate: Date = Date(), endDate: Date? = nil) {
        self.id = id
        self.workoutName = workoutName
        self.userId = userId
        self.startDate = startDate
        self.endDate = endDate
    }
    
    // MARK: - Firestore Serialization
    
    /// Converts the model to a Firestore-compatible dictionary.
    /// Converts Swift Date to Firestore Timestamp for storage.
    func toFirestoreData() -> [String: Any] {
        var data: [String: Any] = [
            "workoutName": workoutName,
            "startDate": Timestamp(date: startDate)
        ]
        
        if let userId = userId {
            data["userId"] = userId
        }
        
        if let endDate = endDate {
            data["endDate"] = Timestamp(date: endDate)
        }
        
        return data
    }
    
    /// Creates a WorkoutLog from a Firestore document.
    /// Converts Firestore Timestamp back to Swift Date.
    static func fromFirestore(id: String, data: [String: Any]) -> WorkoutLog? {
        guard let workoutName = data["workoutName"] as? String,
              let startDateTimestamp = data["startDate"] as? Timestamp else {
            return nil
        }
        
        var log = WorkoutLog(
            id: id,
            workoutName: workoutName,
            startDate: startDateTimestamp.dateValue()
        )
        
        if let userId = data["userId"] as? String {
            log.userId = userId
        }
        
        if let endDateTimestamp = data["endDate"] as? Timestamp {
            log.endDate = endDateTimestamp.dateValue()
        }
        
        return log
    }
}
