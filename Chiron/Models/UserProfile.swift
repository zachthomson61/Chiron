import SwiftUI
import UIKit

// MARK: - User Profile Model

/// Represents a user's profile information.
/// TODO: Wire to real onboarding data and user authentication system.
struct UserProfile {
    var name: String
    var memberSince: Date
    var totalWorkouts: Int
    var totalLbsLifted: Int
    var achievements: [Achievement]
    var profileImage: UIImage?
    /// User's gender preference. Values: "male", "female", or nil.
    /// Currently read from UserDefaults. TODO: Wire to onboarding flow when built.
    var gender: String?
    
    /// Formats total lbs lifted as a compact string (e.g., "75K" for 75,000)
    var formattedLbsLifted: String {
        if totalLbsLifted >= 1000 {
            let thousands = Double(totalLbsLifted) / 1000.0
            if thousands >= 100 {
                return String(format: "%.0fK", thousands)
            } else {
                return String(format: "%.1fK", thousands).replacingOccurrences(of: ".0", with: "")
            }
        }
        return "\(totalLbsLifted)"
    }
    
    /// Formats member since date as "MMM YYYY" (e.g., "Nov 2025")
    var formattedMemberSince: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter.string(from: memberSince)
    }
}

// MARK: - Achievement Model

/// Represents a user achievement badge.
struct Achievement: Identifiable {
    let id = UUID()
    let value: String
    let label: String
    let badgeColor: Color
    
    init(value: String, label: String, badgeColor: Color = .pink) {
        self.value = value
        self.label = label
        self.badgeColor = badgeColor
    }
}

// MARK: - Mock Data Factory

extension UserProfile {
    /// Reads gender preference from UserDefaults.
    /// Key: "user_gender", Values: "male", "female", or nil.
    /// TODO: Replace with real onboarding flow when built.
    static func readGenderFromDefaults() -> String? {
        return UserDefaults.standard.string(forKey: "user_gender")
    }
    
    /// Creates a mock user profile for development and previews.
    static func mock() -> UserProfile {
        UserProfile(
            name: "Zachary Thomson", // TODO: Wire to onboarding data
            memberSince: Calendar.current.date(byAdding: .month, value: -2, to: Date()) ?? Date(),
            totalWorkouts: 8, // TODO: Wire to workout tracking system
            totalLbsLifted: 75000, // TODO: Wire to workout tracking system
            achievements: [
                Achievement(value: "500", label: "CALORIES", badgeColor: Color(red: 1.0, green: 0.8, blue: 0.9)),
                Achievement(value: "1000", label: "CALORIES", badgeColor: Color(red: 1.0, green: 0.8, blue: 0.9))
            ], // TODO: Wire to real achievement system
            profileImage: nil,
            gender: readGenderFromDefaults() // Read from UserDefaults for now
        )
    }
}

// MARK: - Coach Model

/// Represents a coach/trainer assigned to the user.
/// TODO: Wire to real coach system.
struct Coach: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let avatarImage: UIImage?
    
    static func mock() -> Coach {
        Coach(
            name: "Beau Bartone",
            description: "Previously: Strength Coach for Ivy League school, Yale University...",
            avatarImage: nil
        )
    }
}

