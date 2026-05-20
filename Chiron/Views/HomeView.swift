import SwiftUI

struct HomeScreenSpacing {
    static let topInset: CGFloat = 12
    static let topTitlePad: CGFloat = 24
    static let headerStackSpacing: CGFloat = 18
    static let sectionSpacing: CGFloat = 28
    static let bottomInset: CGFloat = 28
}

/// Landing surface for the Home tab.
///
/// Tapping "Start Training" invokes the `onStartWorkout` closure supplied by
/// `RootTabView`, which switches the tab bar over to the Track tab.
struct HomeView: View {
    var onStartWorkout: (() -> Void)? = nil
    @StateObject private var preferencesManager = UserPreferencesManager.shared
    @State private var showGoalSelector = false
    @State private var contentHeight: CGFloat = 0
    @State private var pulseGoal = false
    /// Drives the header animation so we can animate shadow and offset without
    /// triggering extra layout changes.
    @State private var animateTitle = false
    
    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let h = proxy.size.height
                let goalDisplayName = preferencesManager.primaryGoal?.displayName ?? "Choose one"
                let goalIsSet = preferencesManager.primaryGoal != nil
                let shouldShowGoalHint = !goalIsSet && !UserDefaults.standard.bool(forKey: "has_shown_goal_hint")
                
                ScrollView {
                    VStack(spacing: 0) {
                    VStack(spacing: HomeScreenSpacing.sectionSpacing) {
                        // HEADER
                        VStack(alignment: .leading, spacing: HomeScreenSpacing.headerStackSpacing) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("LET'S GET IT!")
                                    .font(.neueMontrealBold(size: 38))
                                    .foregroundColor(.textPrimary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                    .fixedSize()
                                    .padding(.trailing, 24)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .shadow(color: Color.primaryPurple.opacity(animateTitle ? 0.65 : 0.3),
                                            radius: animateTitle ? 26 : 10,
                                            y: animateTitle ? 6 : 0)
                                    .rotationEffect(.degrees(animateTitle ? 1.75 : -1.75))
                                    .offset(x: animateTitle ? 3 : -3)
                                    .scaleEffect(animateTitle ? 1.03 : 1.0)
                                    .allowsTightening(true)
                                    .animation(
                                        Animation.easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                                        value: animateTitle
                                    )
                            }

                            MyGoalCard(
                                goalName: goalDisplayName,
                                isGoalSet: goalIsSet,
                                pulse: pulseGoal,
                                showHint: shouldShowGoalHint,
                                onTap: { showGoalSelector = true },
                                onHintAppear: handleGoalHintAppear
                            )
                        }
                        .padding(.top, HomeScreenSpacing.topTitlePad)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onAppear(perform: startTitleAnimationIfNeeded)
                        .onDisappear(perform: resetTitleAnimation)

                        // CORE
                        VStack(spacing: HomeScreenSpacing.sectionSpacing) {
                            // Ready to train section
                            VStack(spacing: 8) {
                                Text("Ready to train?")
                                    .font(.neueMontrealBold(size: 22))
                                    .foregroundColor(.textPrimary)
                            }

                            // Primary action — jumps to the Track tab so the
                            // session mounts inside the shared tab bar.
                            Button(action: handleStartWorkout) {
                                HStack(spacing: 8) {
                                    Image(systemName: "play.fill")
                                        .font(.neueMontrealSemiBold(size: 17))
                                    Text("Start Training")
                                        .font(.neueMontrealSemiBold(size: 17))
                                }
                                .foregroundColor(.textPrimary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(Color.primaryPurple)
                                .cornerRadius(28)
                            }
                        }

                        // Top three exercises ranked by the biggest recent
                        // improvement (slope change at the latest point).
                        // Self-loading — fetches all set logs once on appear
                        // and computes rankings client-side.
                        RecentProgressSection()
                    }
                    .padding(.horizontal, 20)
                    .background(
                        ViewHeightReader(height: $contentHeight)
                    )

                        // FLEX SPACER (shrinks/grows to balance)
                        Spacer()
                            .frame(height: max(0, min(40, h - contentHeight)))
                            .fixedSize()
                    }
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .scrollDisabled(contentHeight <= h)
                .dottedTabBackground()
            }
            .safeAreaInset(edge: .top) { 
                Color.clear.frame(height: HomeScreenSpacing.topInset) 
            }
            .preferredColorScheme(.dark)
            .sheet(isPresented: $showGoalSelector) {
                GoalSelectorView(preferencesManager: preferencesManager, isPresented: $showGoalSelector)
            }
        }
    }
}

private extension HomeView {
    /// "Start Training" hands control back to `RootTabView`, which switches
    /// to the Track tab so the camera session mounts inside the shared
    /// tab bar rather than a modal sheet.
    func handleStartWorkout() {
        onStartWorkout?()
    }

    func handleGoalHintAppear() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            pulseGoal = true
        }
        AnalyticsManager.shared.trackFirstRunGoalPrompt()
    }

    func startTitleAnimationIfNeeded() {
        guard !animateTitle else { return }
        animateTitle = true
    }

    func resetTitleAnimation() {
        animateTitle = false
    }
}


// Reads the rendered height of its parent and writes it to the binding.
// Uses `.onChange` rather than a `PreferenceKey` because the title's
// continuously-repeating animation re-runs the layout pass each frame,
// and preference writes inside that pass trip SwiftUI's "Bound preference
// tried to update multiple times per frame" warning. `.onChange` updates
// state via the normal mutation pipeline, which is debounced.
struct ViewHeightReader: View {
    @Binding var height: CGFloat
    var body: some View {
        GeometryReader { gp in
            Color.clear
                .onAppear { commit(gp.size.height) }
                .onChange(of: gp.size.height) { _, newValue in
                    commit(newValue)
                }
        }
    }

    private func commit(_ newValue: CGFloat) {
        guard newValue.isFinite, abs(newValue - height) > 0.5 else { return }
        height = newValue
    }
}

private struct MyGoalCard: View {
    let goalName: String
    let isGoalSet: Bool
    let pulse: Bool
    let showHint: Bool
    let onTap: () -> Void
    let onHintAppear: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 14) {
                Text("My Goal")
                    .font(.neueMontrealSemiBold(size: 24))
                    .foregroundColor(.white.opacity(0.6))
                
                HStack(alignment: .top, spacing: 10) {
                    Text(goalName)
                        .font(.neueMontrealBold(size: 40))
                        .foregroundColor(.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.5)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: "square.and.pencil")
                        .font(.neueMontrealBold(size: 22))
                        .foregroundColor(.textPrimary.opacity(0.9))
                }
                
                Text("This is why you're here. Every rep gets you closer 🚀")
                    .font(.neueMontrealRegular(size: 16))
                    .foregroundColor(.textPrimary.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)

                if showHint {
                    Text("Tap to set your goal")
                        .font(.neueMontrealSemiBold(size: 13))
                        .foregroundColor(.textPrimary.opacity(0.95))
                        .padding(.top, 4)
                        .onAppear(perform: onHintAppear)
                } else if !isGoalSet {
                    Text("Set a goal to get personalized coaching")
                        .font(.neueMontrealRegular(size: 13))
                        .foregroundColor(.textPrimary.opacity(0.8))
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 26)
            .padding(.horizontal, 24)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.accentGradient)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.stroke, lineWidth: 1)
                    )
            )
            .shadow(color: Color.primaryPurple.opacity(0.45), radius: 28, y: 14)
            // Base shadow provides the glow; avoid extra blur layers to keep render fast.
        }
        .buttonStyle(.plain)
        .scaleEffect(pulse ? 1.03 : 1.0)
        .animation(
            pulse ? Animation.easeInOut(duration: 0.6).repeatCount(2, autoreverses: true) : nil,
            value: pulse
        )
        .accessibilityLabel("My Goal. Currently \(goalName). Double tap to change")
    }
}



