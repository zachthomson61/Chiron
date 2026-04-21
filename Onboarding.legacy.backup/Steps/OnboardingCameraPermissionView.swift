import SwiftUI
import AVFoundation

// MARK: - Screen 15: Camera Permission

struct OnboardingCameraPermissionView: View, OnboardingScreen {
    let screenId = "screen_15"
    @ObservedObject var coordinator: OnboardingCoordinator
    @State private var showFallback = false
    @State private var iconScale: CGFloat = 0.6
    @State private var iconPulse: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: 40)

                    // Camera icon
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 72))
                        .foregroundColor(Color.primaryPurple)
                        .scaleEffect(iconScale)
                        .scaleEffect(iconPulse ? 1.04 : 1.0)
                        .onAppear {
                            if !reduceMotion {
                                withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) {
                                    iconScale = 1.0
                                }
                                withAnimation(
                                    .easeInOut(duration: 2.0)
                                    .repeatForever(autoreverses: true)
                                ) {
                                    iconPulse = true
                                }
                            } else {
                                iconScale = 1.0
                            }
                        }
                        .accessibilityHidden(true)

                    Spacer().frame(height: 16)

                    // Title
                    Text("Your AI coach needs to see you move")
                        .font(.neueMontrealBold(size: 28))
                        .foregroundColor(Color.pureWhite)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)

                    Spacer().frame(height: 12)

                    // Privacy guarantees
                    VStack(spacing: 8) {
                        PrivacyLine(text: "No video is stored.")
                        PrivacyLine(text: "No footage leaves your phone.")
                        PrivacyLine(text: "Everything is processed on-device.")
                    }

                    Spacer().frame(height: 32)

                    if !showFallback {
                        // Identity statement
                        Text("You demanded a coach who watches every rep.")
                            .font(.neueMontrealSemiBold(size: 17))
                            .foregroundColor(Color.pureWhite.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    Spacer().frame(height: 20)
                }
            }

            if showFallback {
                // Inline fallback card
                fallbackCard
            } else {
                // Primary CTA
                OnboardingCTAButton(title: "Unlock my AI coach") {
                    requestCameraAccess()
                }
                .padding(.bottom, 12)

                // Secondary CTA
                Button(action: {
                    handleDeniedOrSkipped(analyticsValue: "skipped")
                }) {
                    Text("Maybe later")
                        .font(.neueMontrealRegular(size: 15))
                        .foregroundColor(Color.textSecondary)
                        .frame(height: 44)
                }
                .padding(.bottom, 16)
                .accessibilityLabel("Maybe later")
                .accessibilityHint("Continue without camera coaching")
            }
        }
        .accessibilityHint("Camera access is required for the AI coach to analyze your form in real time. No video is stored or sent anywhere.")
    }

    // MARK: - Fallback Card

    private var fallbackCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.badge.ellipsis")
                .font(.system(size: 44))
                .foregroundColor(Color.textSecondary)

            Text("Camera coaching is off for now")
                .font(.neueMontrealSemiBold(size: 17))
                .foregroundColor(Color.pureWhite)

            Text("You can still log workouts and track progress. Enable camera access anytime in Settings > Chiron to unlock real-time form coaching.")
                .font(.neueMontrealRegular(size: 15))
                .foregroundColor(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            Button(action: {
                coordinator.completeScreen(screenId, answer: "denied")
            }) {
                Text("Continue without camera")
                    .font(.neueMontrealSemiBold(size: 17))
                    .foregroundColor(Color.pureWhite)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.white.opacity(0.12))
                    .cornerRadius(28)
            }
            .accessibilityLabel("Continue without camera")
        }
        .padding(16)
        .background(Color.white.opacity(0.06))
        .cornerRadius(16)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .transition(
            reduceMotion
                ? .opacity
                : .move(edge: .bottom).combined(with: .opacity)
        )
    }

    // MARK: - Camera Permission Logic

    private func requestCameraAccess() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                if granted {
                    handleGranted()
                } else {
                    handleDeniedOrSkipped(analyticsValue: "denied")
                }
            }
        }
    }

    private func handleGranted() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        coordinator.setCameraGranted(true)
        coordinator.showAffirmationToast("Coach unlocked.", forScreen: screenId)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            coordinator.completeScreen(screenId, answer: "granted")
        }
    }

    private func handleDeniedOrSkipped(analyticsValue: String) {
        coordinator.setCameraGranted(false)
        withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.2)) {
            showFallback = true
        }
    }
}

// MARK: - Privacy Line

private struct PrivacyLine: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 12))
                .foregroundColor(Color.textSecondary)
            Text(text)
                .font(.neueMontrealRegular(size: 15))
                .foregroundColor(Color.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}
