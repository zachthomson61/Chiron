//
//  UserProfileStore.swift
//  Chiron
//
//  Thin persistence abstraction so the onboarding flow doesn't hard-code UserDefaults.
//  Swap for CoreData / CloudKit / Firestore later by providing a new conforming type —
//  no onboarding code has to change.
//

import Foundation

/// Persistence surface for `ChironUserProfile`.
protocol UserProfileStore {
    func load() -> ChironUserProfile?
    func save(_ profile: ChironUserProfile) throws
    func clear()
}

// MARK: - UserDefaults-backed default

/// Default UserDefaults implementation. Stored as JSON under a versioned key so migrations
/// are explicit rather than silent.
final class UserDefaultsUserProfileStore: UserProfileStore {

    static let storageKey = "chiron.user_profile.v1"
    static let completionKey = "chiron.onboarding_completed.v1"

    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> ChironUserProfile? {
        guard let data = defaults.data(forKey: Self.storageKey) else { return nil }
        return try? decoder.decode(ChironUserProfile.self, from: data)
    }

    func save(_ profile: ChironUserProfile) throws {
        let data = try encoder.encode(profile)
        defaults.set(data, forKey: Self.storageKey)
        defaults.set(true, forKey: Self.completionKey)
    }

    func clear() {
        defaults.removeObject(forKey: Self.storageKey)
        defaults.removeObject(forKey: Self.completionKey)
    }

    /// Convenience flag used by the app root to decide whether to show onboarding.
    var hasCompletedOnboarding: Bool {
        defaults.bool(forKey: Self.completionKey)
    }
}

// MARK: - In-Memory (previews & tests)

final class InMemoryUserProfileStore: UserProfileStore {
    private var storage: ChironUserProfile?

    init(seed: ChironUserProfile? = nil) { self.storage = seed }

    func load() -> ChironUserProfile? { storage }
    func save(_ profile: ChironUserProfile) throws { storage = profile }
    func clear() { storage = nil }
}
