//
//  TrainingProfileCard.swift
//  Chiron
//
//  Surfaces the onboarding-derived fields on the Profile tab and inside the
//  "Complete User Profile" sheet. We deliberately omit `topGoal` here because
//  the home tab's primary-goal card already owns that field — repeating it
//  would just duplicate UI.
//
//  The profile tab uses a richer multi-card layout (`TrainingProfileCard`);
//  the sheet uses a flat Form-rows presentation (`OnboardingSummaryListView`)
//  so it composes naturally with the rest of the form.
//
//  `TrainingProfileCard` takes a binding so the user can tweak weight, coach
//  persona, and coaching intensity inline. The hosting view is responsible
//  for persisting the new value (`UserDefaultsUserProfileStore.save`) and
//  refreshing the coaching manager.
//

import SwiftUI
import UIKit

// MARK: - Field model

/// Pure-data view of the onboarding fields exposed in the sheet's Form rows.
struct OnboardingProfileFields {
    struct Pair: Identifiable {
        let id = UUID()
        let label: String
        let value: String
    }

    let pairs: [Pair]

    init(profile: ChironUserProfile) {
        var p: [Pair] = []
        p.append(Pair(label: "Lifting experience", value: profile.experienceLevel.displayName))
        p.append(Pair(label: "Gender", value: profile.gender.displayName))
        p.append(Pair(label: "Birth year", value: "\(profile.birthYear)"))
        p.append(Pair(label: "Height", value: Self.formatHeight(cm: profile.heightCm, units: profile.preferredUnits)))
        p.append(Pair(label: "Weight", value: Self.formatWeight(kg: profile.weightKg, units: profile.preferredUnits)))

        if profile.hasInjuryConcerns, !profile.injuryFlags.isEmpty {
            let names = profile.injuryFlags.map { $0.displayName }.sorted().joined(separator: ", ")
            p.append(Pair(label: "Injury locations", value: names))
        } else {
            p.append(Pair(label: "Injury locations", value: "None reported"))
        }

        if profile.hasInjuryConcerns, let limitation = profile.movementLimitation {
            p.append(Pair(label: "Movement limitation", value: limitation.displayName))
        }

        if profile.hasInjuryConcerns, !profile.discomfortMovements.isEmpty {
            let names = profile.discomfortMovements.map { $0.displayName }.sorted().joined(separator: ", ")
            p.append(Pair(label: "Discomfort movements", value: names))
        }

        p.append(Pair(label: "Ideal coach", value: profile.coachPersona.displayName))
        p.append(Pair(label: "Coaching intensity", value: profile.coachIntensityLevel.label))

        self.pairs = p
    }

    static func formatHeight(cm: Double, units: UnitSystem) -> String {
        switch units {
        case .imperial:
            let totalInches = cm / 2.54
            let feet = Int(totalInches / 12)
            let inches = Int(totalInches.rounded()) - feet * 12
            return "\(feet)′ \(inches)″"
        case .metric:
            return "\(Int(cm.rounded())) cm"
        }
    }

    static func formatWeight(kg: Double, units: UnitSystem) -> String {
        switch units {
        case .imperial:
            let lbs = kg * 2.2046226218
            return "\(Int(lbs.rounded())) lbs"
        case .metric:
            return "\(Int(kg.rounded())) kg"
        }
    }
}

// MARK: - Form-style list (sheet)

struct OnboardingSummaryListView: View {
    let profile: ChironUserProfile

    var body: some View {
        let fields = OnboardingProfileFields(profile: profile)
        ForEach(fields.pairs) { pair in
            LabeledContent(pair.label, value: pair.value)
        }
    }
}

// MARK: - Card on the profile tab

struct TrainingProfileCard: View {
    @Binding var profile: ChironUserProfile

    @State private var showWeightEditor = false
    @State private var showCoachPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader

            statsTiles
            attributeChips
            coachCard

            if profile.hasInjuryConcerns {
                healthCard
            }
        }
        .sheet(isPresented: $showWeightEditor) {
            WeightEditSheet(weightKg: $profile.weightKg, units: profile.preferredUnits)
        }
        .sheet(isPresented: $showCoachPicker) {
            CoachPersonaEditSheet(persona: $profile.coachPersona)
        }
    }

    // MARK: Section header

    private var sectionHeader: some View {
        Text("Training Profile")
            .font(.headline)
            .foregroundColor(.textPrimary)
    }

    // MARK: Stat tiles

    private var statsTiles: some View {
        HStack(spacing: 10) {
            statTile(label: "Born", value: "\(profile.birthYear)", action: nil)
            statTile(
                label: "Height",
                value: OnboardingProfileFields.formatHeight(cm: profile.heightCm, units: profile.preferredUnits),
                action: nil
            )
            statTile(
                label: "Weight",
                value: OnboardingProfileFields.formatWeight(kg: profile.weightKg, units: profile.preferredUnits),
                action: { showWeightEditor = true }
            )
        }
    }

    @ViewBuilder
    private func statTile(label: String, value: String, action: (() -> Void)?) -> some View {
        let editable = action != nil

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.5)
                    .foregroundColor(.textSecondary)
                Spacer(minLength: 0)
                if editable {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.primaryPurple)
                }
            }
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(white: 0.15))
        )
        .overlay {
            if editable {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.primaryPurple.opacity(0.30), lineWidth: 1)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture {
            action?()
        }
    }

    // MARK: Experience + Gender chips

    private var attributeChips: some View {
        HStack(spacing: 10) {
            attributeChip(
                icon: profile.experienceLevel.iconName,
                title: profile.experienceLevel.displayName,
                subtitle: profile.experienceLevel.detail
            )
            attributeChip(
                icon: profile.gender.iconName,
                title: profile.gender.displayName,
                subtitle: nil
            )
        }
    }

    private func attributeChip(icon: String, title: String, subtitle: String?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primaryPurple)
                .frame(width: 30, height: 30)
                .background(Color.primaryPurple.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.textSecondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(white: 0.15))
        )
    }

    // MARK: Coach card (editable persona + interactive intensity slider)

    private var coachCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                showCoachPicker = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: Self.coachIcon(for: profile.coachPersona))
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.primaryPurple)
                        .frame(width: 44, height: 44)
                        .background(Color.primaryPurple.opacity(0.15))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text("YOUR COACH")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.5)
                            .foregroundColor(.textSecondary)
                        Text(profile.coachPersona.displayName)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.textPrimary)
                    }
                    Spacer()
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primaryPurple)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(profile.coachPersona.descriptor)
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            intensityControl
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(white: 0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.primaryPurple.opacity(0.30), lineWidth: 1)
        )
    }

    /// Slider replaces the static 5-bar meter. Title sits centered above the
    /// track; "Whisper" / "Relentless" anchor the ends; the current level name
    /// sits centered between them so the user always sees the named rung.
    private var intensityControl: some View {
        VStack(spacing: 10) {
            Text("Intensity")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.textSecondary)
                .frame(maxWidth: .infinity)

            IntensitySlider(level: $profile.coachIntensity)

            ZStack {
                // End labels live in their own HStack so Whisper hugs the
                // leading edge and Relentless the trailing edge.
                HStack {
                    Text("Whisper")
                        .font(.system(size: 11, weight: profile.coachIntensity == 1 ? .semibold : .regular))
                        .foregroundColor(profile.coachIntensity == 1 ? .primaryPurple : Color(white: 0.45))
                    Spacer()
                    Text("Relentless")
                        .font(.system(size: 11, weight: profile.coachIntensity == 5 ? .semibold : .regular))
                        .foregroundColor(profile.coachIntensity == 5 ? .primaryPurple : Color(white: 0.45))
                }

                // Centered overlay — geometrically dead-center, regardless of
                // the asymmetric widths of "Whisper" vs "Relentless".
                Text(profile.coachIntensityLevel.label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primaryPurple)
            }
        }
    }

    private static func coachIcon(for persona: CoachPersona) -> String {
        switch persona {
        case .drillSergeant: return "flag.fill"
        case .technician:    return "wrench.and.screwdriver.fill"
        case .hypeFriend:    return "hands.clap.fill"
        case .quietPro:      return "moon.stars.fill"
        }
    }

    // MARK: Health card (only when injury concerns present)

    private var healthCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "cross.case.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primaryPurple)
                Text("HEALTH NOTES")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.5)
                    .foregroundColor(.textSecondary)
            }

            if !profile.injuryFlags.isEmpty {
                healthRow(label: "Locations") {
                    ChipFlow(items: sortedNames(profile.injuryFlags))
                }
            }

            if let limitation = profile.movementLimitation {
                healthRow(label: "Limitation") {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Self.severityColor(for: limitation))
                            .frame(width: 8, height: 8)
                        Text(limitation.displayName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.textPrimary)
                    }
                }
            }

            if !profile.discomfortMovements.isEmpty {
                healthRow(label: "Discomfort") {
                    ChipFlow(items: sortedNames(profile.discomfortMovements))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(white: 0.15))
        )
    }

    private func healthRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.textSecondary)
            content()
        }
    }

    private func sortedNames<S: Sequence>(_ items: S) -> [String] where S.Element: DisplayNamed {
        items.map(\.displayName).sorted()
    }

    private static func severityColor(for limitation: MovementLimitation) -> Color {
        switch limitation {
        case .noLimitation:        return .green
        case .mildDiscomfort:      return Color(red: 1.0, green: 0.84, blue: 0.0)
        case .moderateLimitation:  return .orange
        case .severe:              return .red
        }
    }
}

// MARK: - DisplayNamed bridge

/// Lightweight protocol so the health card's chip helper can pull
/// `displayName` off either `InjuryArea` or `DiscomfortMovement` without
/// an enum-specific switch.
protocol DisplayNamed {
    var displayName: String { get }
}

extension InjuryArea: DisplayNamed {}
extension DiscomfortMovement: DisplayNamed {}

// MARK: - Intensity slider

/// Live, draggable purple slider. Updates the bound integer (1...5) only on
/// drag end so we don't thrash the persistence layer with intermediate values.
/// During the drag the thumb tracks the finger, and a haptic fires whenever
/// the snapped step changes for tactile feedback.
struct IntensitySlider: View {
    @Binding var level: Int

    @State private var dragValue: Double = 3
    @State private var isDragging: Bool = false
    @State private var lastHapticStep: Int = 3

    var body: some View {
        GeometryReader { proxy in
            let trackHeight: CGFloat = 8
            let thumbSize: CGFloat = 22
            let usableWidth = max(0, proxy.size.width - thumbSize)
            let displayValue = isDragging ? dragValue : Double(level)
            let normalized = max(0, min(1, (displayValue - 1.0) / 4.0))
            let thumbX = CGFloat(normalized) * usableWidth

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.10))
                    .frame(height: trackHeight)

                Capsule()
                    .fill(Color.primaryPurple)
                    .frame(width: thumbX + thumbSize / 2, height: trackHeight)

                // Tick marks for the five rungs.
                HStack(spacing: 0) {
                    ForEach(0..<5) { index in
                        Circle()
                            .fill(Color.white.opacity(0.30))
                            .frame(width: 4, height: 4)
                        if index < 4 { Spacer() }
                    }
                }
                .frame(width: usableWidth)
                .offset(x: thumbSize / 2)

                Circle()
                    .fill(Color.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: Color.black.opacity(0.4), radius: 4, y: 2)
                    .offset(x: thumbX)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            dragValue = Double(level)
                            lastHapticStep = level
                        }
                        let clamped = min(max(value.location.x - thumbSize / 2, 0), usableWidth)
                        let pct = usableWidth > 0 ? Double(clamped / usableWidth) : 0
                        dragValue = 1.0 + pct * 4.0
                        let step = max(1, min(5, Int(dragValue.rounded())))
                        if step != lastHapticStep {
                            lastHapticStep = step
                            Haptics.selection()
                        }
                    }
                    .onEnded { _ in
                        let snapped = max(1, min(5, Int(dragValue.rounded())))
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                            level = snapped
                            isDragging = false
                        }
                    }
            )
        }
        .frame(height: 22)
    }
}

// MARK: - Chip flow layout

/// Wrapping HStack for variable-width chips. Custom Layout keeps each chip at
/// its intrinsic size and breaks rows when the next chip would overflow.
struct ChipFlow: View {
    let items: [String]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(Color.white.opacity(0.10))
                    )
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var width: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                width = max(width, x - spacing)
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        width = max(width, x - spacing)
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.minX + maxWidth, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Editor sheets

/// Wheel-picker sheet for updating weight in the user's current units. Saves
/// to the bound `weightKg` and also writes through to `UserManager`'s cached
/// bodyweight (used by bodyweight-exercise volume calculations).
struct WeightEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var weightKg: Double
    let units: UnitSystem

    @State private var pounds: Int = 175
    @State private var kg: Int = 80

    var body: some View {
        ZStack(alignment: .topTrailing) {
            OnboardingTheme.canvas.ignoresSafeArea()

            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    OnboardingTypography.questionTitle("Update your weight")
                    OnboardingTypography.subtitle("Used to scale baseline volume recommendations.")
                }
                .padding(.horizontal, OnboardingTheme.screenHorizontalPadding)
                .padding(.top, 56)
                .frame(maxWidth: .infinity, alignment: .leading)

                Group {
                    if units == .imperial {
                        Picker("Weight (lbs)", selection: $pounds) {
                            ForEach(60...500, id: \.self) { value in
                                Text("\(value) lbs").tag(value)
                            }
                        }
                    } else {
                        Picker("Weight (kg)", selection: $kg) {
                            ForEach(30...250, id: \.self) { value in
                                Text("\(value) kg").tag(value)
                            }
                        }
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxHeight: 220)
                .padding(.horizontal, OnboardingTheme.screenHorizontalPadding)

                Spacer()

                PrimaryCTAButton(title: "Save") {
                    let newKg: Double = units == .imperial
                        ? Double(pounds) / 2.2046226218
                        : Double(kg)
                    weightKg = newKg
                    let lbs = units == .imperial ? Double(pounds) : newKg * 2.2046226218
                    UserManager.shared.setCurrentBodyweight(lbs)
                    dismiss()
                }
                .padding(.horizontal, OnboardingTheme.screenHorizontalPadding)
                .padding(.bottom, 16)
            }

            sheetCloseButton { dismiss() }
                .padding(.trailing, 16)
                .padding(.top, 12)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            pounds = max(60, min(500, Int((weightKg * 2.2046226218).rounded())))
            kg = max(30, min(250, Int(weightKg.rounded())))
        }
    }
}

/// Persona picker. Tapping a row commits immediately (matches the onboarding
/// pattern); the Done button just dismisses.
struct CoachPersonaEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var persona: CoachPersona

    var body: some View {
        ZStack(alignment: .topTrailing) {
            OnboardingTheme.canvas.ignoresSafeArea()

            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    OnboardingTypography.questionTitle("Choose your coach")
                    OnboardingTypography.subtitle("This sets the tone your coach uses during sets.")
                }
                .padding(.horizontal, OnboardingTheme.screenHorizontalPadding)
                .padding(.top, 56)
                .frame(maxWidth: .infinity, alignment: .leading)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        ForEach(CoachPersona.allCases) { p in
                            OnboardingOptionRow(
                                title: p.displayName,
                                descriptor: p.descriptor,
                                isSelected: persona == p
                            ) {
                                persona = p
                            }
                        }
                    }
                    .padding(.horizontal, OnboardingTheme.screenHorizontalPadding)
                }

                PrimaryCTAButton(title: "Done") {
                    dismiss()
                }
                .padding(.horizontal, OnboardingTheme.screenHorizontalPadding)
                .padding(.bottom, 16)
            }

            sheetCloseButton { dismiss() }
                .padding(.trailing, 16)
                .padding(.top, 12)
        }
        .preferredColorScheme(.dark)
    }
}

/// Reusable xmark close pill matching the onboarding-themed sheets.
@ViewBuilder
private func sheetCloseButton(action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Image(systemName: "xmark")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(OnboardingTheme.textPrimary)
            .frame(width: 36, height: 36)
            .background(Circle().fill(OnboardingTheme.surface))
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Close")
}
