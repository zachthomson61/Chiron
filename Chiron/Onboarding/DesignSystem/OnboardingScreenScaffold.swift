//
//  OnboardingScreenScaffold.swift
//  Chiron
//
//  Shared page chrome: top bar, scrollable body, pinned CTA at the bottom safe area.
//  Every step is a thin wrapper around this scaffold so layout stays consistent.
//

import SwiftUI

/// Layout scaffold every onboarding step composes.
///
/// The scaffold owns the top bar, the body scroll view, and the pinned bottom CTA.
/// Steps only provide their own content and decide when the CTA is enabled.
struct OnboardingScreenScaffold<Content: View>: View {
    let title: String?
    let subtitle: String?
    let ctaTitle: String
    let ctaEnabled: Bool
    let onContinue: () -> Void
    let onBack: (() -> Void)?
    let currentStep: Int
    let totalSteps: Int
    let content: () -> Content

    /// Hides the top bar entirely. Used for the welcome and interstitial screens.
    var hideTopBar: Bool = false

    /// Hides the CTA. Used for the calculating loader.
    var hideCTA: Bool = false

    /// When `false`, the body is rendered in a plain `VStack` instead of a
    /// `ScrollView`. Use this for steps whose content doesn't overflow — e.g.
    /// the age wheel picker — so stray drags on empty space don't get swallowed
    /// by the scroll gesture recognizer.
    var scrollable: Bool = true

    init(
        title: String? = nil,
        subtitle: String? = nil,
        ctaTitle: String = "Continue",
        ctaEnabled: Bool = true,
        currentStep: Int,
        totalSteps: Int,
        onContinue: @escaping () -> Void,
        onBack: (() -> Void)? = nil,
        hideTopBar: Bool = false,
        hideCTA: Bool = false,
        scrollable: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.ctaTitle = ctaTitle
        self.ctaEnabled = ctaEnabled
        self.currentStep = currentStep
        self.totalSteps = totalSteps
        self.onContinue = onContinue
        self.onBack = onBack
        self.hideTopBar = hideTopBar
        self.hideCTA = hideCTA
        self.scrollable = scrollable
        self.content = content
    }

    /// Shared body content. Extracted so both the scrollable and non-scrollable
    /// branches render the exact same layout.
    @ViewBuilder
    private var bodyStack: some View {
        VStack(alignment: .leading, spacing: 24) {
            if title != nil || subtitle != nil {
                VStack(alignment: .leading, spacing: 10) {
                    if let title = title {
                        OnboardingTypography.questionTitle(title)
                    }
                    if let subtitle = subtitle {
                        OnboardingTypography.subtitle(subtitle)
                    }
                }
            }

            content()
        }
        .padding(.horizontal, OnboardingTheme.screenHorizontalPadding)
        .padding(.top, hideTopBar ? 0 : 8)
        .padding(.bottom, scrollable ? 120 : 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var body: some View {
        ZStack {
            OnboardingTheme.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                if !hideTopBar {
                    OnboardingTopBar(
                        currentStep: currentStep,
                        totalSteps: totalSteps,
                        canGoBack: onBack != nil,
                        onBack: { onBack?() }
                    )
                    .padding(.bottom, 24)
                }

                if scrollable {
                    ScrollView(showsIndicators: false) {
                        bodyStack
                    }
                } else {
                    bodyStack
                }

                Spacer(minLength: 0)
            }

            if !hideCTA {
                VStack(spacing: 0) {
                    Spacer()
                    // Render the CTA only once the screen's requirements are met.
                    // Hiding it (vs dimming) keeps the pre-selection state clean and
                    // gives the button a decisive "you've made a choice" reveal.
                    if ctaEnabled {
                        PrimaryCTAButton(
                            title: ctaTitle,
                            isEnabled: true,
                            action: onContinue
                        )
                        .padding(.horizontal, OnboardingTheme.screenHorizontalPadding)
                        .padding(.bottom, 8)
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .bottom)),
                                removal: .opacity
                            )
                        )
                    }
                }
                .animation(OnboardingTheme.selectionSpring, value: ctaEnabled)
            }
        }
    }
}
