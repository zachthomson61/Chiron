//
//  CloseGripBenchSummary.swift
//  Chiron
//
//  Compact summary model for close-grip bench press form data.
//  Used to send summarized metrics to OpenAI for coaching feedback.
//

import Foundation

/// Compact summary of close-grip bench press set metrics for AI coaching.
/// Extracted from FormAnalysis and pose detection data when transitioning to rest.
struct CloseGripBenchSummary: Codable {
    /// Form score (1-100) calculated from pose detection
    let formScore: Int
    
    /// Number of reps completed in the set
    let reps: Int
    
    /// Duration of the set in seconds
    let setDurationSec: Double
    
    /// Average eccentric (lowering) tempo in seconds (nil if not tracked)
    let avgTempoEccentricSec: Double?
    
    /// Average concentric (pressing) tempo in seconds (nil if not tracked)
    let avgTempoConcentricSec: Double?
    
    /// Average elbow tuck angle in degrees (nil if not tracked)
    /// Lower values indicate better tuck (elbows closer to sides)
    let avgElbowTuckDeg: Double?
    
    /// Standard deviation of elbow tuck (nil - not currently tracked)
    let elbowTuckStdDev: Double?
    
    /// Average wrist stack error in cm (nil - not currently tracked)
    let avgWristStackErrorCm: Double?
    
    /// Bar path deviation in cm (nil - not currently tracked)
    let barPathDeviationCm: Double?
    
    /// Left/right shoulder height difference in cm (nil - not currently tracked)
    let shoulderSymmetryCm: Double?
    
    /// Range of motion percentage (0-100, nil if not tracked)
    let rangeOfMotionPct: Double?
    
    /// Key warnings/issues detected (only populated if formScore < 75)
    let keyWarnings: [String]
    
    /// Creates a summary from FormAnalysis and set timing data.
    ///
    /// - Parameters:
    ///   - formAnalysis: The form analysis from OnDevicePoseManager
    ///   - setStartTime: When the set started (for duration calculation)
    ///   - setEndTime: When the set ended (defaults to now)
    /// - Returns: A compact summary suitable for AI coaching
    static func from(
        formAnalysis: FormAnalysis,
        setStartTime: Date?,
        setEndTime: Date = Date()
    ) -> CloseGripBenchSummary {
        // Calculate form score (1-100)
        let formScore = max(1, min(100, Int(formAnalysis.overallScore * 100)))
        
        // Calculate set duration
        let setDurationSec: Double
        if let startTime = setStartTime {
            setDurationSec = setEndTime.timeIntervalSince(startTime)
        } else {
            // Fallback: estimate based on reps (assume ~3 seconds per rep)
            setDurationSec = Double(formAnalysis.repCount) * 3.0
        }
        
        // Convert tempo from milliseconds to seconds
        let avgTempoEccentricSec: Double? = formAnalysis.avgEccentricMs.map { Double($0) / 1000.0 }
        let avgTempoConcentricSec: Double? = formAnalysis.avgConcentricMs.map { Double($0) / 1000.0 }
        
        // ROM percentage from depth (depth is 0-1, convert to percentage)
        // For bench press, we use avgBottomDepth if available
        let rangeOfMotionPct: Double? = formAnalysis.avgBottomDepth.map { Double($0) * 100.0 }
        
        // Key warnings only populated if form score < 75
        let keyWarnings: [String]
        if formScore < 75 {
            keyWarnings = formAnalysis.issues
        } else {
            keyWarnings = []
        }
        
        return CloseGripBenchSummary(
            formScore: formScore,
            reps: formAnalysis.repCount,
            setDurationSec: setDurationSec,
            avgTempoEccentricSec: avgTempoEccentricSec,
            avgTempoConcentricSec: avgTempoConcentricSec,
            avgElbowTuckDeg: nil, // Not currently tracked as degrees
            elbowTuckStdDev: nil, // Not currently tracked
            avgWristStackErrorCm: nil, // Not currently tracked
            barPathDeviationCm: nil, // Not currently tracked
            shoulderSymmetryCm: nil, // Not currently tracked
            rangeOfMotionPct: rangeOfMotionPct,
            keyWarnings: keyWarnings
        )
    }
    
    /// Converts the summary to a JSON string for the AI prompt.
    func toJSONString() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        
        guard let data = try? encoder.encode(self),
              let jsonString = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return jsonString
    }
}
