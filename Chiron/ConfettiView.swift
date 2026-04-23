//
//  ConfettiView.swift
//  Chiron
//
//  Short-lived confetti overlay used when a PR is achieved. Particles are
//  drawn by a Canvas driven by a TimelineView — no UIKit, no external lib.
//  The view is fully transparent and non-hit-testing; callers drop it into
//  a ZStack above app content and clear it when `isActive` goes false.
//

import SwiftUI

struct ConfettiView: View {
    /// When this flips from false → true, a fresh burst of particles is seeded
    /// and animated until `duration` elapses, at which point the view resets
    /// `isActive` back to false so the parent can release the overlay.
    @Binding var isActive: Bool
    /// Total burst length including the 0.6s fade-out tail.
    var duration: TimeInterval = 3.0

    @State private var particles: [Particle] = []
    @State private var startTime: Date?

    var body: some View {
        TimelineView(.animation) { context in
            Canvas { ctx, size in
                guard let startTime else { return }
                let elapsed = context.date.timeIntervalSince(startTime)
                let fadeStart = duration - 0.6

                for particle in particles {
                    let t = CGFloat(elapsed)
                    // Position: origin + velocity*t + 0.5 * gravity * t^2
                    let x = particle.originX * size.width
                        + particle.velocityX * t
                    let y = particle.originY * size.height
                        + particle.velocityY * t
                        + 0.5 * 360 * t * t
                    let rotation = particle.initialRotation
                        + particle.angularVelocity * Double(t)

                    let alpha: Double
                    if elapsed >= fadeStart {
                        let fadeProgress = (elapsed - fadeStart) / 0.6
                        alpha = max(0, 1 - fadeProgress)
                    } else {
                        alpha = 1
                    }

                    var transform = CGAffineTransform.identity
                    transform = transform.translatedBy(x: x, y: y)
                    transform = transform.rotated(by: rotation)

                    let rect = CGRect(
                        x: -particle.size.width / 2,
                        y: -particle.size.height / 2,
                        width: particle.size.width,
                        height: particle.size.height
                    )
                    let path = Path(roundedRect: rect, cornerRadius: 1.5)
                        .applying(transform)
                    ctx.fill(path, with: .color(particle.color.opacity(alpha)))
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
        .onChange(of: isActive) { _, active in
            if active {
                seed()
            } else {
                particles = []
                startTime = nil
            }
        }
    }

    private func seed() {
        particles = (0..<90).map { _ in Particle.random() }
        startTime = Date()
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            isActive = false
        }
    }

    private struct Particle {
        let originX: CGFloat           // 0..1 across width
        let originY: CGFloat           // 0..1 down height (negative = above screen)
        let velocityX: CGFloat         // pts/sec horizontal drift
        let velocityY: CGFloat         // pts/sec initial downward speed
        let initialRotation: Double    // radians
        let angularVelocity: Double    // radians/sec
        let size: CGSize
        let color: Color

        static func random() -> Particle {
            let palette: [Color] = [
                Color(red: 0.98, green: 0.76, blue: 0.18), // gold
                Color(red: 0.93, green: 0.28, blue: 0.34), // red
                Color(red: 0.28, green: 0.67, blue: 0.94), // blue
                Color(red: 0.34, green: 0.83, blue: 0.47), // green
                Color(red: 0.67, green: 0.42, blue: 0.96), // purple
                Color(red: 1.00, green: 1.00, blue: 1.00)  // white
            ]
            return Particle(
                originX: CGFloat.random(in: 0.05...0.95),
                originY: CGFloat.random(in: -0.1...0.1),
                velocityX: CGFloat.random(in: -160...160),
                velocityY: CGFloat.random(in: 80...320),
                initialRotation: Double.random(in: 0...(2 * .pi)),
                angularVelocity: Double.random(in: -8...8),
                size: CGSize(
                    width: CGFloat.random(in: 6...11),
                    height: CGFloat.random(in: 10...16)
                ),
                color: palette.randomElement() ?? .yellow
            )
        }
    }
}
