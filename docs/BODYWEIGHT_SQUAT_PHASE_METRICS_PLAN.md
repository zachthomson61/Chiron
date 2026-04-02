# Bodyweight Squat: Phase-Relevant Metrics and Rep-Level Aggregation (Refactored)

## Problem

Bodyweight squat form currently uses instantaneous frame metrics. Depth is a **bottom-position** problem; knee valgus matters near the sticking point; back angle matters in specific phases. We need explicit per-rep metric capture, set-level aggregation that avoids brittle worst-case behavior, and a design that is easier to calibrate and debug—without overengineering.

## Scope

**Bodyweight squats only.** Barbell and other exercises unchanged. **Rep detection logic is unchanged.** No cloud or LLM dependency. Changes are localized to the bodyweight squat path.

---

## 1. Rep Metrics Structure (Minimal but Sufficient)

Replace any minimal rep struct with the following. Define in [OnDevicePoseManager.swift](Chiron/OnDevicePoseManager.swift) (or a dedicated types file):

```swift
struct BodyweightRepMetrics {
    let depthAtBottom: Float
    let backAngleMax: Float
    let kneeAlignmentWorstNearBottom: Float

    let shallowDepth: Bool
    let excessiveForwardLean: Bool
    let kneeValgus: Bool

    let valid: Bool
    let timestamp: TimeInterval
}
```

- **Boolean issue flags** (`shallowDepth`, `excessiveForwardLean`, `kneeValgus`): Set per rep using contract thresholds. Enables aggregation by “how many reps had this issue” instead of re-deriving from raw numbers.
- **valid**: True only when the rep passes validity checks (see §4). Invalid reps are discarded and not appended to history.
- **timestamp**: Rep completion time for ordering, debugging, and future extensibility (e.g. fatigue patterns).

---

## 2. Optionals for Current-Rep Accumulation (No Sentinel Defaults)

Do **not** use numeric defaults like `0` or `1` for min/max tracking.

```swift
private var currentRepBackAngleMax: Float?
private var currentRepKneeAlignmentWorst: Float?
```

- **Initialization**: Set on first valid frame in the appropriate phase (e.g. first frame when `depth > 0.35` for knee; first frame in rep for back angle).
- **Update**: Then apply `max` / `min` only when the optional is set or when the new value is more extreme.
- **Reset**: Set to `nil` on rep completion so the next rep starts clean.

Depth continues to use existing `currentRepBottomDepthMax` (already reset on rep completion).

---

## 3. Explicit Rep Phase (Lightweight State Machine)

Do **not** rely on vague “in a rep” logic. Introduce a minimal internal state:

```swift
enum RepPhase {
    case idle
    case descendingOrBottom
    case ascending
}
```

- **Transitions**: Drive with depth thresholds and existing `reachedDeepThisCycle` and rep-completion signal (e.g. when `validateSquatRep` returns true).
- **idle**: Before first “deep” in the cycle or after rep completion.
- **descendingOrBottom**: From first frame meeting deep threshold until we leave deep (start of ascent).
- **ascending**: From leaving deep until rep completion (consecutive shallow).

Use `RepPhase` to:

- Gate accumulation of back angle (only in `.descendingOrBottom` or `.ascending`, not `.idle`).
- Prevent pre-rep noise from affecting metrics.

Knee accumulation remains gated by depth only: accumulate min when `depth > 0.35`.

---

## 4. Rep Validity Filtering

Before appending to `bodyweightRepHistory`, validate the rep. Only append if:

- Depth exceeded a minimum viable threshold (e.g. we actually entered “bottom”).
- Enough frames contributed to the rep (e.g. minimum frame count in rep).
- Knee window (`depth > 0.35`) had at least one sample (so `kneeAlignmentWorstNearBottom` is meaningful).

If not valid: **discard the rep entirely** (do not append). This prevents noisy detections from corrupting set-level feedback.

When building `BodyweightRepMetrics`, set `valid: Bool` from this check; only append when `valid == true`.

---

## 5. Per-Frame Accumulation Rules

Keep logic simple and phase-relevant.

| Metric | When to accumulate | Rule |
|--------|--------------------|------|
| **Depth** | Existing logic | Continue using `currentRepBottomDepthMax` (updated in `updateTempoTracking` or equivalent). |
| **Back angle** | Only during rep phases (not idle) | When `RepPhase != .idle`, update `currentRepBackAngleMax`: initialize to `backAngle` if `nil`, else `max(currentRepBackAngleMax!, backAngle)`. |
| **Knee alignment** | Only when `depth > 0.35` | Update `currentRepKneeAlignmentWorst`: initialize to `kneeAlignment` if `nil`, else `min(currentRepKneeAlignmentWorst!, kneeAlignment)`. |

Reset both optionals to `nil` on rep completion.

---

## 6. Set-Level Aggregation (Recurring Patterns, Not Pure Worst-Case)

Do **not** use “worst depth from rep 1, worst knee from rep 3, worst lean from rep 5” as one synthetic rep. Base issues on **recurring patterns**; summary should reflect **consistency across reps**.

**Depth**

- Use **min depth across valid reps** (one shallow rep can matter for “some reps lacked depth”).
- Set-level “depth” for scoring/display: e.g. `min(validReps.map(\.depthAtBottom))` when building aggregated analysis.

**Knee valgus**

- Flag **only if**:
  - It occurs in **≥ 2 reps**, OR
  - It occurs in **≥ 25% of valid reps**.
- Prevents a single noisy rep from driving the issue.

**Back angle (excessive forward lean)**

- Flag **only if**:
  - It occurs in **≥ 2 reps**, OR
  - An **upper percentile** (e.g. 75th or 90th) of `backAngleMax` across valid reps exceeds threshold.
- Same idea: avoid one-off noise driving the issue.

Implement this inside a dedicated aggregation function (§7). Do not overload `formAnalysisFrom3D`.

---

## 7. Separate Aggregated Analysis Function

Do **not** overload `formAnalysisFrom3D` with bodyweight rep-history logic.

Add a new function:

```swift
func analyzeBodyweightSquatFromRepHistory(
    repHistory: [BodyweightRepMetrics],
    fallback: FrameMetrics
) -> FormAnalysis
```

**Responsibilities:**

- Take only **valid** reps (or filter by `valid` inside).
- Apply the set-level aggregation rules (§6): depth = min of valid rep depths; knee/back issues only when recurring (≥2 reps or ≥25% / percentile).
- Compute issue flags and any summary inputs from these aggregated results.
- **Fallback**: If no valid reps exist, return a `FormAnalysis` built from `fallback` (current-frame metrics) so the UI and pipeline always have a result.

Call this from the bodyweight branch of the form-analysis path when `trackedExerciseType == .bodyweight`: if `bodyweightRepHistory.isEmpty` or no valid reps, pass current-frame metrics as `fallback` and use them; otherwise pass `bodyweightRepHistory` and the same fallback for safety.

---

## 8. Avoid Synthetic “Impossible Rep” Summaries

Do **not** combine worst depth from one rep, worst knee from another, worst lean from a third and treat as one rep for messaging.

**Do:**

- Base issues on **recurring patterns** (e.g. “shallow depth in multiple reps”, “knees caved in ≥2 reps”).
- Let summary reflect **consistency** (e.g. “some reps lacked depth and knees caved near the bottom” when both patterns hold).

**Do not:**

- Output a single “your squat had shallow depth, knee cave, and excessive lean” unless those issues co-occur in at least 2 reps or meet the percentage/percentile rules above.

---

## 9. Store Rep-Level Issue Flags

Each `BodyweightRepMetrics` stores:

- `shallowDepth: Bool`
- `excessiveForwardLean: Bool`
- `kneeValgus: Bool`

Set these when the rep is committed using the same contract thresholds (e.g. `depthAtBottom < depthShallow`, `backAngleMax > forwardLean`, `kneeAlignmentWorstNearBottom < kneeValgus`). This simplifies aggregation (count reps with each flag), debugging, and future scoring.

---

## 10. Lightweight Instrumentation

Log per-rep data when a rep is committed (before append/discard), for debugging and tuning:

- Rep index (or “rep N of set”)
- `depthAtBottom`
- `backAngleMax`
- `kneeAlignmentWorstNearBottom`
- `valid`
- Issue flags: `shallowDepth`, `excessiveForwardLean`, `kneeValgus`

Use `print` or a simple logger; no cloud. Required for tuning thresholds later.

---

## 11. UI Behavior

- **User-facing UI**: Continue **hiding rep count** for bodyweight squats (BodyweightSquatActiveWorkoutView, TrackView pipeline card, etc.). Show “—” or omit.
- **Internal and debug**: Do **not** remove rep count from internal logic or from debug views (e.g. PoseMetricsView, SharedCameraSessionManager overlay). Rep count remains available for logic and debugging.

---

## Constraints (Recap)

- **Rep detection**: Unchanged.
- **Cloud / LLM**: No new dependency.
- **Phase segmentation**: Minimal—only `RepPhase` and depth gate for knee; no overengineering.
- **Scope**: Bodyweight squat path only.

---

## Files to Touch

| File | Changes |
|------|--------|
| [OnDevicePoseManager.swift](Chiron/OnDevicePoseManager.swift) | Add `RepPhase`, `BodyweightRepMetrics` (with issue flags, `valid`, `timestamp`). Add `bodyweightRepHistory`, optional `currentRepBackAngleMax` and `currentRepKneeAlignmentWorst`. Implement phase transitions; per-frame accumulation rules; rep validity check; on rep completion build `BodyweightRepMetrics` (with flags and `valid`), log instrumentation, append only if valid, reset optionals and phase. Add `analyzeBodyweightSquatFromRepHistory(repHistory:fallback:)` with aggregation rules (§6). Bodyweight branch in form-analysis path calls this with `bodyweightRepHistory` and current-frame fallback. Clear history and state in `handleSetStart`. |
| [BodyweightSquatActiveWorkoutView.swift](Chiron/Views/BodyweightSquatActiveWorkoutView.swift) | Hide rep count in user-facing status (e.g. “Set X” only, or “Rep —”). |
| [TrackView.swift](Chiron/Views/TrackView.swift) | Pipeline status card: do not show rep count for bodyweight (or “—”) in user-facing text. |
| [SharedCameraSessionManager.swift](Chiron/Views/SharedCameraSessionManager.swift) | Keep rep count in debug overlay; optionally show “Reps: —” for bodyweight in a user-facing variant if the overlay is user-visible, or leave as-is for debug. |
| [PoseMetricsView.swift](Chiron/Views/PoseMetricsView.swift) | Keep rep count visible (debug view). For bodyweight can show “Reps: N (internal)” or leave numeric. |

---

## Summary

- **BodyweightRepMetrics**: depth, backAngleMax, kneeAlignmentWorstNearBottom; booleans `shallowDepth`, `excessiveForwardLean`, `kneeValgus`; `valid`; `timestamp`.
- **Optionals** for current-rep back angle and knee; no sentinel defaults.
- **RepPhase** (idle / descendingOrBottom / ascending) gates accumulation and avoids pre-rep noise.
- **Rep validity**: only append valid reps; discard invalid.
- **Set-level aggregation**: depth = min(valid reps); knee/back issues only when ≥2 reps or ≥25%/percentile; no synthetic “impossible” single-rep combo.
- **analyzeBodyweightSquatFromRepHistory(repHistory:fallback:)** owns aggregation and fallback; `formAnalysisFrom3D` is not overloaded.
- **Instrumentation**: log per-rep metrics and flags for calibration.
- **UI**: hide rep count for bodyweight in user-facing screens; keep in internal/debug.
