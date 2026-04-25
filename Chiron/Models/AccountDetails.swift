//
//  AccountDetails.swift
//  Chiron
//
//  Local-only identity captured by the "Complete User Profile" flow.
//  We deliberately do not collect this during onboarding to keep that flow
//  friction-free; the user can fill it in from the Profile tab whenever they
//  want. No remote auth is wired up — `hasPassword` just records whether a
//  password lives in Keychain.
//

import Foundation

struct AccountDetails: Codable, Equatable {
    var name: String
    var email: String
    var createdAt: Date
    var hasPassword: Bool

    init(name: String, email: String, createdAt: Date = Date(), hasPassword: Bool = false) {
        self.name = name
        self.email = email
        self.createdAt = createdAt
        self.hasPassword = hasPassword
    }
}
