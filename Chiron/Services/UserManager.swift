//
//  UserManager.swift
//  Chiron
//
//  Service for managing device-based user identification.
//  Generates and persists a unique user ID for the device.
//

import Foundation
import UIKit

/// Service for managing device-based user identification.
///
/// Provides a consistent user ID for the device that persists across app launches.
/// Uses identifierForVendor as the primary source, with fallback to a stored UUID.
class UserManager {
    static let shared = UserManager()
    
    private let userIdKey = "chiron_user_id"
    private let bodyweightKey = "chiron_current_bodyweight_lbs"
    /// Default bodyweight (lbs) used when the user hasn't completed the
    /// onboarding step yet. Temporary placeholder for testing; once the
    /// onboarding flow writes the real value via `setCurrentBodyweight`,
    /// this default is no longer consulted.
    private let defaultBodyweightLbs: Double = 180.0

    private init() {}
    
    /// Gets the user ID for this device.
    ///
    /// - Returns: A unique string identifier for the device
    ///
    /// The ID is generated once and stored in UserDefaults for persistence.
    /// Uses identifierForVendor if available, otherwise generates and stores a UUID.
    func getUserId() -> String {
        // First, try to get existing stored ID
        if let storedId = UserDefaults.standard.string(forKey: userIdKey), !storedId.isEmpty {
            return storedId
        }
        
        // Try to use identifierForVendor (unique per vendor per device)
        if let vendorId = UIDevice.current.identifierForVendor?.uuidString {
            UserDefaults.standard.set(vendorId, forKey: userIdKey)
            return vendorId
        }
        
        // Fallback: generate and store a UUID
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: userIdKey)
        return newId
    }
    
    /// Resets the user ID (for testing or account switching).
    /// This will generate a new ID on the next call to getUserId().
    func resetUserId() {
        UserDefaults.standard.removeObject(forKey: userIdKey)
    }

    // MARK: - Bodyweight

    /// The user's current bodyweight in lbs. Used by bodyweight-exercise
    /// progression charts to compute daily volume (total reps × bodyweight).
    /// Falls back to `defaultBodyweightLbs` (180) when unset — this is the
    /// temporary testing default until onboarding writes the real value.
    func getCurrentBodyweight() -> Double {
        let stored = UserDefaults.standard.double(forKey: bodyweightKey)
        return stored > 0 ? stored : defaultBodyweightLbs
    }

    /// Stores the user's bodyweight (lbs). Called from the onboarding flow.
    func setCurrentBodyweight(_ weight: Double) {
        guard weight > 0 else { return }
        UserDefaults.standard.set(weight, forKey: bodyweightKey)
    }
}
