//
//  PoseMetricsView.swift
//  Chiron
//
//  Developer panel for pose pipeline metrics: dropped frames, inference latency,
//  jitter, rep tracking, optional landmark recording and debug overlay toggles.
//  Reached via Settings → Developer → Pose Metrics.
//

import SwiftUI

struct PoseMetricsView: View {
    @ObservedObject private var metrics = OnDevicePoseManager.shared.metricsCollector
    @ObservedObject private var recorder = OnDevicePoseManager.shared.landmarkRecorder
    @ObservedObject private var poseManager = OnDevicePoseManager.shared

    var body: some View {
        List {
            Section("Pipeline") {
                MetricRow(label: "Frames sent", value: "\(metrics.framesSent)")
                MetricRow(label: "Frames received", value: "\(metrics.framesReceived)")
                MetricRow(label: "Dropped frames", value: "\(metrics.droppedFrames)")
                MetricRow(label: "Avg latency", value: String(format: "%.1f ms", metrics.avgLatencyMs))
            }

            Section("Stability") {
                MetricRow(label: "Overall jitter", value: String(format: "%.6f", metrics.overallJitter))
                if !metrics.perJointJitter.isEmpty {
                    let sorted = metrics.perJointJitter.sorted { $0.value > $1.value }
                    ForEach(sorted.prefix(5), id: \.key) { joint, variance in
                        MetricRow(label: joint, value: String(format: "%.6f", variance))
                    }
                }
            }

            Section("Rep Tracking") {
                MetricRow(label: "Rep count", value: "\(poseManager.repCount)")
                MetricRow(label: "Current set", value: "\(poseManager.currentSet)")
                MetricRow(label: "Workout state", value: workoutStateLabel)
                MetricRow(label: "Analysis source", value: analysisSourceLabel)
            }

            Section("Landmark Recording") {
                Toggle("Record landmarks", isOn: Binding(
                    get: { recorder.isRecording },
                    set: { on in
                        if on { recorder.startRecording() }
                        else { recorder.stopRecording() }
                    }
                ))
                MetricRow(label: "Frames recorded", value: "\(recorder.frameCount)")
                if let url = recorder.lastSavedURL {
                    Text(url.lastPathComponent)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("Debug Overlay") {
                Toggle("Show debug overlay", isOn: Binding(
                    get: { DebugPoseOverlay.isEnabled },
                    set: { DebugPoseOverlay.isEnabled = $0 }
                ))
            }

            Section {
                Button("Reset Metrics") {
                    metrics.reset()
                }
                .foregroundColor(.red)
            }
        }
        .navigationTitle("Pose Metrics")
    }

    private var workoutStateLabel: String {
        switch poseManager.workoutState {
        case .waiting:    return "Waiting"
        case .exercising: return "Exercising"
        case .resting:    return "Resting"
        case .finished:   return "Finished"
        }
    }

    private var analysisSourceLabel: String {
        switch poseManager.currentAnalysisSource {
        case .pose2D: return "2D (legacy)"
        case .pose3D: return "3D (MediaPipe)"
        }
    }
}

// MARK: - Helper

private struct MetricRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.primary)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
    }
}
