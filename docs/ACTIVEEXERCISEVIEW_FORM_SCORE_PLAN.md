---
name: ActiveExerciseView Form Score Fix
overview: Ensure pose detection is working and the form score updates the circular ring UI for close-grip bench press in WorkoutActiveView. Fix blank UI if needed; wire real-time scoring from OnDevicePoseManager. Add smoothing and confidence gating as needed.
todos: []
isProject: false
---

# Pose Detection and Form Score Ring for Close-Grip Bench Press

## Scope and Target View

- **Target:** [WorkoutActiveView.swift](Chiron/Views/WorkoutActiveView.swift) — the view with the form score ring and close-grip bench press flow.
- **Goals:** (1) Pose detection working when on close-grip bench press. (2) Form score (1–100) updating the circular ring UI in real time.
- **Existing pieces:** [OnDevicePoseManager](Chiron/OnDevicePoseManager.swift) (singleton, `VNDetectHumanBodyPoseRequest`), [SharedCameraSessionManager](Chiron/Views/SharedCameraSessionManager.swift) (shared session → `poseManager.analyzeFrame`), form score ring in `formScoreIndicator` / `topNavigationBar`.

---

## Phase 1: Fix Blank UI So the View Renders

### 1.1 Diagnose Why the View Is Blank

**Likely causes (in order of check):**

1. **Overlay VStack has no explicit frame**  
The main overlay is a `VStack` (top nav + `Spacer` + bottom card) inside a `ZStack` with no `.frame`. In some layouts (e.g. certain presentation contexts) it can collapse or not fill the space.

- **Location:** [WorkoutActiveView.swift](Chiron/Views/WorkoutActiveView.swift) ~397–406 (overlay `VStack`).

2. **GeometryReader zero size**  
Using `GeometryReader` as the root can sometimes report zero size on first layout (e.g. in fullScreenCover / navigation), leading to empty content.

- **Location:** Body ~361–407.

3. **Background vs overlay**  
Background is either `CroppedDemoVideoHeader(workout.videoName)` or `Color.background`. If video fails or `videoName` is nil, fallback is `Color.background`. Overlay could still be missing if (1) or (2) apply.

### 1.2 Concrete Fixes (Do First)

1. **Give the overlay an explicit frame**

- Add `.frame(maxWidth: .infinity, maxHeight: .infinity)` to the overlay `VStack` (the one with `topNavigationBar`, `Spacer`, `bottomExerciseCard`) so it always fills the `ZStack`.

2. **Ensure GeometryReader cannot collapse**

- Add `.frame(minWidth: 1, minHeight: 1, maxWidth: .infinity, maxHeight: .infinity)` to the `GeometryReader` (or the `ZStack` inside it) so the view always receives non-zero size.

3. **Temporary debug UI**

- Add a debug `Color.blue.opacity(0.3)` background behind the overlay **or** a small `Text("ActiveExerciseView")` in a corner, gated by `#if DEBUG`, to confirm the view lifecycle and that the overlay is on screen.
- In `.onAppear`, `print` (or `os_log`) that `WorkoutActiveView` appeared.

4. **Verify lifecycle**

- Ensure `.onAppear` calls `startWorkout()` and that nothing prevents it (e.g. conditional navigation). Keep existing structure; only add logging.

---

## Phase 2: Pose Detection and Subscription

### 2.1 Current Architecture

- **Capture:** `SharedCameraSessionManager` holds the single `AVCaptureSession` and `AVCaptureVideoDataOutput`. Camera is started in Camera Setup (or when starting close-grip bench press).
- **Pose:** Frames go to `OnDevicePoseManager.analyzeFrame(_:)` via `SharedCameraSessionManager`'s `AVCaptureVideoDataOutputSampleBufferDelegate`. `OnDevicePoseManager` uses `VNDetectHumanBodyPoseRequest` and publishes `currentFormAnalysis: FormAnalysis?`.
- **WorkoutActiveView:** Already uses `@ObservedObject private var poseManager = OnDevicePoseManager.shared`. It therefore subscribes to pose-derived state via SwiftUI's `@Published` / `ObservableObject`.

### 2.2 What to Verify / Adjust

- **Pose subscription:** Ensure the form-score ring reads from `poseManager.currentFormAnalysis` (and any smoothed score you add). Confirm the view updates when `currentFormAnalysis` changes.
- **When pose runs:** For close-grip bench press, `startExercise()` calls `SharedCameraSessionManager.shared.switchToWorkoutMode()` and `startPoseAnalysis()`. Confirm this runs when navigating to the close-grip exercise (intro buffer, returning from Test View, etc.). Fix any missed code paths so pose detection is consistently on.

---

## Phase 3: Form Scorer and Ring UI

### 3.1 Current vs Required Behavior

- **Current:** `OnDevicePoseManager` produces `FormAnalysis` with `overallScore` in `0...1`. WorkoutActiveView maps it to 1–100 via `currentFormScore` and drives `formScoreIndicator` (ring) and `formScoreColor`.
- **Required:** Output 1–100; optional baseline penalties (joint angles, torso lean, asymmetry); clamping; smoothing; confidence gating.

### 3.2 Implementation Options

**Option A – Minimal (recommended first):**
Keep using `FormAnalysis.overallScore` as the main signal. In WorkoutActiveView (or a tiny helper):

- Map `overallScore` → 1–100 with `max(1, min(100, Int(overallScore * 100)))`.
- Add a **smoothed score** (e.g. exponential moving average, α ≈ 0.2, or rolling window of last 10 frames) and drive the ring from the smoothed value.
- **Confidence gating:** If `poseManager.poseDetected == false` or a simple "pose confidence" (e.g. derived from `currentFormAnalysis` or a new lightweight confidence flag) is below a threshold, either **freeze** the last score or **slowly decay** it (e.g. blend toward a default like 70) instead of updating from new analysis.
- Update the ring at ~5–10 Hz (e.g. via a `Timer` or `DispatchQueue.asyncAfter` throttle), not every frame.

**Option B – Extend OnDevicePoseManager:**
Add a small "baseline" form scorer inside `OnDevicePoseManager` that:

- Consumes existing joint data from the MediaPipe pipeline (OnDevicePoseManager form analysis; see docs/POSE_PIPELINE_MEDIAPIPE.md).
- Applies simple penalties (e.g. knee/hip/elbow deviation, torso lean, L/R asymmetry), starts at 100, clamps 1–100.
- Exposes a `@Published` form score (1–100) used by WorkoutActiveView. Smoothing and gating can live here or in the view.

Start with **Option A** to get a stable, believable score quickly; introduce Option B only if you need a more structured, penalty-based baseline.

### 3.3 Ring UI (Already Present)

- **Location:** `formScoreIndicator` in [WorkoutActiveView.swift](Chiron/Views/WorkoutActiveView.swift) ~595–630.
- **Behavior:** Fill proportional to score; colors: 1–59 red, 60–74 yellow, 75–89 green, 90–100 emerald. Use the **smoothed** score for the ring.
- **Animation:** Short ease (e.g. `.animation(.easeInOut(duration: 0.2), value: smoothedScore)`) to avoid jitter. Reduce update rate to 5–10 Hz as above.

---

## Phase 4: Smoothing and Confidence Gating

- **Smoothing:** EMA (α ≈ 0.2) or last‑10 rolling average. Store last N raw scores or a single EMA state; compute smoothed value and feed it to the ring.
- **Confidence gating:**  
- If `!poseManager.poseDetected` or confidence < threshold: **freeze** last displayed score or **decay** toward a neutral value over a few seconds.  
- Only apply new `currentFormAnalysis` updates when confidence is above threshold.
- **Update rate:** Throttle UI updates to ~5–10 Hz (e.g. `Timer` every 0.1–0.2 s) so the ring doesn't flicker.

---

## Phase 5: Debug Helpers and Logging

- **DEBUG-only:**
- Small `Text("\(currentFormScore)")` or `Text("\(smoothedScore)")` (and optionally `poseManager.poseDetected` or confidence) in a corner.
- Temporary background or debug overlay only when `#if DEBUG`.
- **Logging:**
- `WorkoutActiveView` appeared (`.onAppear`).
- When pose frames are received (e.g. in `SharedCameraSessionManager` delegate or `OnDevicePoseManager.analyzeFrame` — throttle logs to avoid spam).
- When the displayed form score updates (throttled).
- Remove or disable these once the flow is validated.

---

## Phase 6: Cleanup

- Remove debug background, debug `Text`, and verbose logging.
- Keep any structural fixes (frame, GeometryReader) and the smoothing/gating logic.

---

## Implementation Order (Summary)

1. **Fix blank UI:** Explicit overlay frame, GeometryReader min size, debug background/text, `.onAppear` log. Confirm the view renders.
2. **Confirm lifecycle:** Ensure `startWorkout` → `startExercise` (for close-grip) runs and that pose analysis starts.
3. **Pose subscription:** Confirm WorkoutActiveView updates from `poseManager.currentFormAnalysis`.
4. **Form scorer + ring:** Use `overallScore` → 1–100, add smoothed score, drive ring + colors from it; throttle updates to 5–10 Hz.
5. **Smoothing + gating:** EMA or rolling window; freeze/decay when confidence low.
6. **Debug:** Add DEBUG-only UI and logging; remove after validation.

---

## Acceptance Criteria (Recap)

- Navigating to WorkoutActiveView (active exercise) shows UI immediately (nav bar, bottom card, form ring when on close-grip).
- **Pose detection is working** when on close-grip bench press (frames flowing, `currentFormAnalysis` updating).
- **Form score ring is visible and updates** with user movement when pose is available.
- When pose drops, score freezes or decays gracefully.
- No noticeable performance impact; updates at ~5–10 Hz.

---

## Files to Touch

| File | Changes |
|------|---------|
| [WorkoutActiveView.swift](Chiron/Views/WorkoutActiveView.swift) | Overlay frame, GeometryReader min frame, debug UI/logging, smoothed score state, throttle, confidence gating, ring driven by smoothed score |
| [OnDevicePoseManager.swift](Chiron/OnDevicePoseManager.swift) | Optional: lightweight "pose confidence" or use existing `poseDetected`; optional baseline scorer (Option B) |
| [SharedCameraSessionManager.swift](Chiron/Views/SharedCameraSessionManager.swift) | Optional: throttled logging when forwarding frames to pose |

---

## Notes

- **WorkoutIntroView** uses a similar active layout (`activeWorkoutContent`) but has **no** form score or close-grip pose logic. The spec targets the form score flow, which lives in WorkoutActiveView. If you later add form scoring to WorkoutIntroView, reuse the same pose subscription and scoring approach.
- **Do not over-engineer:** Use existing `FormAnalysis.overallScore` and add minimal smoothing/gating first. Extend with penalty-based rules only if needed.
