# Adding Speech Permissions to Project Settings

Since we removed the manual Info.plist to fix the build conflict, you need to add the speech permissions to your project settings.

## 🔧 Steps to Add Permissions

### **1. Open Xcode Project Settings**
1. Open Xcode
2. Select your project in the navigator
3. Select the "Chiron" target
4. Go to "Build Settings" tab

### **2. Add Speech Permissions**

Search for each of these keys and add them:

#### **NSMicrophoneUsageDescription**
- **Key:** `INFOPLIST_KEY_NSMicrophoneUsageDescription`
- **Value:** `This app uses the microphone for voice commands during workouts.`

#### **NSSpeechRecognitionUsageDescription**
- **Key:** `INFOPLIST_KEY_NSSpeechRecognitionUsageDescription`
- **Value:** `This app uses speech recognition to understand voice commands for workout control.`

#### **NSCameraUsageDescription**
- **Key:** `INFOPLIST_KEY_NSCameraUsageDescription`
- **Value:** `This app uses the camera to analyze your workout form and provide real-time feedback.`

### **3. How to Add Each Permission**

1. In Build Settings, click the "+" button
2. Select "Add User-Defined Setting"
3. Name it: `INFOPLIST_KEY_NSMicrophoneUsageDescription`
4. Set the value to: `This app uses the microphone for voice commands during workouts.`
5. Repeat for the other two permissions

### **4. Alternative Method**

You can also add these directly to the project file. The settings should look like this:

```
INFOPLIST_KEY_NSMicrophoneUsageDescription = "This app uses the microphone for voice commands during workouts.";
INFOPLIST_KEY_NSSpeechRecognitionUsageDescription = "This app uses speech recognition to understand voice commands for workout control.";
INFOPLIST_KEY_NSCameraUsageDescription = "This app uses the camera to analyze your workout form and provide real-time feedback.";
```

### **5. Verify Settings**

After adding the permissions:
1. Clean Build Folder (Cmd+Shift+K)
2. Build (Cmd+B)
3. The build should now succeed without the "Multiple commands produce" error

### **6. Test Speech Functionality**

Once the build succeeds:
1. Run the app
2. Test speech features
3. Verify permissions are requested properly

## 🎯 Expected Result

- ✅ Build succeeds without "Multiple commands produce" error
- ✅ Speech permissions are properly requested
- ✅ Speech functionality works correctly
- ✅ No more build conflicts

The speech integration should work perfectly once these permissions are added to the project settings! 🎤 