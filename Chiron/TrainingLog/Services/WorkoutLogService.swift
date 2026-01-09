//
//  WorkoutLogService.swift
//  Chiron
//
//  TrainingLog module - Service for managing workout logs in Firebase Firestore
//

import Foundation
import FirebaseFirestore
import FirebaseCore

/// Ensures Firebase is configured once, on the main thread, right before first use.
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

/// Service for managing workout logs and exercise set logs in Firebase Firestore
class WorkoutLogService: ObservableObject {
    static let shared = WorkoutLogService()
    
    private lazy var db: Firestore = {
        FirebaseConfigurator.ensureConfigured()
        return Firestore.firestore()
    }()
    
    private let workoutLogsCollection = "workoutLogs"
    private let exerciseSetLogsCollection = "exerciseSetLogs"
    
    private init() {}
    
    // MARK: - Workout Log Operations
    
    /// Create a new workout log in Firestore
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
    
    /// End a workout log by updating the endDate
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
    
    /// Save an individual set log to Firestore
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
    
    /// Update an existing set log
    func updateSetLog(
        setLogId: String,
        weight: Double?,
        reps: Int?,
        flaggedPain: Bool,
        flaggedNotInControl: Bool,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        var updateData: [String: Any] = [
            "flaggedPain": flaggedPain,
            "flaggedNotInControl": flaggedNotInControl
        ]
        
        if let weight = weight {
            updateData["weight"] = weight
        } else {
            updateData["weight"] = FieldValue.delete()
        }
        
        if let reps = reps {
            updateData["reps"] = reps
        } else {
            updateData["reps"] = FieldValue.delete()
        }
        
        db.collection(exerciseSetLogsCollection).document(setLogId).updateData(updateData) { error in
            if let error = error {
                print("❌ Error updating set log: \(error.localizedDescription)")
                completion(.failure(error))
            } else {
                print("✅ Set log updated: \(setLogId)")
                completion(.success(()))
            }
        }
    }
    
    // MARK: - History Operations
    
    /// Get history for a specific exercise, ordered by most recent first
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
    
    /// Get the last weight used for an exercise
    func getLastWeightForExercise(_ exerciseName: String, completion: @escaping (Result<Double?, Error>) -> Void) {
        db.collection(exerciseSetLogsCollection)
            .whereField("exerciseName", isEqualTo: exerciseName)
            .order(by: "timestamp", descending: true)
            .limit(to: 30) // Get more documents to filter client-side
            .getDocuments { snapshot, error in
                if let error = error {
                    print("❌ Error fetching last weight: \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    completion(.success(nil))
                    return
                }
                
                // Find first document with a weight value
                for document in documents {
                    if let weight = document.data()["weight"] as? Double, weight > 0 {
                        completion(.success(weight))
                        return
                    }
                }
                
                completion(.success(nil))
            }
    }
    
    /// Get the last reps used for an exercise
    func getLastRepsForExercise(_ exerciseName: String, completion: @escaping (Result<Int?, Error>) -> Void) {
        db.collection(exerciseSetLogsCollection)
            .whereField("exerciseName", isEqualTo: exerciseName)
            .order(by: "timestamp", descending: true)
            .limit(to: 30) // Get more documents to filter client-side
            .getDocuments { snapshot, error in
                if let error = error {
                    print("❌ Error fetching last reps: \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    completion(.success(nil))
                    return
                }
                
                // Find first document with a reps value
                for document in documents {
                    if let reps = document.data()["reps"] as? Int, reps > 0 {
                        completion(.success(reps))
                        return
                    }
                }
                
                completion(.success(nil))
            }
    }
}
