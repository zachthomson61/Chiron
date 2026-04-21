//
//  OnboardingOptionRow.swift
//  Chiron
//
//  Pill-shaped 64pt option row. Gradient stroke + inner glow on select, with an
//  animated radio/check circle on the left.
//

import SwiftUI
import UIKit

/// Pill-shaped option row used across single-select and multi-select questions.
///
/// Passing `descriptor` turns this into the taller coach-persona card variant
/// where the label and descriptor stack vertically.
struct OnboardingOptionRow: View {
    let title: String
    var icon: String? = nil
    var descriptor: String? = nil
    var isMultiSelect: Bool = false
    let isSelected: Bool
    let onTap: () -> Void

    private var rowHeight: CGFloat {
        descriptor == nil ? OnboardingTheme.optionRowHeight : 88
    }

    var body: some View {
        Button(action: fire) {
            HStack(spacing: 16) {
                selectionMark

                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(
                            isSelected
                            ? AnyShapeStyle(OnboardingTheme.accentGradient)
                            : AnyShapeStyle(OnboardingTheme.textSecondary)
                        )
                        .frame(width: 24)
                }

                VStack(alignment: .leading, spacing: 2) {
                    OnboardingTypography.optionLabel(title)
                    if let descriptor = descriptor {
                        OnboardingTypography.optionDescriptor(descriptor)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .frame(height: rowHeight)
            .frame(maxWidth: .infinity)
            .background(background)
            .overlay(strokeOverlay)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(OnboardingTheme.selectionSpring, value: isSelected)
    }

    @ViewBuilder
    private var selectionMark: some View {
        ZStack {
            Circle()
                .stroke(
                    isSelected ? Color.clear : OnboardingTheme.stroke,
                    lineWidth: 1.5
                )
                .frame(width: 22, height: 22)

            if isSelected {
                Circle()
                    .fill(OnboardingTheme.accentGradient)
                    .frame(width: 22, height: 22)

                Image(systemName: isMultiSelect ? "checkmark" : "circle.fill")
                    .font(.system(size: isMultiSelect ? 11 : 7, weight: .bold))
                    .foregroundStyle(Color.white)
            }
        }
        .frame(width: 22, height: 22)
    }

    @ViewBuilder
    private var background: some View {
        ZStack {
            RoundedRectangle(cornerRadius: OnboardingTheme.cornerRadiusLarge, style: .continuous)
                .fill(OnboardingTheme.surface)

            if isSelected {
                RoundedRectangle(cornerRadius: OnboardingTheme.cornerRadiusLarge, style: .continuous)
                    .fill(OnboardingTheme.accentGlow)
            }
        }
    }

    @ViewBuilder
    private var strokeOverlay: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: OnboardingTheme.cornerRadiusLarge, style: .continuous)
                .strokeBorder(OnboardingTheme.accentGradient, lineWidth: 1)
        } else {
            RoundedRectangle(cornerRadius: OnboardingTheme.cornerRadiusLarge, style: .continuous)
                .strokeBorder(OnboardingTheme.stroke, lineWidth: 1)
        }
    }

    private func fire() {
        UISelectionFeedbackGenerator().selectionChanged()
        onTap()
    }
}

#Preview {
    ZStack {
        OnboardingTheme.canvas.ignoresSafeArea()
        VStack(spacing: 12) {
            OnboardingOptionRow(title: "Build strength", icon: "bolt.fill", isSelected: true) {}
            OnboardingOptionRow(title: "Build muscle", icon: "figure.strengthtraining.traditional", isSelected: false) {}
            OnboardingOptionRow(title: "The Drill Sergeant", descriptor: "Blunt. Direct. Holds nothing back.", isSelected: true) {}
            OnboardingOptionRow(title: "Knees", icon: "figure.walk", isMultiSelect: true, isSelected: true) {}
        }
        .padding(24)
    }
}
