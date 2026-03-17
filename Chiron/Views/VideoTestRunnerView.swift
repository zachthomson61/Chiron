//
//  VideoTestRunnerView.swift
//  Chiron
//
//  UI for running bundled test videos through MediaPipe and viewing latency,
//  jitter, and saved landmark JSON. Settings → Developer → Video Tests.
//

import SwiftUI

struct VideoTestRunnerView: View {
    @StateObject private var runner = VideoTestRunner()

    var body: some View {
        List {
            Section("Run Tests") {
                Button(action: { runner.runAll() }) {
                    HStack {
                        Text("Run All Test Videos")
                        Spacer()
                        if runner.isRunning {
                            ProgressView()
                        }
                    }
                }
                .disabled(runner.isRunning)

                if runner.isRunning {
                    HStack {
                        Text("Processing: \(runner.currentVideo)")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "%.0f%%", runner.progress * 100))
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    }
                }
            }

            if !runner.results.isEmpty {
                Section("Results") {
                    ForEach(runner.results) { r in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(r.videoName)
                                .font(.headline)
                            HStack {
                                Label("\(r.totalFrames) frames", systemImage: "film")
                                Spacer()
                                Label("\(r.framesWithPose) poses", systemImage: "figure.stand")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)

                            HStack {
                                Text(String(format: "Latency: %.1f ms", r.avgLatencyMs))
                                Spacer()
                                Text(String(format: "Jitter: %.6f", r.avgJitter))
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)

                            if let url = r.landmarkFileURL {
                                Text(url.lastPathComponent)
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section("Test Videos") {
                ForEach(VideoTestRunner.testVideos, id: \.self) { name in
                    HStack {
                        Text(name)
                        Spacer()
                        if Bundle.main.path(forResource: name, ofType: "mp4") != nil {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Image(systemName: "xmark.circle")
                                .foregroundColor(.red)
                        }
                    }
                }
                Text("Add .mp4 files to TestVideos/ and include in the app target.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Video Tests")
    }
}
