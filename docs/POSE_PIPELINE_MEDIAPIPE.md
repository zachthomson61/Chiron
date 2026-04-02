# Pose Pipeline: MediaPipe (Active) vs Apple Vision (Legacy)

## Active pipeline: MediaPipe

All **live** pose detection and form analysis use **MediaPipe Pose Landmarker**:

1. **Input:** Camera frames via `SharedCameraSessionManager` → `OnDevicePoseManager.analyzeFrame(pixelBuffer)`.
2. **Detection:** `PoseLandmarker` (MediaPipeTasksVision) runs on-device; outputs `PoseLandmarkerResult` with:
   - **World landmarks** (33 points, metric space, hip-centered) → used for **form metrics**.
   - **Image landmarks** (33 points, normalized 0–1) → used for **overlay / UI**.
3. **Adapter:** `MediaPipePoseAdapter` maps MediaPipe indices to app joint names and builds:
   - **Skeleton3D** from world landmarks (for depth, back angle, knee alignment, etc.).
   - **Overlay landmarks** `[String: CGPoint]` from image landmarks (for skeleton overlay).
4. **Form analysis:** `OnDevicePoseManager.formAnalysisFrom3D(skeleton:)` (and bodyweight rep-history aggregation) uses **only 3D skeleton** from world landmarks. No Apple Vision types are involved.

**Coordinate systems:**

- **World (3D):** MediaPipe world landmarks; used for squat depth (knee angle), back angle, knee alignment. Origin and scale are model-defined (hip-centered, metric).
- **Overlay (2D):** Normalized image coordinates 0–1, origin top-left, Y down. Same convention as typical image space; used for drawing the skeleton on the camera preview.

## Legacy: Apple Vision

**`PoseDetectionManager`** uses `VNDetectHumanBodyPoseRequest` (Apple Vision) and produces `PoseDetectionResults` with `VNHumanBodyPoseObservation.JointName` keypoints. It is **not** wired into the current camera path: nothing sets `PoseDetectionManager.delegate`, and `SharedCameraSessionManager` only calls `OnDevicePoseManager.analyzeFrame`. The Vision-based flow (squat form, rep counting, form feedback) is **legacy**. `WorkoutViewModel` still conforms to `PoseDetectionDelegate`, but that delegate is never attached to a Vision pipeline in the app.

## Updating analysis to MediaPipe

- **Form metrics (squats, bench):** Already on MediaPipe. Implemented in `OnDevicePoseManager` using `Skeleton3D` from `MediaPipePoseAdapter` (world landmarks). See:
  - `calculateMovementDepthScore3D`, `calculateBackAngle3D`, `calculateKneeAlignment3D`
  - `analyzeBodyweightSquatFromRepHistory` for bodyweight rep-level aggregation
  - `analyzeCloseGripBenchPressForm3D` for bench
- **Overlay / UI:** Uses `currentNormalizedLandmarks` from the adapter’s **image** landmarks (same keys: `leftShoulder`, `leftHip`, etc.). Skeleton edges in `SharedCameraSessionManager` use these keys.
- **Comments:** Any remaining “Vision” references in the codebase refer to the **coordinate convention** (normalized 0–1, Y down), which matches MediaPipe’s image landmarks; the logic is MediaPipe-based.

To add or change form analysis, use the **3D skeleton** and the helpers in `OnDevicePoseManager`; do not rely on `PoseDetectionManager` or Vision types for the live path.

## Lower body tracking

MediaPipe can lag or mis-estimate hip/knee positions when the lower body is occluded or at extreme angles. To get more accurate lower body tracking:

- **Camera angle:** A **side or 3/4 view** (phone to the side of the user) keeps hips and knees visible. Straight-on (front) views often occlude the hips when squatting deep, so the overlay and rep logic may not show hips going below knees even when they do in real life.
- **Smoothing:** The app uses a joint smoother (3D) and landmark smoother (2D overlay) with higher alpha so lower body updates faster; if the overlay still lags, consider reducing smoothing further in `OnDevicePoseManager` (e.g. `JointSmoother` alpha, `Landmark2DSmoother` alphaWhenMoving).
- **Confidence:** `minPosePresenceConfidence` and `minTrackingConfidence` are set to 0.4 so frames are not dropped when the model is less confident in deep squat positions.
- **Heavy model (optional):** MediaPipe provides a “heavy” pose model (e.g. `pose_landmarker_heavy.task`) that can be more accurate than the default “full” model, at the cost of more CPU. If you add the heavy `.task` to the bundle and point `modelAssetPath` at it in `setupMediaPipe()`, detection may improve for difficult poses.
