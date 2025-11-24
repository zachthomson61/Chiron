//
//  CameraSetupView.swift
//  Chiron
//
//  Backward compatibility wrapper for exercises that haven't been migrated to exercise-specific camera setup views.
//
//  This wrapper routes legacy exercise overview views (DeadliftOverview, BarbellBenchPressOverview, etc.)
//  to the bodyweight squat camera setup flow as a temporary measure.
//
//  Migration Path:
//  When migrating other exercises, create exercise-specific camera setup views following the pattern:
//  1. Create [ExerciseName]CameraSetupView.swift (e.g., DeadliftCameraSetupView.swift)
//  2. Update the exercise overview to route to the new camera setup view
//  3. Remove this wrapper once all exercises are migrated
//

import SwiftUI

/// Temporary backward compatibility wrapper. Routes to bodyweight squat camera setup.
/// TODO: Remove this once all exercises have their own camera setup views.
struct CameraSetupView: View {
    @StateObject private var viewModel = WorkoutViewModel()
    
    var body: some View {
        BodyweightSquatCameraSetupView(viewModel: viewModel)
    }
}

