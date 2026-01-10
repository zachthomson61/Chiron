//
//  WorkoutLogService.swift
//  Chiron
//
//  TrainingLog module - Service for managing workout logs in Firebase Firestore
//
//  Provides async operations for creating workout sessions, logging exercise sets,
//  and retrieving exercise history. All data is persisted to Firestore collections:
//  - `workoutLogs`: One document per workout session
//  - `exerciseSetLogs`: One document per set logged
//

import Foundation
import FirebaseFirestore
import FirebaseCore

/// Ensures Firebase is configured once, on the main thread, right before first use.
/// Reuses the same configuration pattern as FirebaseManager.
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
///
/// Singleton service that handles all Firestore operations for workout logging.
/// Follows the same pattern as FirebaseManager for consistency.
///
/// ## Data Flow
///
/// 1. **Workout Start**: `createWorkoutLog()` creates a WorkoutLog document
/// 2. **During Workout**: `saveSetLog()` creates ExerciseSetLog documents as user logs sets
/// 3. **Workout End**: `endWorkoutLog()` updates the WorkoutLog with endDate
/// 4. **History**: `getHistoryForExercise()` queries ExerciseSetLog documents by exercise name
///
/// ## Firestore Collections
///
/// - `workoutLogs`: One document per workout session
/// - `exerciseSetLogs`: One document per set logged (references workoutLogId)
///
/// ## Usage Example
///
/// ```swift
/// let service = WorkoutLogService.shared
/// service.createWorkoutLog(workoutName: "My Workout") { result in
///     switch result {
///     case .success(let logId):
///         // Store logId for subsequent set logs
///     case .failure(let error):
///         // Handle error
///     }
/// }
/// ```
class WorkoutLogService: ObservableObject {
    static let shared = WorkoutLogService()
    
    /// Lazy Firestore database instance (configured on first access)
    private lazy var db: Firestore = {
        FirebaseConfigurator.ensureConfigured()
        return Firestore.firestore()
    }()
    
    /// Firestore collection name for workout logs
    private let workoutLogsCollection = "workoutLogs"
    
    /// Firestore collection name for exercise set logs
    private let exerciseSetLogsCollection = "exerciseSetLogs"
    
    private init() {}
    
    // MARK: - Workout Log Operations
    
    /// Creates a new workout log in Firestore.
    ///
    /// - Parameters:
    ///   - workoutName: Name of the workout (e.g., "Python Wrangler")
    ///   - completion: Callback with Result containing the document ID on success, or Error on failure
    ///
    /// The document ID is returned so it can be used to associate ExerciseSetLog entries.
    func createWorkoutLog(workoutName: String, completion: @escaping (Result<String, Error>) -> Void) {
        let workoutLog = WorkoutLog(workoutName: workoutName)
        let data = workoutLog.toFirestoreData()
        
        var ref: DocumentReference?
        ref = db.collection(workoutLogsCollection).addDocument(data: data) { error in
            if let error = error {
                print("❌ Error creating workout log: \(error.localizedDescription)")
                completion(.failure(error))
            } else if let documentId = ref?.documentID {
                print("✅ Workout log created with ID: \(documentId)")
                completion(.success(documentId))
            } else {
                completion(.failure(NSError(domain: "WorkoutLogService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get document ID"])))
            }
        }
    }
    
    /// Marks a workout log as completed by setting the endDate.
    ///
    /// - Parameters:
    ///   - workoutLogId: The Firestore document ID of the workout log
    ///   - completion: Callback with Result indicating success or failure
    func endWorkoutLog(workoutLogId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let endDate = Timestamp(date: Date())
        db.collection(workoutLogsCollection).document(workoutLogId).updateData([
            "endDate": endDate
        ]) { error in
            if let error = error {
                print("❌ Error ending workout log: \(error.localizedDescription)")
                completion(.failure(error))
            } else {
                print("✅ Workout log ended: \(workoutLogId)")
                completion(.success(()))
            }
        }
    }
    
    // MARK: - Exercise Set Log Operations
    
    /// Saves an individual set log to Firestore.
    ///
    /// Creates a new document in the `exerciseSetLogs` collection with the set data.
    /// Weight is optional (nil for bodyweight exercises). Reps is required.
    ///
    /// - Parameters:
    ///   - workoutLogId: The Firestore document ID of the parent WorkoutLog
    ///   - exerciseName: Name of the exercise (e.g., "Barbell Back Squat")
    ///   - setNumber: Set number within the exercise (1, 2, 3, etc.)
    ///   - weight: Weight in pounds (nil for bodyweight exercises)
    ///   - reps: Number of reps completed
    ///   - flaggedPain: Whether user experienced pain
    ///   - flaggedNotInControl: Whether user felt not in control
    ///   - completion: Callback with Result containing document ID on success, or Error on failure
    func saveSetLog(
        workoutLogId: String,
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
            exerciseName: exerciseName,
            setNumber: setNumber,
            weight: weight,
            reps: reps,
            flaggedPain: flaggedPain,
            flaggedNotInControl: flaggedNotInControl
        )
        
        let data = setLog.toFirestoreData()
        
        var ref: DocumentReference?
        ref = db.collection(exerciseSetLogsCollection).addDocument(data: data) { error in
            if let error = error {
                print("❌ Error saving set log: \(error.localizedDescription)")
                completion(.failure(error))
            } else if let documentId = ref?.documentID {
                print("✅ Set log saved with ID: \(documentId)")
                completion(.success(documentId))
            } else {
                completion(.failure(NSError(domain: "WorkoutLogService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get document ID"])))
            }
        }
    }
    
    // MARK: - History Operations
    
    /// Retrieves exercise history from Firestore.
    ///
    /// Fetches all set logs for a specific exercise, ordered by most recent first.
    /// Used to display previous performance in the ExerciseHistorySheet.
    ///
    /// - Parameters:
    ///   - exerciseName: Name of the exercise to get history for
    ///   - limit: Maximum number of set logs to return (default: 30)
    ///   - completion: Callback with Result containing array of ExerciseSetLog on success, or Error on failure
    func getHistoryForExercise(_ exerciseName: String, limit: Int = 30, completion: @escaping (Result<[ExerciseSetLog], Error>) -> Void) {
        db.collection(exerciseSetLogsCollection)
            .whereField("exerciseName", isEqualTo: exerciseName)
            .order(by: "timestamp", descending: true)
            .limit(to: limit)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("❌ Error fetching exercise history: \(error.localizedDescription)")
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
                
                print("✅ Fetched \(setLogs.count) set logs for exercise: \(exerciseName)")
                completion(.success(setLogs))
            }
    }
    
}
