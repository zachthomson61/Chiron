# Quick Start: One Question Flow

## Step 1: Verify Files in Xcode

1. Open Xcode
2. In the Project Navigator (left sidebar), look for:
   ```
   Chiron/Features/PlanBuilder/OneQuestionFlow/
     ├── FlowConfig.swift
     ├── OQFViewModel.swift
     ├── OneQuestionShellView.swift
     └── InputViews.swift
   ```

3. **If files are RED (missing):**
   - Right-click on the `OneQuestionFlow` folder in Xcode
   - Select "Add Files to Chiron..."
   - Navigate to `Chiron/Features/PlanBuilder/OneQuestionFlow/`
   - Select all 4 Swift files
   - Make sure "Copy items if needed" is UNCHECKED (files are already there)
   - Make sure "Add to targets: Chiron" is CHECKED
   - Click "Add"

## Step 2: Enable the Feature Flag

### Option A: In Code (Quick Test)
Open `PlanBuilderView.swift` and change line 10:
```swift
@AppStorage("planBuilderOQFEnabled") private var isOQFEnabled = true  // Change false to true
```

### Option B: In Settings (Permanent)
Add this to your app settings or a developer menu:
```swift
UserDefaults.standard.set(true, forKey: "planBuilderOQFEnabled")
```

## Step 3: Build and Run

1. Clean Build Folder: `Cmd + Shift + K`
2. Build: `Cmd + B`
3. Run: `Cmd + R`

## Step 4: Test

1. Navigate to the Plan Builder in your app
2. You should see the one-question-at-a-time flow instead of the scrollable form
3. Try answering a few questions to verify it works

## Troubleshooting

### "Cannot find 'OQFViewModel' in scope"
- Make sure all 4 files are added to the Xcode project
- Check that they're included in the "Chiron" target
- Clean build folder and rebuild

### "Cannot find 'OneQuestionShellView' in scope"
- Same as above - verify files are in the project

### Feature not showing
- Double-check the feature flag is set to `true`
- Verify you're looking at the right screen in the app
- Check console for any runtime errors

### Build Errors
- Make sure `FlowConfig.swift` compiles (it references `MuscleGroup` and `WorkoutSplit`)
- Verify all imports are correct (SwiftUI, Foundation, Combine)

## File Checklist

✅ `FlowConfig.swift` - Flow definitions  
✅ `OQFViewModel.swift` - State management  
✅ `OneQuestionShellView.swift` - Main UI  
✅ `InputViews.swift` - Input components  
✅ `PlanBuilderView.swift` - Updated with feature flag  

All files are in: `Chiron/Features/PlanBuilder/OneQuestionFlow/`





