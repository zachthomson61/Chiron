//
//  CompleteProfileSheet.swift
//  Chiron
//
//  Two-step "Complete User Profile" flow that converts the post-onboarding
//  anonymous profile into a named local account. Reuses the onboarding design
//  system (canvas, top bar, primary CTA) so the sheet feels like a continuation
//  of the onboarding flow rather than a Settings-style form.
//
//      Step 1 — first + last name
//      Step 2 — email + password + password confirmation
//
//  Values land in `AccountStore` (UserDefaults + Keychain). No remote auth.
//

import SwiftUI
import UIKit

struct CompleteProfileSheet: View {
    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    let initialFirstName: String
    let initialLastName: String
    let initialEmail: String
    let onSave: (_ name: String, _ email: String, _ password: String) -> Void

    @State private var step: Int = 0
    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var direction: Direction = .forward

    enum Mode { case create, edit }
    private enum Direction { case forward, backward }

    private let totalSteps = 2

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                switch step {
                case 0: nameStep
                default: accountStep
                }
            }
            .id(step)
            .transition(OnboardingTheme.screenTransition(forward: direction == .forward))

            closeButton
                .padding(.trailing, 16)
                .padding(.top, 8)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if firstName.isEmpty { firstName = initialFirstName }
            if lastName.isEmpty { lastName = initialLastName }
            if email.isEmpty { email = initialEmail }
        }
    }

    // MARK: - Step 1: name

    private var nameStep: some View {
        OnboardingScreenScaffold(
            title: "What's your name?",
            subtitle: "We'll show this on your profile.",
            ctaTitle: "Continue",
            ctaEnabled: nameValid,
            currentStep: 1,
            totalSteps: totalSteps,
            onContinue: { advance(to: 1, direction: .forward) },
            onBack: nil
        ) {
            VStack(spacing: 12) {
                OnboardingTextField(
                    placeholder: "First name",
                    text: $firstName,
                    contentType: .givenName,
                    autocap: .words
                )
                OnboardingTextField(
                    placeholder: "Last name",
                    text: $lastName,
                    contentType: .familyName,
                    autocap: .words
                )
            }
        }
    }

    // MARK: - Step 2: account

    private var accountStep: some View {
        OnboardingScreenScaffold(
            title: "Set up your login",
            subtitle: "Saved only on this device — Chiron never sends it anywhere.",
            ctaTitle: mode == .create ? "Complete Profile" : "Save Changes",
            ctaEnabled: accountValid,
            currentStep: 2,
            totalSteps: totalSteps,
            onContinue: complete,
            onBack: { advance(to: 0, direction: .backward) }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                OnboardingTextField(
                    placeholder: "Email",
                    text: $email,
                    contentType: .emailAddress,
                    isSecure: false,
                    keyboard: .emailAddress,
                    autocap: .never
                )
                OnboardingTextField(
                    placeholder: passwordPlaceholder,
                    text: $password,
                    contentType: mode == .create ? .newPassword : .password,
                    isSecure: true,
                    autocap: .never
                )
                OnboardingTextField(
                    placeholder: "Confirm password",
                    text: $confirmPassword,
                    contentType: mode == .create ? .newPassword : .password,
                    isSecure: true,
                    autocap: .never
                )

                if shouldFlagMismatch {
                    Text("Passwords don't match")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.red.opacity(0.85))
                        .padding(.leading, 4)
                        .transition(.opacity)
                }
            }
            .animation(OnboardingTheme.selectionSpring, value: shouldFlagMismatch)
        }
    }

    // MARK: - Close button

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(OnboardingTheme.textPrimary)
                .frame(width: 36, height: 36)
                .background(Circle().fill(OnboardingTheme.surface))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
    }

    // MARK: - Actions

    private func advance(to newStep: Int, direction newDirection: Direction) {
        direction = newDirection
        withAnimation(OnboardingTheme.selectionSpring) {
            step = newStep
        }
    }

    private func complete() {
        let trimmedFirst = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLast = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let composed = "\(trimmedFirst) \(trimmedLast)".trimmingCharacters(in: .whitespacesAndNewlines)
        onSave(
            composed,
            email.trimmingCharacters(in: .whitespacesAndNewlines),
            password
        )
        dismiss()
    }

    // MARK: - Validation

    private var nameValid: Bool {
        !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var accountValid: Bool {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidEmail(trimmedEmail) else { return false }
        switch mode {
        case .create:
            return password.count >= 6 && password == confirmPassword
        case .edit:
            // Both blank = keep existing password.
            if password.isEmpty && confirmPassword.isEmpty { return true }
            return password.count >= 6 && password == confirmPassword
        }
    }

    /// Only show the mismatch hint once the user has typed something into
    /// confirm — flashing it on every keystroke would be noisy.
    private var shouldFlagMismatch: Bool {
        !confirmPassword.isEmpty && password != confirmPassword
    }

    private var passwordPlaceholder: String {
        mode == .create ? "Password" : "New password (or leave blank)"
    }

    private func isValidEmail(_ value: String) -> Bool {
        guard let atIndex = value.firstIndex(of: "@") else { return false }
        let local = value[value.startIndex..<atIndex]
        let domain = value[value.index(after: atIndex)..<value.endIndex]
        return !local.isEmpty && domain.contains(".") && !domain.hasSuffix(".")
    }
}

// MARK: - Onboarding-styled text field

/// Pill-shaped text field that mirrors `OnboardingOptionRow`'s surface + stroke
/// treatment so the sheet's inputs feel native to the onboarding flow.
struct OnboardingTextField: View {
    let placeholder: String
    @Binding var text: String
    var contentType: UITextContentType?
    var isSecure: Bool = false
    var keyboard: UIKeyboardType = .default
    var autocap: TextInputAutocapitalization = .sentences

    var body: some View {
        Group {
            if isSecure {
                SecureField("", text: $text, prompt: prompt)
            } else {
                TextField("", text: $text, prompt: prompt)
                    .keyboardType(keyboard)
            }
        }
        .font(.system(size: 17, weight: .medium))
        .foregroundStyle(OnboardingTheme.textPrimary)
        .tint(OnboardingTheme.accentStart)
        .textContentType(contentType)
        .textInputAutocapitalization(autocap)
        .autocorrectionDisabled()
        .padding(.horizontal, 20)
        .frame(height: OnboardingTheme.optionRowHeight)
        .background(
            RoundedRectangle(cornerRadius: OnboardingTheme.cornerRadiusLarge, style: .continuous)
                .fill(OnboardingTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OnboardingTheme.cornerRadiusLarge, style: .continuous)
                .strokeBorder(OnboardingTheme.stroke, lineWidth: 1)
        )
    }

    private var prompt: Text {
        Text(placeholder).foregroundStyle(OnboardingTheme.textTertiary)
    }
}
