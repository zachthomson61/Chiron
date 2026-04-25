//
//  BadgeArtworkView.swift
//  Chiron
//
//  Visual treatment for a Badge medallion. Three layers compose the artwork:
//
//    1. An outer ring stroked with the category accent + soft glow, so the
//       badge reads as a "minted coin" silhouette regardless of the wallpaper
//       behind it.
//    2. A gradient-filled disc using the category palette, with a radial
//       highlight in the upper-left for depth.
//    3. The category symbol in pure white at the center, balanced against an
//       inner ribbon of small star punctuation that scales with size.
//
//  When `isLocked` is true, the badge desaturates and dims so the gallery can
//  show the user *what's coming next* without misrepresenting it as earned.
//

import SwiftUI

struct BadgeArtworkView: View {
    let badge: Badge
    var size: CGFloat = 96
    var isLocked: Bool = false

    var body: some View {
        ZStack {
            // Outer halo — gives the medallion a sense of presence on dark backgrounds.
            Circle()
                .fill(badge.category.accent.opacity(isLocked ? 0.05 : 0.20))
                .frame(width: size * 1.18, height: size * 1.18)
                .blur(radius: size * 0.08)

            // Base disc.
            Circle()
                .fill(badge.category.gradient)
                .frame(width: size, height: size)
                .overlay(
                    // Top-left highlight to simulate raised metal.
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.white.opacity(0.40), Color.clear],
                                center: .topLeading,
                                startRadius: 0,
                                endRadius: size * 0.65
                            )
                        )
                )
                .overlay(
                    // Inner stroke — separates the symbol from the gradient.
                    Circle()
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: max(1, size * 0.018))
                )

            // Outer ring with accent gradient — the "minted edge".
            Circle()
                .strokeBorder(
                    AngularGradient(
                        colors: [
                            badge.category.accent.opacity(0.95),
                            Color.white.opacity(0.85),
                            badge.category.accent.opacity(0.95),
                            Color.white.opacity(0.55),
                            badge.category.accent.opacity(0.95)
                        ],
                        center: .center
                    ),
                    lineWidth: max(2, size * 0.04)
                )
                .frame(width: size, height: size)

            // Central symbol — white-on-gradient for maximum legibility.
            Image(systemName: badge.symbol)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: size * 0.04, y: size * 0.02)

            // Scatter of small sparkles around the symbol — purely decorative,
            // adds energy without competing with the icon.
            ForEach(sparkleOffsets, id: \.self) { offset in
                Image(systemName: "sparkle")
                    .font(.system(size: size * 0.10, weight: .black))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .offset(offset)
            }
        }
        .frame(width: size * 1.18, height: size * 1.18)
        .saturation(isLocked ? 0.0 : 1.0)
        .opacity(isLocked ? 0.45 : 1.0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(badge.title) badge\(isLocked ? ", locked" : "")")
        .accessibilityHint(badge.tagline)
    }

    /// Three offsets arranged around the medallion edge. Computed off `size`
    /// so the sparkles stay in proportion when the view is reused at smaller
    /// sizes inside the gallery grid.
    private var sparkleOffsets: [CGSize] {
        [
            CGSize(width: -size * 0.32, height: -size * 0.30),
            CGSize(width:  size * 0.34, height: -size * 0.18),
            CGSize(width:  size * 0.04, height:  size * 0.36)
        ]
    }
}

// MARK: - Preview

#if DEBUG
struct BadgeArtworkView_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            VStack(spacing: 24) {
                ForEach(BadgeCategory.allCases) { category in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(category.displayName)
                            .font(.headline).foregroundColor(.white)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 18) {
                                ForEach(BadgeCatalog.all.filter { $0.category == category }) { badge in
                                    VStack(spacing: 6) {
                                        BadgeArtworkView(badge: badge, size: 92)
                                        Text(badge.title)
                                            .font(.caption).foregroundColor(.white)
                                    }
                                }
                            }
                            .padding(.horizontal, 4)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 24)
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
    }
}
#endif
