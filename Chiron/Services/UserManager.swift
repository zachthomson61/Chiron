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
}
