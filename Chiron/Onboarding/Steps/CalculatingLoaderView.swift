//
//  CalculatingLoaderView.swift
//  Chiron
//
//  Step 10 — gradient progress bar with a cycling status line. Minimum 1.8s dwell
//  so the reveal after it has weight (Opal pattern). No CTA, no back button.
//

import SwiftUI

struct CalculatingLoaderView: View {
    @Bindable var coordinator: ChironOnboardingCoordinator

    /// Minimum time the loader stays on screen even if the underlying work is instant.
    /// Shortening this kills the feeling of "the app is working for me" — keep it ≥1.8s.
    private let minimumDwell: TimeInterval = 2.4

    private let messages: [String] = [
        "Calibrating form thresholds…",
        "Tuning your coach…",
        "Loading the six lifts…",
        "Almost there…"
    ]

    @State private var progress: Double = 0.0
    @State private var messageIndex: Int = 0

    var body: some View {
        ZStack {
            OnboardingTheme.canvas.ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                ZStack {
                    Circle()
                        .stroke(OnboardingTheme.stroke, lineWidth: 6)
                        .frame(width: 120, height: 120)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            OnboardingTheme.accentGradient,
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .frame(width: 120, height: 120)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: minimumDwell), value: progress)
                }

                VStack(spacing: 12) {
                    Text("Building your plan")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(OnboardingTheme.textPrimary)

                    Text(messages[messageIndex])
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(OnboardingTheme.textSecondary)
                        .id(messageIndex)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        .animation(.easeInOut(duration: 0.35), value: messageIndex)
                }

                // Horizontal gradient progress bar.
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(OnboardingTheme.stroke)

                        Capsule()
                            .fill(OnboardingTheme.accentGradient)
                            .frame(width: proxy.size.width * CGFloat(progress))
                            .animation(.easeInOut(duration: minimumDwell), value: progress)
                    }
                }
                .frame(height: 6)
                .padding(.horizontal, 40)

                Spacer()
            }
            .padding(.horizontal, OnboardingTheme.screenHorizontalPadding)
        }
        .onAppear(perform: runLoader)
    }

    private func runLoader() {
        // Kick off the progress animation immediately.
        withAnimation(.easeInOut(duration: minimumDwell)) {
            progress = 1.0
        }

        // Cycle the status line so the user has something to read.
        let tick = minimumDwell / Double(messages.count)
        for index in 1..<messages.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + tick * Double(index)) {
                messageIndex = index
            }
        }

        // Advance to the reveal once the minimum dwell has elapsed.
        DispatchQueue.main.asyncAfter(deadline: .now() + minimumDwell) {
            coordinator.advance()
        }
    }
}

#Preview {
    CalculatingLoaderView(coordinator: ChironOnboardingCoordinator(store: InMemoryUserProfileStore()))
}
