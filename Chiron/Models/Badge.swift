//
//  Badge.swift
//  Chiron
//
//  Catalog of earnable achievements. Each badge declares its identity, the
//  category it belongs to, and the engaging artwork it should render with
//  (gradient palette + SF Symbol). The conditions that unlock each badge are
//  evaluated by `BadgeCenter` against persisted workout data — this file is
//  pure metadata so the catalog and the evaluator can evolve independently.
//

import SwiftUI

// MARK: - Badge Category

/// Top-level grouping shown in the achievements UI. Each category drives the
/// gradient palette behind the badge artwork so the user can read the type
/// at a glance without parsing copy.
enum BadgeCategory: String, CaseIterable, Codable, Identifiable {
    case firstSteps      = "First Steps"
    case consistency     = "Consistency"
    case formQuality     = "Form Quality"
    case exerciseMastery = "Exercise Mastery"
    case volume          = "Volume Milestones"

    var id: String { rawValue }

    /// Display label used in section headers + the gallery sheet.
    var displayName: String { rawValue }

    /// Two-stop gradient that fills the badge medallion. Picked to be visually
    /// distinct between categories while staying within the dark-app palette.
    var gradient: LinearGradient {
        switch self {
        case .firstSteps:
            return LinearGradient(
                colors: [
                    Color(red: 0.36, green: 0.78, blue: 0.98),
                    Color(red: 0.20, green: 0.45, blue: 0.86)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .consistency:
            return LinearGradient(
                colors: [
                    Color(red: 1.00, green: 0.66, blue: 0.20),
                    Color(red: 0.90, green: 0.30, blue: 0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .formQuality:
            return LinearGradient(
                colors: [
                    Color(red: 0.67, green: 0.42, blue: 0.96),
                    Color(red: 0.34, green: 0.16, blue: 0.72)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .exerciseMastery:
            return LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.32, blue: 0.36),
                    Color(red: 0.62, green: 0.10, blue: 0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .volume:
            return LinearGradient(
                colors: [
                    Color(red: 1.00, green: 0.86, blue: 0.32),
                    Color(red: 0.78, green: 0.52, blue: 0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    /// Border + glow accent used around the medallion to lift it off the dark
    /// background. Matches the secondary stop of `gradient`.
    var accent: Color {
        switch self {
        case .firstSteps:      return Color(red: 0.36, green: 0.78, blue: 0.98)
        case .consistency:     return Color(red: 1.00, green: 0.66, blue: 0.20)
        case .formQuality:     return Color(red: 0.67, green: 0.42, blue: 0.96)
        case .exerciseMastery: return Color(red: 0.95, green: 0.32, blue: 0.36)
        case .volume:          return Color(red: 1.00, green: 0.86, blue: 0.32)
        }
    }
}

// MARK: - Badge

/// One earnable achievement. The `id` is the persistence key — never reuse
/// or rename one once shipped or earned badges will silently disappear.
struct Badge: Identifiable, Hashable {
    let id: String
    let title: String
    let tagline: String
    let category: BadgeCategory
    /// Primary SF Symbol drawn at the medallion's center.
    let symbol: String

    static func == (lhs: Badge, rhs: Badge) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Catalog

/// Single source of truth for every shipped badge. `BadgeCenter` references
/// these by id; UI code iterates `BadgeCatalog.all` to render gallery + earned
/// state. Adding a new badge here is enough to make it visible — the evaluator
/// just needs the matching unlock rule.
enum BadgeCatalog {

    // MARK: First Steps
    static let setCloser = Badge(
        id: "first.set_closer",
        title: "Set Closer",
        tagline: "Complete your first full set",
        category: .firstSteps,
        symbol: "checkmark.seal.fill"
    )
    static let profileComplete = Badge(
        id: "first.profile_complete",
        title: "Profile Complete",
        tagline: "Finish onboarding",
        category: .firstSteps,
        symbol: "person.crop.circle.fill.badge.checkmark"
    )

    // MARK: Consistency
    static let backForMore = Badge(
        id: "consistency.back_for_more",
        title: "Back for More",
        tagline: "Work out 2 days in a row",
        category: .consistency,
        symbol: "arrow.uturn.right.circle.fill"
    )
    static let weekOne = Badge(
        id: "consistency.week_one",
        title: "Week One",
        tagline: "Complete 3 workouts in your first 7 days",
        category: .consistency,
        symbol: "calendar.badge.checkmark"
    )
    static let streak7 = Badge(
        id: "consistency.streak_7",
        title: "Streak: 7",
        tagline: "7-day workout streak",
        category: .consistency,
        symbol: "flame.fill"
    )
    static let streak14 = Badge(
        id: "consistency.streak_14",
        title: "Streak: 14",
        tagline: "14-day workout streak",
        category: .consistency,
        symbol: "flame.fill"
    )
    static let streak30 = Badge(
        id: "consistency.streak_30",
        title: "Streak: 30",
        tagline: "30-day workout streak",
        category: .consistency,
        symbol: "flame.fill"
    )
    static let comeback = Badge(
        id: "consistency.comeback",
        title: "Comeback",
        tagline: "Return after 7+ days off and complete a session",
        category: .consistency,
        symbol: "arrow.counterclockwise.circle.fill"
    )
    static let monthlyRegular = Badge(
        id: "consistency.monthly_regular",
        title: "Monthly Regular",
        tagline: "12 workouts in a calendar month",
        category: .consistency,
        symbol: "calendar"
    )

    // MARK: Form Quality
    static let cleanSet = Badge(
        id: "form.clean_set",
        title: "Clean Set",
        tagline: "Every rep above 75% form score",
        category: .formQuality,
        symbol: "sparkles"
    )
    static let depthDemon = Badge(
        id: "form.depth_demon",
        title: "Depth Demon",
        tagline: "10 squats in one set hitting good depth",
        category: .formQuality,
        symbol: "arrow.down.to.line.compact"
    )
    static let kneesOut = Badge(
        id: "form.knees_out",
        title: "Knees Out",
        tagline: "Squat set with zero knee valgus flags",
        category: .formQuality,
        symbol: "arrow.left.and.right"
    )
    static let tallChest = Badge(
        id: "form.tall_chest",
        title: "Tall Chest",
        tagline: "Squat set with zero forward lean flags",
        category: .formQuality,
        symbol: "figure.stand"
    )
    static let tempoMaster = Badge(
        id: "form.tempo_master",
        title: "Tempo Master",
        tagline: "Set averaging 1.5+ seconds on the eccentric",
        category: .formQuality,
        symbol: "metronome.fill"
    )
    static let theStandard = Badge(
        id: "form.the_standard",
        title: "The Standard",
        tagline: "85%+ form across 50 reps of any exercise",
        category: .formQuality,
        symbol: "rosette"
    )

    // MARK: Exercise Mastery
    static let bodyweightBuilder = Badge(
        id: "mastery.bodyweight_builder",
        title: "Bodyweight Builder",
        tagline: "100 lifetime bodyweight squats",
        category: .exerciseMastery,
        symbol: "figure.strengthtraining.functional"
    )
    static let ironInitiate = Badge(
        id: "mastery.iron_initiate",
        title: "Iron Initiate",
        tagline: "50 lifetime barbell back squats",
        category: .exerciseMastery,
        symbol: "figure.strengthtraining.traditional"
    )
    static let ironVeteran = Badge(
        id: "mastery.iron_veteran",
        title: "Iron Veteran",
        tagline: "250 lifetime barbell back squats",
        category: .exerciseMastery,
        symbol: "shield.lefthalf.filled"
    )
    static let benchPressed = Badge(
        id: "mastery.bench_pressed",
        title: "Bench Pressed",
        tagline: "100 lifetime bench press reps",
        category: .exerciseMastery,
        symbol: "dumbbell.fill"
    )
    static let hipHingeHero = Badge(
        id: "mastery.hip_hinge_hero",
        title: "Hip Hinge Hero",
        tagline: "100 lifetime deadlifts or RDLs",
        category: .exerciseMastery,
        symbol: "arrow.up.and.down.righttriangle.up.righttriangle.down.fill"
    )
    static let rowBoss = Badge(
        id: "mastery.row_boss",
        title: "Row Boss",
        tagline: "100 lifetime barbell rows",
        category: .exerciseMastery,
        symbol: "arrow.left.to.line.compact"
    )
    static let sixPack = Badge(
        id: "mastery.six_pack",
        title: "Six-Pack",
        tagline: "Complete a set in all six tracked exercises",
        category: .exerciseMastery,
        symbol: "square.grid.3x2.fill"
    )

    // MARK: Volume
    static let club100 = Badge(
        id: "volume.club_100",
        title: "100 Club",
        tagline: "100 lifetime reps",
        category: .volume,
        symbol: "100.circle.fill"
    )
    static let club500 = Badge(
        id: "volume.club_500",
        title: "500 Club",
        tagline: "500 lifetime reps",
        category: .volume,
        symbol: "medal.fill"
    )
    static let club1000 = Badge(
        id: "volume.club_1000",
        title: "1,000 Club",
        tagline: "1,000 lifetime reps",
        category: .volume,
        symbol: "trophy.fill"
    )
    static let heavyHour = Badge(
        id: "volume.heavy_hour",
        title: "Heavy Hour",
        tagline: "60 cumulative minutes of tracked exercise",
        category: .volume,
        symbol: "stopwatch.fill"
    )

    /// Catalog ordering. Drives gallery layout — keep grouped by category and
    /// roughly easy → hard within a category so the user reads progress as
    /// natural escalation.
    static let all: [Badge] = [
        // First Steps
        setCloser, profileComplete,
        // Consistency
        backForMore, weekOne, streak7, streak14, streak30, comeback, monthlyRegular,
        // Form Quality
        cleanSet, depthDemon, kneesOut, tallChest, tempoMaster, theStandard,
        // Exercise Mastery
        bodyweightBuilder, ironInitiate, ironVeteran, benchPressed, hipHingeHero, rowBoss, sixPack,
        // Volume
        club100, club500, club1000, heavyHour
    ]

    static var byCategory: [(category: BadgeCategory, badges: [Badge])] {
        BadgeCategory.allCases.map { category in
            (category, all.filter { $0.category == category })
        }
    }
}
