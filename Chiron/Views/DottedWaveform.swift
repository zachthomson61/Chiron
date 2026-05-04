import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Halftone-style dotted band anchored to a corner. Dots sit on a regular
/// grid clipped to a curved band emanating from an offscreen origin just
/// outside the corner. Color shifts along the arc using the brand gradient,
/// and opacity fades toward both edges of the band so the sweep feels soft.
struct DottedWaveform: View {
    enum Corner: Hashable {
        case topLeading
        case bottomTrailing
    }

    var corner: Corner
    var startColor: Color = .primaryPurple
    var endColor: Color = .accentBlue
    var dotSpacing: CGFloat = 9
    var dotRadius: CGFloat = 1.7
    var innerRadius: CGFloat = 130
    var outerRadius: CGFloat = 280
    var maxOpacity: Double = 0.75

    var body: some View {
        Canvas { context, size in
            let inset: CGFloat = 60
            let origin: CGPoint
            let angleStart: Double
            let angleEnd: Double
            switch corner {
            case .topLeading:
                origin = CGPoint(x: -inset, y: -inset)
                angleStart = 0
                angleEnd = .pi / 2
            case .bottomTrailing:
                origin = CGPoint(x: size.width + inset, y: size.height + inset)
                angleStart = .pi
                angleEnd = 3 * .pi / 2
            }

            let bandWidth = outerRadius - innerRadius
            let angleSpan = angleEnd - angleStart

            var y: CGFloat = 0
            while y <= size.height {
                var x: CGFloat = 0
                while x <= size.width {
                    let dx = x - origin.x
                    let dy = y - origin.y
                    let r = sqrt(dx * dx + dy * dy)

                    if r >= innerRadius && r <= outerRadius {
                        let bandPos = (r - innerRadius) / bandWidth
                        let edgeFade = sin(bandPos * .pi)

                        var angle = atan2(dy, dx)
                        if angle < 0 { angle += 2 * .pi }
                        let angleT = max(0, min(1, (angle - angleStart) / angleSpan))

                        let dotColor = lerp(startColor, endColor, t: Double(angleT))
                            .opacity(edgeFade * maxOpacity)

                        let rect = CGRect(
                            x: x - dotRadius,
                            y: y - dotRadius,
                            width: dotRadius * 2,
                            height: dotRadius * 2
                        )
                        context.fill(Path(ellipseIn: rect), with: .color(dotColor))
                    }
                    x += dotSpacing
                }
                y += dotSpacing
            }
        }
        .allowsHitTesting(false)
    }
}

extension View {
    /// Tab canvas: dark background plus a dotted halftone wave in the
    /// requested corners. Bleeds edge-to-edge under the status bar and tab
    /// bar. Default is both corners (home pattern); pass `[.bottomTrailing]`
    /// for the single-corner accent used on Research/Profile.
    func dottedTabBackground(
        corners: Set<DottedWaveform.Corner> = [.topLeading, .bottomTrailing]
    ) -> some View {
        background {
            ZStack {
                Color.softBlack
                if corners.contains(.topLeading) {
                    DottedWaveform(corner: .topLeading)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                if corners.contains(.bottomTrailing) {
                    DottedWaveform(corner: .bottomTrailing)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
            .ignoresSafeArea()
        }
    }
}

private func lerp(_ a: Color, _ b: Color, t: Double) -> Color {
    let ua = UIColor(a)
    let ub = UIColor(b)
    var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
    var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
    ua.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
    ub.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
    let clamped = CGFloat(max(0, min(1, t)))
    return Color(
        red: Double(ar + (br - ar) * clamped),
        green: Double(ag + (bg - ag) * clamped),
        blue: Double(ab + (bb - ab) * clamped)
    )
}
