//
//  AccuracyFlagSheet.swift
//  Chiron
//
//  Modal sheet for tester-reported set-tracking inaccuracies. Three
//  options — Rep Count Off, Coach Feedback Wrong, Both / Other — that
//  capture the exact inputs the AI pipeline saw and write them as JSON
//  into the standard telemetry pipeline for triage in R2.
//
//  This sheet is intentionally distinct from `FlagOptionsSheet` (which
//  flags pain / not-in-control on the user-facing set log). Different
//  audience, different storage path.
//

import SwiftUI

struct AccuracyFlagSheet: View {
    @Binding var isPresented: Bool

    /// The phase the flag is being raised in — passed through to the
    /// store so the snapshot pulls from the right source.
    let phase: AccuracyFlagPhase

    /// Called after the JSON is queued for upload. The view layer uses
    /// this to flash a small confirmation if it wants to.
    let onSubmitted: ((AccuracyFlagCategory, Bool) -> Void)?

    @State private var didSubmit = false

    var body: some View {
        NavigationView {
            ZStack {
                Color.background.ignoresSafeArea()

                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Text("Flag This Set")
                            .font(.neueMontrealBold(size: 28))
                            .foregroundColor(.textPrimary)

                        Text("What went wrong with the tracking?")
                            .font(.neueMontrealRegular(size: 16))
                            .foregroundColor(.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 20)

                    VStack(spacing: 12) {
                        AccuracyFlagOptionRow(
                            category: .repCountOff,
                            icon: "list.number",
                            color: .expertRed,
                            action: { handleSelect(.repCountOff) }
                        )
                        AccuracyFlagOptionRow(
                            category: .coachFeedbackWrong,
                            icon: "ear",
                            color: .intermediateYellow,
                            action: { handleSelect(.coachFeedbackWrong) }
                        )
                        AccuracyFlagOptionRow(
                            category: .bothOrOther,
                            icon: "exclamationmark.bubble.fill",
                            color: .primaryPurple,
                            action: { handleSelect(.bothOrOther) }
                        )
                    }
                    .padding(.horizontal, 20)

                    Spacer()

                    if didSubmit {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Flag sent — thanks.")
                                .font(.neueMontrealSemiBold(size: 16))
                                .foregroundColor(.textPrimary)
                        }
                        .padding(.bottom, 24)
                        .transition(.opacity)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { isPresented = false }
                        .foregroundColor(.textPrimary)
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    private func handleSelect(_ category: AccuracyFlagCategory) {
        let ok = AccuracyFlagStore.shared.submit(category: category, phase: phase)
        onSubmitted?(category, ok)
        withAnimation(.easeInOut(duration: 0.2)) { didSubmit = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            isPresented = false
        }
    }
}

private struct AccuracyFlagOptionRow: View {
    let category: AccuracyFlagCategory
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(color)
                    .frame(width: 44, height: 44)
                    .background(color.opacity(0.18))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(category.displayTitle)
                        .font(.neueMontrealSemiBold(size: 18))
                        .foregroundColor(.textPrimary)
                    Text(category.displayDescription)
                        .font(.neueMontrealRegular(size: 14))
                        .foregroundColor(.textSecondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.textSecondary)
            }
            .padding(16)
            .background(Color.white.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(color.opacity(0.35), lineWidth: 1)
            )
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    AccuracyFlagSheet(
        isPresented: .constant(true),
        phase: .afterSet,
        onSubmitted: nil
    )
}
