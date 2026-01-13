//
//  CameraCoachingPreferences.swift
//  Chiron
//
//  Manager for camera coaching preferences per exercise.
//  Stores and retrieves user preferences for enabling/disabling camera coaching.
//

import Foundation
import SwiftUI

/// Manager for camera coaching preferences.
///
/// Stores per-exercise camera coaching preferences in UserDefaults.
/// Defaults to enabled (true) for all exercises if not explicitly set.
///
/// Usage:
/// ```swift
/// // Check if coaching is enabled for an exercise
/// let isEnabled = CameraCoachingPreferencesManager.shared.isCameraCoachingEnabled(for: "Close-Grip Bench Press")
///
/// // Set coaching preference (will be used when settings UI is added)
/// CameraCoachingPreferencesManager.shared.setCameraCoaching(enabled: false, for: "Close-Grip Bench Press")
/// ```
class CameraCoachingPreferencesManager: ObservableObject {
    static let shared = CameraCoachingPreferencesManager()
    
    private let keyPrefix = "camera_coaching_"
    
    private init() {}
    
    /// Check if camera coaching is enabled for a specific exercise.
    /// - Parameter exerciseName: The name of the exercise to check
    /// - Returns: `true` if coaching is enabled (default), `false` if explicitly disabled
    func isCameraCoachingEnabled(for exerciseName: String) -> Bool {
        let key = keyPrefix + exerciseName.replacingOccurrences(of: " ", with: "_")
        
        // If not set, default to enabled (true)
        if UserDefaults.standard.object(forKey: key) == nil {
            return true
        }
        
        return UserDefaults.standard.bool(forKey: key)
    }
    
    /// Set camera coaching preference for a specific exercise.
    /// - Parameters:
    ///   - enabled: Whether coaching should be enabled
    ///   - exerciseName: The name of the exercise
    func setCameraCoaching(enabled: Bool, for exerciseName: String) {
        let key = keyPrefix + exerciseName.replacingOccurrences(of: " ", with: "_")
        UserDefaults.standard.set(enabled, forKey: key)
        objectWillChange.send()
    }
    
    /// Reset camera coaching preference for a specific exercise to default (enabled).
    /// - Parameter exerciseName: The name of the exercise
    func resetCameraCoaching(for exerciseName: String) {
        let key = keyPrefix + exerciseName.replacingOccurrences(of: " ", with: "_")
        UserDefaults.standard.removeObject(forKey: key)
        objectWillChange.send()
    }
}
