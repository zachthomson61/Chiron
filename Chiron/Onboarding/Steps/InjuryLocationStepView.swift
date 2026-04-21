//
//  InjuryLocationStepView.swift
//  Chiron
//
//  Step 6b — shown only when the user answered "Yes" on the gate.
//
//  Custom anatomical silhouette with connector lines to label pills on either side.
//  The lower-back arrow is drawn UNDER the body fill so it appears to disappear
//  behind the figure — visual shorthand for "rear side." The "Other" option row
//  replaces its own label with an inline TextField when selected.
//

import SwiftUI

struct InjuryLocationStepView: View {
    @Bindable var coordinator: ChironOnboardingCoordinator

    @FocusState private var otherFieldFocused: Bool

    /// Anatomical target points expressed as fractions of the body frame.
    private struct LabelPlacement {
        let area: InjuryArea
        let side: HorizontalEdge
        /// Fractional y on the figure; 0 = top of head, 1 = feet.
        let bodyY: CGFloat
        /// If true, the connector terminates inside the torso so the body fill
        /// hides the end of the line — reads as "behind the figure."
        var behindBody: Bool = false
    }

    /// Placements tuned to the male anatomy asset. y-fractions are measured
    /// against the body image (0 = top of head, 1 = feet).
    private static let malePlacements: [LabelPlacement] = [
        .init(area: .neck,       side: .leading,  bodyY: 0.16),
        .init(area: .shoulder,   side: .trailing, bodyY: 0.20),
        .init(area: .elbow,      side: .trailing, bodyY: 0.36),
        .init(area: .lowerBack,  side: .leading,  bodyY: 0.42, behindBody: true),
        .init(area: .hip,        side: .leading,  bodyY: 0.54),
        .init(area: .wrist,      side: .trailing, bodyY: 0.56),
        .init(area: .knee,       side: .trailing, bodyY: 0.74),
        .init(area: .ankle,      side: .leading,  bodyY: 0.95),
    ]

    /// Placements tuned to the female anatomy asset. The female figure has a
    /// slightly longer neck, narrower shoulders, longer torso, and higher-set
    /// hips — the y-fractions shift to match.
    private static let femalePlacements: [LabelPlacement] = [
        .init(area: .neck,       side: .leading,  bodyY: 0.15),
        .init(area: .shoulder,   side: .trailing, bodyY: 0.22),
        .init(area: .elbow,      side: .trailing, bodyY: 0.38),
        .init(area: .lowerBack,  side: .leading,  bodyY: 0.44, behindBody: true),
        .init(area: .hip,        side: .leading,  bodyY: 0.56),
        .init(area: .wrist,      side: .trailing, bodyY: 0.58),
        .init(area: .knee,       side: .trailing, bodyY: 0.75),
        .init(area: .ankle,      side: .leading,  bodyY: 0.96),
    ]

    /// Placements for the current user — female figure uses its own tuning,
    /// everything else (male / non-binary / prefer-not-to-say) uses the male.
    private var placements: [LabelPlacement] {
        coordinator.draft.gender == .female
            ? Self.femalePlacements
            : Self.malePlacements
    }

    private var ctaEnabled: Bool {
        let flags = coordinator.draft.injuryFlags
        guard !flags.isEmpty else { return false }
        if flags.contains(.other) {
            return !coordinator.draft.injuryOtherDescription
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    var body: some View {
        OnboardingScreenScaffold(
            title: "Where's the issue?",
            subtitle: "Tap each area that applies. We'll filter cues accordingly.",
            ctaTitle: "Continue",
            ctaEnabled: ctaEnabled,
            currentStep: coordinator.progressStepIndex,
            totalSteps: coordinator.totalProgressSteps,
            onContinue: { coordinator.advance() },
            onBack: { coordinator.goBack() }
        ) {
            // Wrap the content in a ScrollViewReader so we can drive an explicit
            // scroll-to-other when the text field gets focus. The scaffold's
            // outer ScrollView is the scroll target, and ScrollViewReader walks
            // the hierarchy to find it.
            ScrollViewReader { proxy in
                VStack(spacing: 24) {
                    bodyDiagram
                        .frame(height: 460)

                    otherRow
                        .id(Self.otherRowAnchor)
                }
                .onChange(of: otherFieldFocused) { _, focused in
                    guard focused else { return }
                    // Small delay so the keyboard has a chance to start
                    // animating up — scrolling while the scroll frame is mid-
                    // shrink gives a smoother landing.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        withAnimation(.easeOut(duration: 0.25)) {
                            // Anchor y 0.72 (not 1.0) leaves clearance at the
                            // bottom of the visible area for the pinned
                            // Continue button, so the text input the user just
                            // tapped sits comfortably above the CTA instead
                            // of being hidden by it.
                            proxy.scrollTo(
                                Self.otherRowAnchor,
                                anchor: UnitPoint(x: 0.5, y: 0.72)
                            )
                        }
                    }
                }
            }
        }
    }

    /// Identifier used by the ScrollViewReader to position the Other row above
    /// the keyboard when it gains focus.
    private static let otherRowAnchor = "injuryOtherRow"

    // MARK: - Body Diagram

    /// The figure column is narrower than the full diagram width to leave room for
    /// label pills on either side. Connector lines and labels render around it.
    private var bodyDiagram: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height

            // Match the asset aspect ratio so the figure fills its box exactly —
            // no whitespace on the sides that would throw off arrow endpoints.
            // Both the male (482×1099) and female (498×1109) images are ≈0.45.
            //
            // 0.88 height factor (vs 0.98) pulls the body in from the sides so
            // the label pills sit fully *outside* the image rect. The lowerBack
            // "behind the body" line needs that outside gap to show anything —
            // once the pill overlaps the image, the entire behind line is
            // covered and the arrow vanishes.
            let figureAspectRatio: CGFloat = 0.45
            let bodyHeight = h * 0.88
            let bodyWidth = bodyHeight * figureAspectRatio
            let bodyRect = CGRect(
                x: (w - bodyWidth) / 2,
                y: h * 0.01,
                width: bodyWidth,
                height: bodyHeight
            )

            ZStack {
                // Layer 1: "Behind-the-body" lines (just the lowerBack arrow).
                // These are drawn below the image so the image visually covers
                // the portion of the line that enters the torso — the "arrow
                // disappears behind the figure" effect.
                connectorCanvas(
                    size: proxy.size,
                    bodyRect: bodyRect,
                    includeBehind: true
                )

                // Layer 2: Anatomical figure. The asset is opaque, so anything
                // beneath it inside `bodyRect` is hidden.
                Image(anatomyAssetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: bodyRect.width, height: bodyRect.height)
                    .position(x: bodyRect.midX, y: bodyRect.midY)

                // Layer 3: All other connector lines, drawn ABOVE the body
                // image so they're visible all the way to their anchor on the
                // figure silhouette.
                connectorCanvas(
                    size: proxy.size,
                    bodyRect: bodyRect,
                    includeBehind: false
                )

                // Layer 4: Dots and labels on top.
                ForEach(placements, id: \.area) { placement in
                    dotAndLabel(for: placement, in: proxy.size, bodyRect: bodyRect)
                }
            }
        }
    }

    /// Draws connector lines into a Canvas so coordinates stay absolute.
    /// - `includeBehind == true`: draws only the `behindBody` placements (this
    ///   canvas gets layered below the figure image).
    /// - `includeBehind == false`: draws only the non-`behindBody` placements
    ///   (this canvas gets layered above the figure image).
    ///
    /// All geometry in this Canvas is derived from two gender-aware sources:
    /// `placements` (which resolves to `malePlacements` or `femalePlacements`
    /// based on the user's selection) and `bodySilhouetteEdgeOffset` (which
    /// delegates to `maleEdgeOffset` or `femaleEdgeOffset`). The Canvas
    /// closure re-evaluates whenever `coordinator.draft.gender` changes, so
    /// the arrows always match whichever anatomy image is on screen.
    @ViewBuilder
    private func connectorCanvas(
        size: CGSize,
        bodyRect: CGRect,
        includeBehind: Bool
    ) -> some View {
        // Snapshot the current gender up front so the Canvas closure visibly
        // depends on it — this guarantees Canvas is re-drawn when the user's
        // gender selection changes (e.g. if they go back and pick differently).
        let currentGender = coordinator.draft.gender
        let activePlacements = placements

        Canvas { context, _ in
            for placement in activePlacements where placement.behindBody == includeBehind {
                let isSelected = coordinator.draft.injuryFlags.contains(placement.area)
                let y = bodyRect.minY + bodyRect.height * placement.bodyY
                let startX = labelInnerX(for: placement, width: size.width)
                let endPoint = bodyAnchor(for: placement, bodyRect: bodyRect)

                var path = Path()
                path.move(to: CGPoint(x: startX, y: y))
                path.addLine(to: endPoint)

                let stroke = StrokeStyle(
                    lineWidth: isSelected ? 2 : 1.25,
                    lineCap: .round,
                    dash: isSelected ? [] : [3, 3]
                )

                if isSelected {
                    context.stroke(
                        path,
                        with: .linearGradient(
                            Gradient(colors: [OnboardingTheme.accentStart, OnboardingTheme.accentEnd]),
                            startPoint: CGPoint(x: startX, y: y),
                            endPoint: endPoint
                        ),
                        style: stroke
                    )
                } else {
                    // `OnboardingTheme.stroke` is tuned for the 1pt borders on
                    // option rows, where it sits on `surface` (#1A1A1D) and
                    // reads fine. On the canvas background (#0E0E10) it's
                    // nearly invisible, so connector lines use a brighter tone.
                    context.stroke(
                        path,
                        with: .color(OnboardingTheme.textSecondary.opacity(0.55)),
                        style: stroke
                    )
                }
            }
        }
        // Giving the Canvas an id tied to the gender forces a fresh render
        // when gender changes, even if SwiftUI's diffing would otherwise
        // reuse the previous Canvas node.
        .id("connectorCanvas-\(includeBehind)-\(currentGender?.rawValue ?? "none")")
        .frame(width: size.width, height: size.height)
        .animation(
            OnboardingTheme.selectionSpring,
            value: coordinator.draft.injuryFlags
        )
    }

    /// Female for `.female`, male asset for everything else (male, non-binary,
    /// prefer-not-to-say). Falls back to male if no gender is set (shouldn't
    /// happen in the live flow — the gender step gates this one — but keeps
    /// previews usable).
    private var anatomyAssetName: String {
        coordinator.draft.gender?.anatomyAssetName ?? "AnatomyMale"
    }

    // MARK: - Connector geometry

    /// Anchor point on the body where the connector meets the silhouette.
    private func bodyAnchor(
        for placement: LabelPlacement,
        bodyRect: CGRect
    ) -> CGPoint {
        let y = bodyRect.minY + bodyRect.height * placement.bodyY

        if placement.behindBody {
            // Terminate in the middle of the torso so the body fill covers the tail.
            return CGPoint(x: bodyRect.midX, y: y)
        }

        // Approximate x along the silhouette's outline at the given y.
        // Fractions reflect the AnatomyFigure path's widest point at each band.
        let edgeOffset = bodySilhouetteEdgeOffset(forY: placement.bodyY) * bodyRect.width
        switch placement.side {
        case .leading:  return CGPoint(x: bodyRect.midX - edgeOffset, y: y)
        case .trailing: return CGPoint(x: bodyRect.midX + edgeOffset, y: y)
        }
    }

    /// Horizontal half-width of the silhouette at a given y fraction, expressed
    /// as a fraction of `bodyRect.width` (0.5 = outer edge of the PNG).
    /// The anatomy PNGs have ~12% padding on each side of the figure, so these
    /// values stop inside that edge — where the actual silhouette lives.
    ///
    /// The male and female figures have different proportions (shoulder width,
    /// hip width, waist), so the table branches on the user's gender.
    private func bodySilhouetteEdgeOffset(forY y: CGFloat) -> CGFloat {
        coordinator.draft.gender == .female
            ? femaleEdgeOffset(forY: y)
            : maleEdgeOffset(forY: y)
    }

    private func maleEdgeOffset(forY y: CGFloat) -> CGFloat {
        switch y {
        case 0..<0.10:       return 0.10   // head
        case 0.10..<0.18:    return 0.07   // neck
        case 0.18..<0.24:    return 0.40   // deltoid cap — widest point
        case 0.24..<0.36:    return 0.32   // upper arm / biceps
        case 0.36..<0.45:    return 0.34   // elbow
        case 0.45..<0.52:    return 0.34   // forearm
        case 0.52..<0.58:    return 0.34   // wrist / hand
        case 0.58..<0.64:    return 0.18   // hip
        case 0.64..<0.70:    return 0.17   // upper thigh
        case 0.70..<0.78:    return 0.13   // knee
        case 0.78..<0.90:    return 0.11   // calf
        default:             return 0.08   // ankle / foot
        }
    }

    private func femaleEdgeOffset(forY y: CGFloat) -> CGFloat {
        switch y {
        case 0..<0.10:       return 0.10   // head
        case 0.10..<0.18:    return 0.07   // neck
        case 0.18..<0.26:    return 0.34   // shoulder — narrower than male
        case 0.26..<0.38:    return 0.28   // upper arm
        case 0.38..<0.46:    return 0.30   // elbow
        case 0.46..<0.54:    return 0.31   // forearm
        case 0.54..<0.60:    return 0.31   // wrist / hand
        case 0.60..<0.66:    return 0.22   // hip — wider than male
        case 0.66..<0.72:    return 0.20   // upper thigh
        case 0.72..<0.80:    return 0.14   // knee
        case 0.80..<0.92:    return 0.12   // calf
        default:             return 0.08   // ankle / foot
        }
    }

    private func labelX(for placement: LabelPlacement, width: CGFloat) -> CGFloat {
        switch placement.side {
        case .leading:  return width * 0.12
        case .trailing: return width * 0.88
        }
    }

    /// Inner edge of the label pill — where the connector originates. Keep the
    /// constant in sync with the `.frame(width:)` on `labelPill`.
    private func labelInnerX(for placement: LabelPlacement, width: CGFloat) -> CGFloat {
        let center = labelX(for: placement, width: width)
        let halfPillWidth: CGFloat = 48   // matches labelPill .frame(width: 96)
        return placement.side == .leading ? center + halfPillWidth : center - halfPillWidth
    }

    @ViewBuilder
    private func dotAndLabel(
        for placement: LabelPlacement,
        in size: CGSize,
        bodyRect: CGRect
    ) -> some View {
        let isSelected = coordinator.draft.injuryFlags.contains(placement.area)
        let y = bodyRect.minY + bodyRect.height * placement.bodyY
        let endPoint = bodyAnchor(for: placement, bodyRect: bodyRect)

        // Only draw a visible dot for outward-pointing arrows. The behind-body
        // placement intentionally has no terminator — it's swallowed by the figure.
        if !placement.behindBody {
            Circle()
                .fill(isSelected ? AnyShapeStyle(OnboardingTheme.accentGradient) : AnyShapeStyle(OnboardingTheme.textSecondary))
                .frame(width: 6, height: 6)
                .position(endPoint)
        }

        labelPill(for: placement.area, isSelected: isSelected)
            .position(x: labelX(for: placement, width: size.width), y: y)
    }

    @ViewBuilder
    private func labelPill(for area: InjuryArea, isSelected: Bool) -> some View {
        Button {
            toggle(area)
        } label: {
            Text(area.displayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? Color.white : OnboardingTheme.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(width: 96)
                .background(
                    ZStack {
                        Capsule().fill(OnboardingTheme.surface)
                        if isSelected {
                            Capsule().fill(OnboardingTheme.accentGlow)
                        }
                    }
                )
                .overlay(
                    Capsule()
                        .strokeBorder(
                            isSelected
                            ? AnyShapeStyle(OnboardingTheme.accentGradient)
                            : AnyShapeStyle(OnboardingTheme.stroke),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .animation(OnboardingTheme.selectionSpring, value: isSelected)
    }

    // MARK: - "Other" option row (inline text field replacement)

    /// When unselected, looks like any other option row. When selected, the row's
    /// title is replaced in place by a TextField with a flashing cursor.
    ///
    /// Split into two independent tap targets: the selection mark on the left
    /// always toggles the flag (so the user can turn Other off even while the
    /// text field has focus), and the remaining area activates the row or
    /// edits the text depending on state.
    @ViewBuilder
    private var otherRow: some View {
        let isSelected = coordinator.draft.injuryFlags.contains(.other)

        HStack(spacing: 16) {
            // Dedicated tap target for toggling. Lives outside the text-field
            // area so it always receives taps — even when the TextField has
            // first-responder status.
            Button(action: handleSelectionMarkTap) {
                selectionMark(isSelected: isSelected)
            }
            .buttonStyle(.plain)

            Image(systemName: "pencil.and.outline")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(
                    isSelected
                    ? AnyShapeStyle(OnboardingTheme.accentGradient)
                    : AnyShapeStyle(OnboardingTheme.textSecondary)
                )
                .frame(width: 24)

            if isSelected {
                inlineTextField
            } else {
                // Tapping the rest of the row while unselected activates and
                // immediately focuses the field (brings up the keyboard).
                Button(action: activateAndFocus) {
                    HStack {
                        Text(InjuryArea.other.displayName)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(OnboardingTheme.textPrimary)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: OnboardingTheme.optionRowHeight)
        .frame(maxWidth: .infinity)
        .background(rowBackground(isSelected: isSelected))
        .overlay(rowStroke(isSelected: isSelected))
        .animation(OnboardingTheme.selectionSpring, value: isSelected)
    }

    private func handleSelectionMarkTap() {
        let wasSelected = coordinator.draft.injuryFlags.contains(.other)
        toggle(.other)
        if !wasSelected {
            // We just turned it on — pop the keyboard.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                otherFieldFocused = true
            }
        } else {
            // We just turned it off — dismiss the keyboard.
            otherFieldFocused = false
        }
    }

    private func activateAndFocus() {
        toggle(.other)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            otherFieldFocused = true
        }
    }

    private var inlineTextField: some View {
        TextField(
            "",
            text: Binding(
                get: { coordinator.draft.injuryOtherDescription },
                set: { coordinator.draft.injuryOtherDescription = $0 }
            ),
            prompt: Text("Describe the area/injury")
                .foregroundStyle(OnboardingTheme.textTertiary)
        )
        .font(.system(size: 17, weight: .medium))
        .foregroundStyle(OnboardingTheme.textPrimary)
        .tint(OnboardingTheme.accentStart)
        .focused($otherFieldFocused)
        .submitLabel(.done)
        .textInputAutocapitalization(.sentences)
        .autocorrectionDisabled(false)
    }

    @ViewBuilder
    private func selectionMark(isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .stroke(isSelected ? Color.clear : OnboardingTheme.stroke, lineWidth: 1.5)
                .frame(width: 22, height: 22)

            if isSelected {
                Circle()
                    .fill(OnboardingTheme.accentGradient)
                    .frame(width: 22, height: 22)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.white)
            }
        }
        .frame(width: 22, height: 22)
    }

    @ViewBuilder
    private func rowBackground(isSelected: Bool) -> some View {
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
    private func rowStroke(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: OnboardingTheme.cornerRadiusLarge, style: .continuous)
            .strokeBorder(
                isSelected
                ? AnyShapeStyle(OnboardingTheme.accentGradient)
                : AnyShapeStyle(OnboardingTheme.stroke),
                lineWidth: 1
            )
    }

    // MARK: - Selection

    private func toggle(_ area: InjuryArea) {
        var flags = coordinator.draft.injuryFlags
        if flags.contains(area) {
            flags.remove(area)
            if area == .other {
                coordinator.draft.injuryOtherDescription = ""
                otherFieldFocused = false
            }
        } else {
            flags.insert(area)
        }
        coordinator.draft.injuryFlags = flags
    }
}


// MARK: - Helpers

private enum HorizontalEdge {
    case leading, trailing
}

#Preview("Male — empty") {
    let coordinator: ChironOnboardingCoordinator = {
        let c = ChironOnboardingCoordinator(store: InMemoryUserProfileStore())
        c.draft.gender = .male
        c.draft.hasInjuryConcerns = true
        return c
    }()
    InjuryLocationStepView(coordinator: coordinator)
}

#Preview("Male — selections") {
    let coordinator: ChironOnboardingCoordinator = {
        let c = ChironOnboardingCoordinator(store: InMemoryUserProfileStore())
        c.draft.gender = .male
        c.draft.hasInjuryConcerns = true
        c.draft.injuryFlags = [.knee, .lowerBack, .shoulder]
        return c
    }()
    InjuryLocationStepView(coordinator: coordinator)
}

#Preview("Female — selections") {
    let coordinator: ChironOnboardingCoordinator = {
        let c = ChironOnboardingCoordinator(store: InMemoryUserProfileStore())
        c.draft.gender = .female
        c.draft.hasInjuryConcerns = true
        c.draft.injuryFlags = [.hip, .wrist]
        return c
    }()
    InjuryLocationStepView(coordinator: coordinator)
}

#Preview("Other with text") {
    let coordinator: ChironOnboardingCoordinator = {
        let c = ChironOnboardingCoordinator(store: InMemoryUserProfileStore())
        c.draft.gender = .male
        c.draft.hasInjuryConcerns = true
        c.draft.injuryFlags = [.other]
        c.draft.injuryOtherDescription = "Right elbow tendinitis"
        return c
    }()
    InjuryLocationStepView(coordinator: coordinator)
}
