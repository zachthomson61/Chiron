# Fixing Chiron Build Issues

## 🚨 Current Issues

The "Multiple commands produce" error indicates duplicate build phases or file references. Here's how to fix it:

## 🔧 Step-by-Step Fix

### **1. Clean Derived Data**
```bash
# Remove all derived data for Chiron
rm -rf ~/Library/Developer/Xcode/DerivedData/Chiron-*
```

### **2. Fix Info.plist Conflict**

The project is using `GENERATE_INFOPLIST_FILE = YES` but also has a manual Info.plist file. This causes conflicts.

**Option A: Use Manual Info.plist (Recommended)**
1. In Xcode, go to **Project Settings → Build Settings**
2. Search for "Generate Info.plist"
3. Set `GENERATE_INFOPLIST_FILE` to `NO`
4. Add the Info.plist file to your project if not already added

**Option B: Use Generated Info.plist**
1. Delete the manual `Info.plist` file from the project
2. Add the permissions to the project settings instead

### **3. Check File References**

**In Xcode:**
1. Open the **Project Navigator**
2. Look for any **red files** (missing files)
3. Look for any **duplicate files**
4. Remove any duplicate references

### **4. Check Build Phases**

**In Xcode:**
1. Select your project in the navigator
2. Select the **Chiron target**
3. Go to **Build Phases** tab
4. Check for duplicate entries in:
   - **Compile Sources**
   - **Copy Bundle Resources**
   - **Copy Files**

### **5. Add Missing Files**

Make sure these files are added to the project:
- `SpeechManager.swift`
- `FeedbackModels.swift`
- `FirebaseManager.swift`
- `VideoRecordingManager.swift`
- `CloudConfig.swift`
- All files in `Views/` folder
- All files in `ViewModels/` folder
- All files in `Models/` folder
- All files in `Components/` folder

### **6. Add Firebase Dependencies**

**In Xcode:**
1. Go to **File → Add Package Dependencies**
2. Add: `https://github.com/firebase/firebase-ios-sdk.git`
3. Select these products:
   - `FirebaseCore`
   - `FirebaseStorage`

### **7. Fix Asset Catalog**

**In Xcode:**
1. Open `Assets.xcassets`
2. Make sure all images are properly added
3. Remove any duplicate image references

### **8. Clean and Rebuild**

```bash
# Clean build folder
rm -rf build/

# Clean Xcode cache
rm -rf ~/Library/Caches/com.apple.dt.Xcode/
```

**In Xcode:**
1. **Product → Clean Build Folder** (Cmd+Shift+K)
2. **Product → Build** (Cmd+B)

## 🎯 Common Solutions

### **If you see "Multiple commands produce":**
- Check for duplicate files in the project
- Look for files added to multiple build phases
- Verify asset catalog references

### **If you see "duplicate output file":**
- Clean derived data
- Check for duplicate Info.plist files
- Verify build phase configurations

### **If you see missing files:**
- Add the missing Swift files to the project
- Make sure they're in the correct target
- Check file references in the project navigator

## 📋 Verification Checklist

- [ ] No red files in project navigator
- [ ] All Swift files added to project
- [ ] Firebase dependencies added
- [ ] Info.plist properly configured
- [ ] No duplicate file references
- [ ] Build phases clean
- [ ] Derived data cleaned
- [ ] Project builds successfully

## 🚀 After Fix

Once the build issues are resolved:
1. Test the speech functionality
2. Verify Firebase integration
3. Test the workout flow
4. Check that all features work properly

The speech integration should work perfectly once these build issues are resolved! 🎤 