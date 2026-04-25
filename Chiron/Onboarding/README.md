# Chiron Onboarding

Self-contained first-time-user onboarding module. Produces a `ChironUserProfile`
that downstream systems (coaching layer, training log, future multi-agent coach)
read from.

## Flow Order

| # | Step | View | Notes |
|---|---|---|---|
| 1 | Welcome | `WelcomeStepView` | Brand moment, hero subtitle, single "Get Started" CTA. No progress bar. |
| 2 | Top goal | `GoalStepView` | Single-select with icons. |
| 3 | Experience level | `ExperienceStepView` | Gates coaching aggression downstream. |
| 4 | Birth year | `AgeStepView` | Wheel picker, Cal AI style. |
| 5 | Height + weight | `HeightWeightStepView` | Dual wheel picker with Imperial/Metric toggle. Metric is authoritative; imperial is display. |
| 6 | Injury concerns | `InjuriesStepView` | Multi-select; "None" is mutually exclusive. |
| 7 | Coach interstitial | `CoachInterstitialView` | Storytelling beat, no options (Opal pattern). |
| 8 | Coach persona | `CoachPersonaStepView` | Four persona cards. |
| 9 | Coach intensity | `CoachIntensityStepView` | 1–5 slider with live-morphing cue text. |
| 10 | Calculating | `CalculatingLoaderView` | Minimum 2.4s dwell. Auto-advances. |
| 11 | Reveal | `PersonalizedRevealView` | Gradient hero number derived from inputs. |
| 12 | Notification primer | `NotificationPrimerView` | Custom primer, then the system prompt. Decline still advances. |
| 13 | Ready | `ReadyStepView` | Summary card stack. "Start My First Session" persists and fires `onFinish`. |

`OnboardingStep` (in `ChironOnboardingCoordinator.swift`) is the source of truth for
ordering — its `rawValue` is the progress-bar segment index. Adding a step is a
single enum case plus a routing entry in `OnboardingRootView`.

## Architecture

```
Onboarding/
├── OnboardingRootView.swift       # Entry point. Embed at app launch when no profile exists.
├── ChironOnboardingCoordinator.swift    # @Observable, owns step + draft. Steps @Bindable into it.
├── Models/
│   ├── ChironUserProfile.swift
│   ├── OnboardingEnums.swift      # FitnessGoal, ExperienceLevel, UnitSystem, InjuryArea,
│   │                              # CoachPersona, CoachIntensityLevel,
│   │                              # + TrackedExerciseType Codable/CaseIterable shim
│   └── UserProfileStore.swift     # Protocol + UserDefaults-backed default + in-memory stub
├── DesignSystem/
│   ├── OnboardingTheme.swift
│   ├── OnboardingTypography.swift
│   ├── OnboardingScreenScaffold.swift
│   ├── OnboardingTopBar.swift
│   ├── OnboardingOptionRow.swift
│   └── PrimaryCTAButton.swift
└── Steps/                          # One file per step.
```

Steps are independent — no step reads another step's state. They only mutate
fields on `coordinator.draft` and check `coordinator.canAdvance`.

## UserProfile Schema

Named `ChironUserProfile` to avoid collision with the existing
`Models/UserProfile.swift` (a display-layer mock for `ProfileView`). The existing
struct should eventually be retired and its call sites migrated to
`ChironUserProfile`; that work is out of scope for the MVP.

```swift
struct ChironUserProfile: Codable, Equatable {
    var topGoal: FitnessGoal
    var experienceLevel: ExperienceLevel
    var birthYear: Int
    var heightCm: Double            // metric source of truth
    var weightKg: Double            // metric source of truth
    var preferredUnits: UnitSystem  // display only
    var trackedExercises: Set<TrackedExerciseType>
    var injuryFlags: Set<InjuryArea>
    var coachPersona: CoachPersona
    var coachIntensity: Int         // 1...5, clamped in init
    var createdAt: Date
    var schemaVersion: Int          // starts at 1
}
```

### Schema versioning

`schemaVersion` starts at 1. Bump `ChironUserProfile.currentSchemaVersion` on
non-additive changes and add a migration path in `UserDefaultsUserProfileStore`.

### TrackedExerciseType

Lives in `OnDevicePoseManager.swift`. The onboarding layer does **not** extend it
with new cases — all six MVP exercises are already present. It does add
`Codable`, `Hashable`, `CaseIterable` conformance via an extension in
`OnboardingEnums.swift`. Adding a new case to the source enum requires adding it
to the `allCases` array in that extension; the exhaustive switch over
`storageKey`/`displayName` will flag drift at compile time.

## Wiring into the app

In `ContentView.swift` (or wherever the app root chooses between onboarding and
the main tab view):

```swift
struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var profileStore = UserDefaultsUserProfileStore()
    @State private var hasProfile: Bool = UserDefaultsUserProfileStore().hasCompletedOnboarding

    var body: some View {
        if hasProfile {
            RootTabView()
                .environmentObject(appState.planStore)
                .modelContainer(appState.modelContainer)
        } else {
            OnboardingRootView(store: profileStore) { _ in
                hasProfile = true
            }
        }
    }
}
```

The existing `ContentView` uses `@AppStorage("has_completed_onboarding")` to
gate a legacy onboarding flow in `Features/Onboarding/`. When swapping to this
module, either:

1. Replace `OnboardingFlowView()` with `OnboardingRootView(...)` and keep the
   existing `@AppStorage` flag, calling the `onFinish` closure to set it.
2. Or delete `Features/Onboarding/` and use `UserDefaultsUserProfileStore.hasCompletedOnboarding`
   as the gate — the store writes the completion flag automatically on `save`.

Option 2 is cleaner; option 1 is safer mid-migration.

## Engagement Patterns

Four required patterns are implemented:

1. **Coach intensity slider with live-morphing cue text** —
   `CoachIntensityStepView`. The cue text view uses `.id(currentLevel)` so
   SwiftUI tears it down and replaces it, triggering the cross-fade transition.
2. **Storytelling interstitial** — `CoachInterstitialView`. Three staggered
   text lines, no options, single Continue.
3. **Gradient hero reveal** — `PersonalizedRevealView` uses
   `OnboardingTypography.heroNumber` (72pt New York serif with the accent
   gradient as foreground).
4. **Minimum-2.4s calculating loader** — `CalculatingLoaderView` holds for
   `minimumDwell` regardless of how fast the underlying work completes.

## Design System

- **Canvas:** `#0E0E10` warm off-black.
- **Surface:** `#1A1A1D`.
- **Stroke (unselected):** `#2A2A2F`.
- **Text:** white primary, `#9A9AA2` secondary.
- **Accent gradient:** `#7B61FF → #4FA8FF`.
- **Typography:** SF Pro throughout, New York serif 72pt for the hero number only.
- **Motion:** `.spring(response: 0.35, dampingFraction: 0.75)` for selection; screen transitions are horizontal slide + fade.
- **Haptics:** `.selection` on option tap, `.success` on CTA fire.

All primitives live in `DesignSystem/` and are reusable outside onboarding — the
theme and typography enums are deliberately not namespaced to onboarding state.

## Testing

Each step view has at least one SwiftUI `#Preview` with realistic mock state.
For headless testing, drive the coordinator with `InMemoryUserProfileStore`:

```swift
let coordinator = ChironOnboardingCoordinator(store: InMemoryUserProfileStore())
coordinator.draft.topGoal = .getStronger
// ...
XCTAssertTrue(coordinator.canAdvance)
```

## Adding to the Xcode project

The files are laid out on disk but still need to be added to the `Chiron`
target in `Chiron.xcodeproj`. In Xcode: right-click the project navigator →
"Add Files to Chiron…" → select `Chiron/Onboarding` → check
"Create groups" + the `Chiron` target. No other settings changes required —
everything uses only SwiftUI, Foundation, UIKit (for haptics), and
UserNotifications.
