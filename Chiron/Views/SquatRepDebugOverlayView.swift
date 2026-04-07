//
//  SquatRepDebugOverlayView.swift
//  Chiron
//
//  Debug overlay for bodyweight squat rep detection.
//  Shows live numeric panel, mini knee-angle chart, and CSV export button.
//  Enable via the debug toggle on TrackView (only visible in DEBUG builds).
//

import SwiftUI
import UIKit

// MARK: - Debug Overlay Container

struct SquatRepDebugOverlayView: View {
    @State private var tick: Int = 0
    private let refreshTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    @State private var showShareSheet = false
    @State private var csvURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SquatRepMiniChartView(tick: tick)
                .frame(height: 100)
                .background(Color.black.opacity(0.5))
                .cornerRadius(6)

            SquatRepNumericPanelView(tick: tick)
                .background(Color.black.opacity(0.5))
                .cornerRadius(6)

            HStack {
                Button {
                    let csv = SquatRepDebugLogger.shared.exportCSV()
                    let url = FileManager.default.temporaryDirectory
                        .appendingPathComponent("squat_debug_\(Int(Date().timeIntervalSince1970)).csv")
                    try? csv.data(using: .utf8)?.write(to: url)
                    csvURL = url
                    showShareSheet = true
                } label: {
                    Label("Export CSV", systemImage: "square.and.arrow.up")
                        .font(.caption2)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.6))
                        .cornerRadius(4)
                }

                Button {
                    SquatRepDebugLogger.shared.reset()
                } label: {
                    Label("Clear", systemImage: "trash")
                        .font(.caption2)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.6))
                        .cornerRadius(4)
                }

                Spacer()

                Text("\(SquatRepDebugLogger.shared.allFrames.count) frames")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
        .padding(6)
        .onReceive(refreshTimer) { _ in
            tick += 1
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = csvURL {
                SquatRepShareSheet(url: url)
            }
        }
    }
}

// MARK: - Numeric Panel

struct SquatRepNumericPanelView: View {
    let tick: Int

    var body: some View {
        let f = SquatRepDebugLogger.shared.latestFrame

        VStack(alignment: .leading, spacing: 2) {
            debugRow("Phase", f?.phase ?? "-")
            debugRow("Knee angle raw", fmtOpt(f?.kneeAngleRaw))
            debugRow("Knee angle EMA", fmtOpt(f?.kneeAngleSmoothed))
            debugRow("Side", f?.selectedSide ?? "-")
            debugRow("Down thresh", fmtOpt(f?.downAngleThreshold))
            debugRow("Up thresh", fmtOpt(f?.upAngleThreshold))

            Divider().background(Color.gray)

            debugRow("Hip depth 3D", fmtOpt(f?.hipDepth3D))
            debugRow("Standing hip H", fmtOpt(f?.standingHipHeight))
            debugRow("Standing leg L", fmtOpt(f?.standingLegLength))
            debugRow("Leg span (2D)", fmtOpt(f?.overlayLegSpan))

            Divider().background(Color.gray)

            debugRow("Peak depth rep", fmtOpt(f?.peakDepthThisRep))
            debugRow("Rep frames", f.map { "\($0.repFrameCount)" } ?? "-")
            debugRow("Knee samples", f.map { "\($0.kneeWindowSamples)" } ?? "-")

            if let reason = f?.rejectReason {
                debugRow("Last reject", reason)
                    .foregroundColor(.red)
            }
        }
        .padding(4)
    }

    private func debugRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.gray)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
        }
    }

    private func fmtOpt(_ v: Float?) -> String {
        guard let v = v else { return "-" }
        return String(format: "%.1f", v)
    }

    private func fmtOpt(_ v: Float) -> String {
        String(format: "%.1f", v)
    }
}

// MARK: - Mini Chart (last ~3 seconds of knee angle)

struct SquatRepMiniChartView: View {
    let tick: Int

    var body: some View {
        let frames = Array(SquatRepDebugLogger.shared.chartFrames)
        GeometryReader { geo in
            chartContent(frames: frames, size: geo.size)
        }
    }

    @ViewBuilder
    private func chartContent(frames: [SquatRepDebugFrame], size: CGSize) -> some View {
        let w = size.width
        let h = size.height
        let angles = frames.compactMap { $0.kneeAngleSmoothed }
        let hasData = frames.count >= 2 && angles.count >= 2

        if hasData {
            // Fixed Y axis: 40° (deep squat) to 190° (standing)
            let plotMin: Float = 40
            let plotMax: Float = 190
            let plotRange = plotMax - plotMin

            ZStack {
                // Phase background bands
                ForEach(0..<frames.count, id: \.self) { i in
                    let x = CGFloat(i) / CGFloat(max(1, frames.count - 1)) * w
                    let bandW = w / CGFloat(max(1, frames.count))
                    Rectangle()
                        .fill(phaseColor(frames[i].phase).opacity(0.15))
                        .frame(width: bandW, height: h)
                        .position(x: x, y: h / 2)
                }

                // Down threshold line
                if let thresh = frames.last?.downAngleThreshold {
                    let y = CGFloat((plotMax - thresh) / plotRange) * h
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: w, y: y))
                    }
                    .stroke(Color.orange.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }

                // Up threshold line
                if let thresh = frames.last?.upAngleThreshold {
                    let y = CGFloat((plotMax - thresh) / plotRange) * h
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: w, y: y))
                    }
                    .stroke(Color.green.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }

                // Knee angle line
                Path { path in
                    for (i, frame) in frames.enumerated() {
                        if let angle = frame.kneeAngleSmoothed {
                            let x = CGFloat(i) / CGFloat(max(1, frames.count - 1)) * w
                            let y = CGFloat((plotMax - angle) / plotRange) * h
                            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                            else { path.addLine(to: CGPoint(x: x, y: y)) }
                        }
                    }
                }
                .stroke(Color.cyan, lineWidth: 1.5)

                // Rep counted markers
                ForEach(0..<frames.count, id: \.self) { i in
                    if frames[i].repCounted {
                        let x = CGFloat(i) / CGFloat(max(1, frames.count - 1)) * w
                        Path { p in
                            p.move(to: CGPoint(x: x, y: 0))
                            p.addLine(to: CGPoint(x: x, y: h))
                        }
                        .stroke(Color.yellow, lineWidth: 2)
                    }
                }
            }
        } else {
            Text("Collecting frames...")
                .font(.caption2).foregroundColor(.gray)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func phaseColor(_ phase: String) -> Color {
        switch phase {
        case "up":   return .green
        case "down": return .red
        default:     return .gray
        }
    }
}

// MARK: - Share Sheet (UIKit wrapper)

struct SquatRepShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
