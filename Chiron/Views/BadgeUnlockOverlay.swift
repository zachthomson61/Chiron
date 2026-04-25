//
//  BadgeUnlockOverlay.swift
//  Chiron
//
//  Floating celebration card that animates in from the top whenever
//  `BadgeCenter.shared.pendingUnlock` becomes non-nil. Sits in the same
//  `RootTabView` ZStack as the PR confetti so every workout flow (Track tab,
//  predetermined workouts) fires into the same surface — no per-screen
//  plumbing required.
//
//  The card auto-dismisses after `presentationDuration` and tells the center
//  it's done so chained unlocks (e.g. set-completion crossing both 100 Club
//  and Set Closer) animate sequentially instead of overlapping.
//

import SwiftUI

struct BadgeUnlockOverlay: View {
    @ObservedObject private var center = BadgeCenter.shared
    @State private var visible: Bool = false
    @State private var dismissWorkItem: DispatchWorkItem?

    /// How long the celebration sits on screen before retracting. Tuned so
    /// the user can read the title without it overstaying the moment.
    private let presentationDuration: TimeInterval = 2.6
    private let slideInDuration: Double = 0.45
    private let slideOutDuration: Double = 0.35

    var body: some View {
        // Always reserve the layout; render content only when there's a badge.
        VStack {
            if let badge = center.pendingUnlock {
                cardView(for: badge)
                    .padding(.top, 56)
                    .padding(.horizontal, 20)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .opacity
                        )
                    )
                    .onAppear {
                        scheduleAutoDismiss()
                    }
            }
            Spacer()
        }
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(center.pendingUnlock != nil)
        .animation(.spring(response: slideInDuration, dampingFraction: 0.78), value: center.pendingUnlock?.id)
        .onChange(of: center.pendingUnlock?.id) { _, newID in
            // Reschedule dismissal whenever a new badge surfaces (handles
            // the edge case where chained unlocks replace the current one
            // before the previous timer fires).
            if newID != nil { scheduleAutoDismiss() }
        }
    }

    @ViewBuilder
    private func cardView(for badge: Badge) -> some View {
        HStack(spacing: 14) {
            BadgeArtworkView(badge: badge, size: 60)

            VStack(alignment: .leading, spacing: 2) {
                Text("Badge Unlocked")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(badge.category.accent)
                    .textCase(.uppercase)
                Text(badge.title)
                    .font(.title3.weight(.bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(badge.tagline)
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.78))
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black.opacity(0.78))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(badge.category.accent.opacity(0.55), lineWidth: 1.2)
                )
                .shadow(color: badge.category.accent.opacity(0.45), radius: 14, y: 4)
        )
        .onTapGesture { dismissNow() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }

    private func scheduleAutoDismiss() {
        dismissWorkItem?.cancel()
        let work = DispatchWorkItem {
            withAnimation(.easeIn(duration: slideOutDuration)) {
                center.didFinishCelebration()
            }
        }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + presentationDuration, execute: work)
    }

    private func dismissNow() {
        dismissWorkItem?.cancel()
        withAnimation(.easeIn(duration: slideOutDuration)) {
            center.didFinishCelebration()
        }
    }
}

#if DEBUG
struct BadgeUnlockOverlay_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            BadgeUnlockOverlay()
        }
        .onAppear {
            BadgeCenter.shared.pendingUnlock = BadgeCatalog.depthDemon
        }
        .preferredColorScheme(.dark)
    }
}
#endif
