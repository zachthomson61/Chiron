//
//  WeightScrollerSheet.swift
//  Chiron
//
//  Weight picker presented as a bottom sheet from the Track tab. The primary
//  input is a haptic-driven scroller of common weight intervals; a secondary
//  text field lets the user type an exact value without scrolling.
//

import SwiftUI
import UIKit

/// Weight picker for the Track tab. Scroll through common intervals (5 lb) with
/// snap-detent haptics, or type an exact value. Deliberately distinct from the
/// ±1/±5 button sheet used by the predetermined workout flow.
struct WeightScrollerSheet: View {
    @Binding var isPresented: Bool
    let initialWeight: Double?
    let onSave: (Double) -> Void

    /// Common plate/dumbbell increments — 0 to 500 lbs in 5 lb steps.
    private static let weightValues: [Double] = stride(from: 0.0, through: 500.0, by: 5.0).map { $0 }

    @State private var selectedWeight: Double
    @State private var manualInput: String
    /// Last value we provided haptic feedback for; prevents double-firing when
    /// the scroller briefly settles between two values.
    @State private var lastHapticValue: Double
    /// Whether the manual text field currently owns the input focus. Used to
    /// avoid a feedback loop when the scroller updates `manualInput`.
    @FocusState private var manualFieldFocused: Bool
    /// Drives the blinking caret on the manual input card.
    @State private var caretVisible: Bool = true

    /// Seed the wheel + text field from `initialWeight` at init time so the
    /// Picker mounts at the user's last saved value on the very first render
    /// (rather than briefly showing the default 45 lb and then snapping in
    /// `onAppear`). The manual input shows the raw seed so off-grid typed
    /// values like 137.5 are preserved between opens; the wheel snaps to
    /// the nearest 5 lb increment.
    init(isPresented: Binding<Bool>, initialWeight: Double?, onSave: @escaping (Double) -> Void) {
        self._isPresented = isPresented
        self.initialWeight = initialWeight
        self.onSave = onSave

        let seed = initialWeight ?? 45.0
        let snapped = Self.closestSnapValue(seed)
        _selectedWeight = State(initialValue: snapped)
        _manualInput = State(initialValue: Self.formatted(seed))
        _lastHapticValue = State(initialValue: snapped)
    }

    var body: some View {
        ZStack {
            Color.background.ignoresSafeArea()

            VStack(spacing: 20) {
                Text("Input Weight")
                    .font(.neueMontrealBold(size: 24))
                    .foregroundColor(.textPrimary)
                    .padding(.top, 24)

                // Manual entry — sits directly under the title so the user can
                // type without scrolling. Compact card; blinking purple caret
                // marks the insertion point.
                manualInputCard
                    .padding(.horizontal, 20)

                // Scroller. No surrounding card — just the wheel itself, which
                // provides the native centered-selection look.
                Picker("Weight", selection: $selectedWeight) {
                    ForEach(Self.weightValues, id: \.self) { value in
                        Text(Self.formatted(value))
                            .font(.neueMontrealBold(size: 22))
                            .foregroundColor(.textPrimary)
                            .tag(value)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 170)
                .onChange(of: selectedWeight) { _, newValue in
                    // Keep the text field in sync as the user scrolls, but
                    // only when the field isn't the source of truth.
                    if !manualFieldFocused {
                        manualInput = Self.formatted(newValue)
                    }
                    // Fire a light haptic on every snap — the wheel picker's
                    // built-in taptic is subtle, so we reinforce it explicitly.
                    if newValue != lastHapticValue {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        lastHapticValue = newValue
                    }
                }

                Spacer(minLength: 0)

                Button {
                    // Prefer the typed value when it's a valid number; fall
                    // back to the scroller selection otherwise.
                    let resolved: Double = {
                        if let typed = Double(manualInput), typed >= 0 {
                            return typed
                        }
                        return selectedWeight
                    }()
                    onSave(resolved)
                    isPresented = false
                } label: {
                    Text("Save")
                        .font(.neueMontrealSemiBold(size: 16))
                        .foregroundColor(.white)
                        .frame(width: 200, height: 52)
                        .background(Color.primaryPurple)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 20)
            }
        }
        .onAppear {
            // Seeding of selectedWeight / manualInput / lastHapticValue
            // happens in `init(...)` so the wheel mounts at the correct
            // value immediately. Only the caret animation needs to start
            // on appear.
            withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                caretVisible = false
            }
        }
        .preferredColorScheme(.dark)
    }

    /// Compact text card with a purple blinking caret at the end of the input.
    /// Tapping anywhere on the card focuses the hidden TextField so the keyboard
    /// comes up; the caret reads as the current insertion point.
    private var manualInputCard: some View {
        ZStack(alignment: .center) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.08))

            HStack(spacing: 2) {
                Text(manualInput.isEmpty ? " " : manualInput)
                    .font(.neueMontrealBold(size: 20))
                    .foregroundColor(.textPrimary)
                Rectangle()
                    .fill(Color.primaryPurple)
                    .frame(width: 2, height: 22)
                    .opacity(caretVisible ? 1 : 0)
                // Unit label sits to the right of the blinking caret so it's
                // always visible regardless of whether the user has typed.
                Text("lbs")
                    .font(.neueMontrealRegular(size: 16))
                    .foregroundColor(.textSecondary)
                    .padding(.leading, 4)
            }

            // Invisible editable field layered on top — receives keystrokes
            // when the card is tapped but doesn't render its own glyphs, so the
            // visible text above (plus caret) is the only thing the user sees.
            TextField("", text: $manualInput)
                .keyboardType(.decimalPad)
                .focused($manualFieldFocused)
                .foregroundColor(.clear)
                .tint(.clear)
                .accentColor(.clear)
                .multilineTextAlignment(.center)
                .onChange(of: manualInput) { _, newValue in
                    // Only steer the wheel when the change came from
                    // keyboard input — otherwise we'd fight the scroll.
                    guard manualFieldFocused else { return }
                    if let typed = Double(newValue),
                       let snapped = Self.weightValues.min(by: { abs($0 - typed) < abs($1 - typed) }) {
                        selectedWeight = snapped
                    }
                }
        }
        .frame(height: 40)
        .contentShape(Rectangle())
        .onTapGesture {
            manualFieldFocused = true
        }
    }

    private static func closestSnapValue(_ raw: Double) -> Double {
        weightValues.min(by: { abs($0 - raw) < abs($1 - raw) }) ?? raw
    }

    private static func formatted(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", value)
        } else {
            return String(format: "%.1f", value)
        }
    }
}

#Preview {
    WeightScrollerSheet(
        isPresented: .constant(true),
        initialWeight: nil,
        onSave: { _ in }
    )
}
