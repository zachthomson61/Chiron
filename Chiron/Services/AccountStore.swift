//
//  AccountStore.swift
//  Chiron
//
//  Persistence + observable state for the local user account (name/email/password
//  + profile picture). Stays separate from `UserDefaultsUserProfileStore` (which
//  owns the onboarding-derived `ChironUserProfile`) because identity is optional
//  and decoupled from the training profile — an "anonymous" user has a complete
//  ChironUserProfile but no AccountDetails.
//

import Foundation
import UIKit
import Combine

@MainActor
final class AccountStore: ObservableObject {
    static let shared = AccountStore()

    @Published private(set) var details: AccountDetails?
    @Published private(set) var profileImage: UIImage?

    private let detailsKey = "chiron.account_details.v1"
    private let imageKey = "chiron.account_profile_image.v1"
    private let passwordKeychainAccount = "chiron.account_password.v1"

    /// Avatar images are downscaled to this max edge length before being persisted
    /// — keeps the UserDefaults blob bounded so we don't bloat the preferences file.
    private let avatarMaxDimension: CGFloat = 512

    private init() {
        load()
    }

    // MARK: - Load

    private func load() {
        if let data = UserDefaults.standard.data(forKey: detailsKey),
           let decoded = try? JSONDecoder().decode(AccountDetails.self, from: data) {
            details = decoded
        }
        if let imageData = UserDefaults.standard.data(forKey: imageKey),
           let image = UIImage(data: imageData) {
            profileImage = image
        }
    }

    // MARK: - Save

    /// Persists name + email, and stores the password in Keychain when supplied.
    /// Pass an empty `password` on edit to leave the existing one untouched.
    func save(name: String, email: String, password: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let createdAt = details?.createdAt ?? Date()
        var hasPassword = details?.hasPassword ?? false

        if !password.isEmpty {
            hasPassword = KeychainHelper.set(password, account: passwordKeychainAccount) || hasPassword
        }

        let updated = AccountDetails(
            name: trimmedName,
            email: trimmedEmail,
            createdAt: createdAt,
            hasPassword: hasPassword
        )

        if let data = try? JSONEncoder().encode(updated) {
            UserDefaults.standard.set(data, forKey: detailsKey)
        }
        details = updated
    }

    // MARK: - Avatar

    func updateProfileImage(_ image: UIImage?) {
        if let image {
            let resized = Self.resized(image, maxDimension: avatarMaxDimension)
            profileImage = resized
            if let data = resized.jpegData(compressionQuality: 0.85) {
                UserDefaults.standard.set(data, forKey: imageKey)
            }
        } else {
            profileImage = nil
            UserDefaults.standard.removeObject(forKey: imageKey)
        }
    }

    private static func resized(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension else { return image }
        let scale = maxDimension / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    // MARK: - Reset (used by the DEBUG onboarding-reset overlay)

    func clear() {
        details = nil
        profileImage = nil
        UserDefaults.standard.removeObject(forKey: detailsKey)
        UserDefaults.standard.removeObject(forKey: imageKey)
        KeychainHelper.delete(account: passwordKeychainAccount)
    }
}
