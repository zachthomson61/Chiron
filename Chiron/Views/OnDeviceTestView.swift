import SwiftUI

struct OnDeviceTestView: View {
    @StateObject private var viewModel = WorkoutViewModel()
    
    var body: some View {
        CameraSetupView(exerciseType: .bodyweightSquat, viewModel: viewModel)
    }
}

#Preview {
    OnDeviceTestView()
} 