//
//  WorkoutLogService.swift
//  Chiron
//
//  Service for managing workout logs and exercise set logs in Firebase Firestore.
//  Handles creating workout logs, saving set logs, and retrieving exercise history.
//

import Foundation
import FirebaseFirestore
import FirebaseCore

/// Ensures Firebase is configured once, on the main thread, right before first use.
/// 
/// This is used by WorkoutLogService to ensure Firebase is initialized before accessing Firestore.
/// Prevents crashes when WorkoutLogService is accessed before FirebaseApp.configure() has been called.
private enum FirebaseConfigurator {
    static func ensureConfigured() {
        guard FirebaseApp.app() == nil else { return }

        if Thread.isMainThread {
            FirebaseApp.configure()
        } else {
            DispatchQueue.main.sync {
                if FirebaseApp.app() == nil {
                    FirebaseApp.configure()
                }
            }
        }
    }
}

/// Service for managing workout logs and exercise set logs in Firebase Firestore.
class WorkoutLogService {
    static let shared = WorkoutLogService()
    
    /// Firestore database instance.
    /// Uses lazy initialization to ensure Firebase is configured before accessing Firestore.
    /// This prevents crashes when the service is accessed before FirebaseApp.configure() has been called.
    private lazy var db: Firestore = {
        // Ensure Firebase is configured before accessing Firestore
        FirebaseConfigurator.ensureConfigured()
        return Firestore.firestore()
    }()
    
    private let workoutLogsCollection = "workoutLogs"
    private let exerciseSetLogsCollection = "exerciseSetLogs"
    
    private init() {}
    
    // MARK: - Workout Log Management
    
    /// Creates a new workout log in Firestore.
    ///
    /// - Parameters:
    ///   - workoutName: Name of the workout
    ///   - userId: User ID (device-based)
    ///   - completion: Callback with Result containing workout log ID on success, or Error on failure
    func createWorkoutLog(workoutName: String, userId: String, completion: @escaping (Result<String, Error>) -> Void) {
        let workoutLog: [String: Any] = [
            "workoutName": workoutName,
            "userId": userId,
            "startTime": Timestamp(date: Date()),
            "endTime": NSNull(),
            "totalDuration": NSNull(),
            "totalPausedDuration": NSNull()
        ]
        
        var ref: DocumentReference?
        ref = db.collection(workoutLogsCollection).addDocument(data: workoutLog) { error in
            if let error = error {
                completion(.failure(error))
            } else if let documentId = ref?.documentID {
                completion(.success(documentId))
            } else {
                let unknownError = NSError(domain: "WorkoutLogService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown error creating workout log"])
                completion(.failure(unknownError))
            }
        }
    }
    
    /// Ends a workout log by updating the end time and total duration.
    ///
    /// - Parameters:
    ///   - workoutLogId: The ID of the workout log to end
    ///   - totalDuration: Total duration of the workout in seconds
    ///   - totalPausedDuration: Total time paused during the workout in seconds
    ///   - completion: Callback with Result containing success status or Error on failure
    func endWorkoutLog(workoutLogId: String, totalDuration: Int, totalPausedDuration: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        let updates: [String: Any] = [
            "endTime": Timestamp(date: Date()),
            "totalDuration": totalDuration,
            "totalPausedDuration": totalPausedDuration
        ]
        
        db.collection(workoutLogsCollection).document(workoutLogId).updateData(updates) { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }
    
    // MARK: - Exercise Set Log Management
    
    /// Saves an exercise set log to Firestore.
    ///
    /// - Parameters:
    ///   - workoutLogId: ID of the workout log this set belongs to
    ///   - userId: User ID (device-based)
    ///   - exerciseName: Name of the exercise
    ///   - setNumber: Set number (1-based)
    ///   - weight: Weight used (optional for bodyweight exercises)
    ///   - reps: Number of reps completed (optional, can save weight-only sets)
    ///   - flaggedPain: Whether the set was flagged for pain
    ///   - flaggedNotInControl: Whether the set was flagged as not in control
    ///   - completion: Callback with Result containing set log ID on success, or Error on failure
    func saveSetLog(
        workoutLogId: String,
        userId: String,
        exerciseName: String,
        setNumber: Int,
        weight: Double?,
        reps: Int?,
        flaggedPain: Bool,
        flaggedNotInControl: Bool,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let setLog = ExerciseSetLog(
            workoutLogId: workoutLogId,
            userId: userId,
            exerciseName: exerciseName,
            setNumber: setNumber,
            weight: weight,
            reps: reps,
            flaggedPain: flaggedPain,
            flaggedNotInControl: flaggedNotInControl,
            timestamp: Date()
        )
        
        let data = setLog.toFirestoreData()
        
        var ref: DocumentReference?
        ref = db.collection(exerciseSetLogsCollection).addDocument(data: data) { error in
            if let error = error {
                completion(.failure(error))
            } else if let documentId = ref?.documentID {
                completion(.success(documentId))
            } else {
                let unknownError = NSError(domain: "WorkoutLogService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown error saving set log"])
                completion(.failure(unknownError))
            }
        }
    }
    
    /// Retrieves exercise history for a specific exercise and user.
    ///
    /// - Parameters:
    ///   - exerciseName: Name of the exercise to get history for
    ///   - userId: User ID (device-based)
    ///   - limit: Maximum number of set logs to return (default: 30)
    ///   - completion: Callback with Result containing array of ExerciseSetLog on success, or Error on failure
    ///
    /// Note: This query requires a Firestore composite index on (exerciseName, userId, timestamp).
    /// Firebase will prompt to create this index when the query is first run.
    func getHistoryForExercise(_ exerciseName: String, userId: String, limit: Int = 30, completion: @escaping (Result<[ExerciseSetLog], Error>) -> Void) {
        
        db.collection(exerciseSetLogsCollection)
            .whereField("exerciseName", isEqualTo: exerciseName)
            .whereField("userId", isEqualTo: userId)
            .order(by: "timestamp", descending: true)
            .limit(to: limit)
            .getDocuments { snapshot, error in
                if let error = error {
                    // If this is a Firestore index error (code 9), create a composite index on
                    // exerciseSetLogs: exerciseName (Ascending), userId (Ascending), timestamp (Descending).
                    // Use lowercase "userId". Create at: Firebase Console → Firestore → Indexes.
                    
                    completion(.failure(error))
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    completion(.success([]))
                    return
                }
                
                let setLogs = documents.compactMap { doc -> ExerciseSetLog? in
                    ExerciseSetLog.fromFirestore(id: doc.documentID, data: doc.data())
                }
                
                completion(.success(setLogs))
            }
    }
    
}
