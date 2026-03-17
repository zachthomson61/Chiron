# MediaPipe On-Device Integration Guide

Step-by-step instructions to get the MediaPipe pose pipeline running in Chiron. Follow in order.

---

## Prerequisites

- **Xcode 16+** (or latest stable)
- **CocoaPods 1.12+**  
  Check: `pod --version`  
  Install if needed: `sudo gem install cocoapods`
- **Ruby** (macOS ships with one; CocoaPods uses it)
- **Network access** to download the model and pods

---

## 1. Install CocoaPods dependencies

From the **project root** (the folder that contains `Podfile` and `Chiron.xcodeproj`):

```bash
cd /path/to/Chiron
pod install
```

- This creates **`Chiron.xcworkspace`** in the same directory and installs the `MediaPipeTasksVision` pod.
- If you see errors about Ruby or permissions, use:  
  `gem install cocoapods --user-install`  
  and ensure your shell `PATH` includes the user gem bin path.

**Important:** From now on, **always open `Chiron.xcworkspace`** (not `Chiron.xcodeproj`) when working in Xcode. The workspace includes both the app target and the Pods; building the project alone will not link MediaPipe.

---

## 2. Download the Pose Landmarker model

From the project root:

```bash
./download_pose_model.sh
```

- This downloads **`pose_landmarker_full.task`** into `Chiron/Models/MediaPipe/`.
- If the file is already there, the script exits without re-downloading.
- If `curl` fails (e.g. network), run again or download manually from:  
  `https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_full/float16/latest/pose_landmarker_full.task`  
  and place it at **`Chiron/Models/MediaPipe/pose_landmarker_full.task`**.

---

## 3. Add the model to the app bundle in Xcode

The app loads the model at runtime with:

```swift
Bundle.main.path(forResource: "pose_landmarker_full", ofType: "task")
```

So the `.task` file **must** be in the app bundle (Copy Bundle Resources).

**Option A – Project uses a synchronized “Chiron” folder (file system group):**

1. Open **Chiron.xcworkspace** in Xcode.
2. In the Project Navigator, find **Chiron** (the app source folder).
3. Confirm **`Chiron/Models/MediaPipe/pose_landmarker_full.task`** appears under Chiron (it will if you ran the download script and the folder is synced).
4. Select the **Chiron** target → **Build Phases** → **Copy Bundle Resources**.
5. If **`pose_landmarker_full.task`** is not in the list, click **+**, add **`Chiron/Models/MediaPipe/pose_landmarker_full.task`**, and leave **Copy items if needed** unchecked (file already lives in the project).
6. Ensure the `.task` file is **only** in **Copy Bundle Resources** (not in **Compile Sources**).

**Option B – Manual add:**

1. In Finder, ensure the file exists at **`Chiron/Models/MediaPipe/pose_landmarker_full.task`**.
2. In Xcode (with **Chiron.xcworkspace** open), right‑click the **Chiron** group (or **Models/MediaPipe** if you have it) → **Add Files to "Chiron"…**.
3. Select **`pose_landmarker_full.task`**.
4. Leave **Copy items if needed** unchecked if the file is already under the project directory.
5. **Add to targets:** check **Chiron** only.
6. Click **Add**.
7. Select the **Chiron** target → **Build Phases** → **Copy Bundle Resources**.
8. If the file is missing from the list, click **+** and add **`pose_landmarker_full.task`**.

---

## 4. Confirm new source files are in the target

The refactor adds these Swift files under **Chiron/**:

- `MediaPipePoseAdapter.swift`
- `PoseMetricsCollector.swift`
- `LandmarkRecorder.swift`
- `VideoTestRunner.swift`
- `Views/DebugPoseOverlay.swift`
- `Views/PoseMetricsView.swift`
- `Views/VideoTestRunnerView.swift`

If your project uses a **synchronized root group** for the Chiron folder (e.g. **PBXFileSystemSynchronizedRootGroup**), these files are included automatically as long as they are on disk under **Chiron/**.

Otherwise, add any missing file manually:

1. Right‑click the appropriate group in the Project Navigator → **Add Files to "Chiron"…**.
2. Select the `.swift` file(s).
3. Ensure **Chiron** is checked under **Add to targets**.

---

## 5. Build and fix common issues

1. In Xcode, select the **Chiron** scheme and a **real device or simulator** (iOS 16+).
2. **Product → Build** (⌘B).

**If you see “No such module 'MediaPipeTasksVision'”:**

- You are likely opening **Chiron.xcodeproj** instead of **Chiron.xcworkspace**. Close Xcode, open **Chiron.xcworkspace**, and build again.
- Run **`pod install`** again from the project root and then open **Chiron.xcworkspace**.

**If the model is not found at runtime (console: "pose_landmarker_full.task not found"):**

- Confirm **`pose_landmarker_full.task`** is listed in **Chiron** target → **Build Phases** → **Copy Bundle Resources**.
- Do a **Clean Build Folder** (⇧⌘K), then build and run again.

**If a Pod or script fails (e.g. code signing or sandboxing):**

- In **Build Settings** for the **Chiron** target, you can try **User Script Sandboxing** = **No** if a pod script phase requires it (use only if necessary).

---

## 6. Run on a device

1. Connect an **iPhone/iPad** (or use a simulator; camera features need a device for live pose).
2. Select the **Chiron** scheme and your device.
3. **Product → Run** (⌘R).
4. Grant camera permission when prompted.
5. Go to an exercise that uses the camera (e.g. bodyweight squat); the overlay and rep count should be driven by MediaPipe on-device.

---

## 7. (Optional) Pose metrics and debug overlay

- **Settings → Developer → Pose Metrics**  
  View dropped frames, inference latency, jitter, rep count; toggle landmark recording and **Show debug overlay**.
- **Settings → Developer → Video Test Runner**  
  Run test videos (once they are added) and see per-video results and saved JSON.

---

## 8. (Optional) Add test videos for validation

To use **Video Test Runner** with fixed clips:

1. Add short **.mp4** clips (about 10–30 s, 3–5 clear reps) and name them:
   - `test_squat.mp4`
   - `test_deadlift.mp4`
   - `test_bench.mp4`
   - `test_row.mp4`
2. Place them in **`Chiron/TestVideos/`** (or another folder under the project).
3. In Xcode, add each file to the project (**Add Files to "Chiron"…**) and ensure they are in the **Chiron** target’s **Copy Bundle Resources** (so they are in the app bundle).
4. In **VideoTestRunner.swift**, the code loads them with  
   `Bundle.main.path(forResource: name, ofType: "mp4")`  
   so the names must match exactly (e.g. `test_squat`, `test_deadlift`, etc.) and they must be in the bundle.

See **`Chiron/TestVideos/README.md`** for recording guidelines.

---

## 9. Checklist summary

| Step | Action |
|------|--------|
| 1 | Run **`pod install`** in project root. |
| 2 | Run **`./download_pose_model.sh`**. |
| 3 | Open **Chiron.xcworkspace** (not the .xcodeproj). |
| 4 | Add **`pose_landmarker_full.task`** to **Copy Bundle Resources** for the Chiron target. |
| 5 | Ensure all new Swift files under Chiron/ are in the Chiron target (automatic if using a synced folder). |
| 6 | Build (⌘B) and fix any “No such module” or missing-model issues. |
| 7 | Run on a device (⌘R), grant camera, and verify pose overlay and reps. |
| 8 | (Optional) Add test videos to the target and use Pose Metrics / Video Test Runner. |

---

## Troubleshooting

- **Overlay never appears after launch**  
  Model may not be in the bundle. Re-check **Copy Bundle Resources** for `pose_landmarker_full.task` and clean/build.

- **Overlay or rep count never updates**  
  Confirm camera permission and that you’re on a screen that calls `startPoseTrackingOnly()` or `startPoseAnalysis()` (e.g. Track flow or active workout).

- **CocoaPods and SPM together**  
  The workspace builds the app target and links both SPM packages (e.g. Firebase) and Pods (MediaPipe). Always use **Chiron.xcworkspace** so both are included.

- **Simulator**  
  MediaPipe runs in the simulator, but live camera pose requires a physical device for real use.
