//
//  WorkoutLog.swift
//  Chiron
//
//  TrainingLog module - WorkoutLog model for Firebase Firestore
//

import Foundation
import FirebaseFirestore

/// Represents a workout session log stored in Firestore
struct WorkoutLog: Codable, Identifiable {
    var id: String // Firestore document ID
    var workoutName: String
    var userId: String?
    var startDate: Date
    var endDate: Date?
    
    init(id: String = UUID().uuidString, workoutName: String, userId: String? = nil, startDate: Date = Date(), endDate: Date? = nil) {
        self.id = id
        self.workoutName = workoutName
        self.userId = userId
        self.startDate = startDate
        self.endDate = endDate
    }
    
    /// Convert to Firestore-compatible dictionary
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
    
    /// Create from Firestore document
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
