import SwiftUI

/// Protocol for individual onboarding step views.
protocol OnboardingScreen: View {
    var screenId: String { get }
}
