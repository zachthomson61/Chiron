//
//  WorkoutPhaseProgressHeader.swift
//  Chiron
//
//  Horizontal workout phase progress header showing overall progress track
//  and phase indicators with expandable current phase capsule.
//

import SwiftUI

/// Represents a single phase in the workout with its state
struct WorkoutPhase {
    let id: String
    let name: String
    var isComplete: Bool
    var isCurrent: Bool
    var phaseProgress: Double // 0.0 to 1.0, only meaningful for current phase
}

/// Horizontal header component displaying overall workout progress and phase indicators.
///
/// Features:
/// - Long capsule progress track (left side) showing overall phases completed
/// - Phase indicators (right side) as circles or expanding capsules
/// - Current phase expands to show within-phase progress
/// - Smooth animations for phase transitions and progress updates
struct WorkoutPhaseProgressHeader: View {
    let phases: [WorkoutPhase]
    let overallProgress: Double // Overall phases completed (0.0 to 1.0)
    
    // Visual constants
    private let trackHeight: CGFloat = 12
    private let circleDiameter: CGFloat = 10
    private let expandedCapsuleWidth: CGFloat = 36 // ~3.6x circle diameter
    private let indicatorSpacing: CGFloat = 4 // Reduced from 7 to bring dots closer together
    
    var body: some View {
        // Just show phase indicators (no overall progress track)
        phaseIndicators
            .frame(height: trackHeight)
    }
    
    // MARK: - Phase Indicators
    
    private var phaseIndicators: some View {
        HStack(spacing: indicatorSpacing) {
            ForEach(Array(phases.enumerated()), id: \.element.id) { index, phase in
                PhaseIndicator(
                    phase: phase,
                    circleDiameter: circleDiameter,
                    expandedWidth: expandedCapsuleWidth
                )
            }
        }
        .frame(height: trackHeight)
    }
}

// MARK: - Phase Indicator

private struct PhaseIndicator: View {
    let phase: WorkoutPhase
    let circleDiameter: CGFloat
    let expandedWidth: CGFloat
    
    private var isExpanded: Bool {
        phase.isCurrent
    }
    
    private var width: CGFloat {
        isExpanded ? expandedWidth : circleDiameter
    }
    
    var body: some View {
        ZStack(alignment: .leading) {
            // Background shape - use Capsule for both states (circle when width == height)
            Capsule()
                .fill(indicatorBackgroundColor)
                .frame(width: width, height: circleDiameter)
            
            // Progress fill (only for current phase)
            if isExpanded && phase.phaseProgress > 0 {
                Capsule()
                    .fill(Color.textPrimary)
                    .frame(
                        width: max(0, min(width, width * clampedPhaseProgress)),
                        height: circleDiameter
                    )
                    .animation(.linear(duration: 0.3), value: phase.phaseProgress)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isExpanded)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: width)
        .frame(width: width, height: circleDiameter)
    }
    
    private var indicatorBackgroundColor: Color {
        if phase.isComplete {
            return Color.textPrimary.opacity(0.8)
        } else if phase.isCurrent {
            return Color.white.opacity(0.2)
        } else {
            return Color.white.opacity(0.3)
        }
    }
    
    private var clampedPhaseProgress: Double {
        max(0.0, min(1.0, phase.phaseProgress))
    }
}

// MARK: - Previews

#Preview("All Future") {
    ZStack {
        Color.background.ignoresSafeArea()
        
        VStack {
            Spacer()
            
            WorkoutPhaseProgressHeader(
                phases: [
                    WorkoutPhase(id: "1", name: "Warm-up", isComplete: false, isCurrent: false, phaseProgress: 0.0),
                    WorkoutPhase(id: "2", name: "Primer", isComplete: false, isCurrent: false, phaseProgress: 0.0),
                    WorkoutPhase(id: "3", name: "Superset 1", isComplete: false, isCurrent: false, phaseProgress: 0.0),
                    WorkoutPhase(id: "4", name: "Superset 2", isComplete: false, isCurrent: false, phaseProgress: 0.0),
                    WorkoutPhase(id: "5", name: "Finisher", isComplete: false, isCurrent: false, phaseProgress: 0.0),
                    WorkoutPhase(id: "6", name: "Cool Down", isComplete: false, isCurrent: false, phaseProgress: 0.0)
                ],
                overallProgress: 0.0
            )
            
            Spacer()
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("Some Complete + Current") {
    ZStack {
        Color.background.ignoresSafeArea()
        
        VStack {
            Spacer()
            
            WorkoutPhaseProgressHeader(
                phases: [
                    WorkoutPhase(id: "1", name: "Warm-up", isComplete: true, isCurrent: false, phaseProgress: 1.0),
                    WorkoutPhase(id: "2", name: "Primer", isComplete: true, isCurrent: false, phaseProgress: 1.0),
                    WorkoutPhase(id: "3", name: "Superset 1", isComplete: false, isCurrent: true, phaseProgress: 0.3),
                    WorkoutPhase(id: "4", name: "Superset 2", isComplete: false, isCurrent: false, phaseProgress: 0.0),
                    WorkoutPhase(id: "5", name: "Finisher", isComplete: false, isCurrent: false, phaseProgress: 0.0),
                    WorkoutPhase(id: "6", name: "Cool Down", isComplete: false, isCurrent: false, phaseProgress: 0.0),
                    WorkoutPhase(id: "7", name: "Stretch", isComplete: false, isCurrent: false, phaseProgress: 0.0)
                ],
                overallProgress: 2.0 / 7.0
            )
            
            Spacer()
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("Current at 80%") {
    ZStack {
        Color.background.ignoresSafeArea()
        
        VStack {
            Spacer()
            
            WorkoutPhaseProgressHeader(
                phases: [
                    WorkoutPhase(id: "1", name: "Warm-up", isComplete: true, isCurrent: false, phaseProgress: 1.0),
                    WorkoutPhase(id: "2", name: "Primer", isComplete: true, isCurrent: false, phaseProgress: 1.0),
                    WorkoutPhase(id: "3", name: "Superset 1", isComplete: true, isCurrent: false, phaseProgress: 1.0),
                    WorkoutPhase(id: "4", name: "Superset 2", isComplete: true, isCurrent: false, phaseProgress: 1.0),
                    WorkoutPhase(id: "5", name: "Finisher", isComplete: false, isCurrent: true, phaseProgress: 0.8),
                    WorkoutPhase(id: "6", name: "Cool Down", isComplete: false, isCurrent: false, phaseProgress: 0.0),
                    WorkoutPhase(id: "7", name: "Stretch", isComplete: false, isCurrent: false, phaseProgress: 0.0)
                ],
                overallProgress: 4.0 / 7.0
            )
            
            Spacer()
        }
    }
    .preferredColorScheme(.dark)
}
