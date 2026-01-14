# Chiron - Workout Form Coach

Chiron is an iOS app that uses computer vision to analyze workout form and provide real-time feedback. The app now includes video recording and Firebase Storage integration for uploading workout videos.

## Features

- Real-time pose detection using Vision framework
- Form analysis for exercises (currently Squat)
- Video recording during workouts
- Firebase Storage integration for video uploads
- Progress tracking and form scoring

## Firebase Setup

To enable video upload functionality, you need to set up Firebase:

### 1. Create a Firebase Project

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Create a new project or select an existing one
3. Enable Firebase Storage in your project

### 2. Configure Firebase Storage Rules

In the Firebase Console, go to Storage > Rules and update the rules to allow uploads:

```
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /workout-videos/{workoutId}/{allPaths=**} {
      allow read, write: if request.auth != null;
    }
    match /workout-data/{workoutId}/{allPaths=**} {
      allow read, write: if request.auth != null;
    }
  }
}
```

### 3. Download Configuration File

1. In Firebase Console, go to Project Settings
2. Add an iOS app to your project
3. Download the `GoogleService-Info.plist` file
4. Replace the template file in `Chiron/GoogleService-Info.plist` with your actual configuration

### 4. Add Firebase Dependencies

The project includes a `Package.swift` file with Firebase dependencies. In Xcode:

1. Go to File > Add Package Dependencies
2. Add the Firebase iOS SDK: `https://github.com/firebase/firebase-ios-sdk.git`
3. Select the following products:
   - FirebaseCore
   - FirebaseStorage

## Video Recording Features

### Automatic Recording
- Video recording starts automatically when a workout begins
- Recording duration is displayed in the workout interface
- Videos are uploaded to Firebase Storage when the set is completed

### Upload Progress
- Real-time upload progress is shown in the Set Complete view
- Workout data (reps, form scores, etc.) is uploaded alongside the video
- Videos are organized by workout ID in Firebase Storage

### File Structure in Firebase Storage
```
workout-videos/
  {workoutId}/
    {videoFileName}.mp4
    
workout-data/
  {workoutId}/
    workout.json
```

## Usage

1. Launch the app and tap "Start Workout"
2. The camera will start and video recording will begin automatically
3. Perform your workout - the app will analyze your form in real-time
4. When you finish a set, tap "Finish Set"
5. The video will be uploaded to Firebase Storage with workout data
6. Upload progress is shown in the Set Complete view

## Privacy

- Videos are stored securely in Firebase Storage
- Workout data is anonymized and stored with the video
- Users can delete their data through the Firebase Console

## Technical Details

### Video Recording
- Uses `AVCaptureMovieFileOutput` for video recording
- Integrates with existing camera setup
- Records in MP4 format for optimal compression

### Firebase Integration
- Uses Firebase Storage for video uploads
- Implements progress tracking for uploads
- Stores workout metadata alongside videos

### Architecture
- `VideoRecordingManager`: Handles video recording
- `FirebaseManager`: Manages Firebase Storage uploads
- `WorkoutViewModel`: Coordinates recording and upload flow
- Integration with existing pose detection system

### Screen Orientation
The app is locked to portrait orientation only for both iPhone and iPad. This is configured in:
- **Info.plist**: `UISupportedInterfaceOrientations` and `UISupportedInterfaceOrientations~ipad` are set to portrait only
- **Project Build Settings**: `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone` and `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad` are set to portrait only
- **UIRequiresFullScreen**: Set to `true` to suppress Xcode warnings about orientation support

## Requirements

- iOS 17.0+
- Xcode 15.0+
- Firebase project with Storage enabled
- Camera permissions

## Troubleshooting

### Upload Issues
- Check Firebase Storage rules
- Verify network connectivity
- Ensure Firebase configuration is correct

### Recording Issues
- Check camera permissions
- Verify device has sufficient storage
- Ensure camera is not being used by another app 