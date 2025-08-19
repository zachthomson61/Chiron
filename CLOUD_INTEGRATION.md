# Cloud Integration Guide

This guide covers the complete setup for integrating the iOS app with the Google Cloud Run function for workout video analysis.

## 🚀 Complete Integration Flow

```
iOS App → Firebase Storage → Cloud Function → Analysis Results → iOS App
```

1. **iOS app** records workout video
2. **Video uploaded** to Firebase Storage
3. **Cloud function** triggered with download URL
4. **MediaPipe analysis** performed on video
5. **Results stored** in Firebase Storage
6. **iOS app** retrieves and displays analysis

## 📱 iOS App Integration

### New Features Added:

#### **FirebaseManager.swift**
- ✅ `uploadWorkoutVideo()` - Uploads video to Firebase Storage
- ✅ `callCloudAnalysis()` - Triggers cloud function with download URL
- ✅ `getAnalysisResults()` - Retrieves stored analysis results
- ✅ Automatic cloud function calling after video upload

#### **WorkoutViewModel.swift**
- ✅ `startAnalysisPolling()` - Polls for analysis results
- ✅ `@Published var isAnalyzing` - Shows analysis progress
- ✅ `@Published var analysisResults` - Stores analysis results

#### **New Views**
- ✅ `AnalysisResultsView.swift` - Displays detailed analysis results
- ✅ `CloudConfigView.swift` - Configures cloud function URL
- ✅ Enhanced `SetCompleteView.swift` - Shows analysis progress

### Configuration

#### **1. Set Cloud Function URL**
```swift
// In your app initialization
CloudConfig.shared.configure(cloudFunctionURL: "https://your-service-url.run.app")
```

#### **2. Enable Analysis**
The app will automatically:
- Upload videos to Firebase Storage
- Call cloud function with download URL
- Poll for analysis results
- Display results in the UI

## ☁️ Cloud Function Setup

### **1. Deploy the Cloud Function**

```bash
# Navigate to cloud-functions directory
cd cloud-functions

# Make deployment script executable
chmod +x deploy.sh

# Edit deploy.sh and set your PROJECT_ID
# Then run deployment
./deploy.sh
```

### **2. Configure Environment Variables**

After deployment, set these in Cloud Run:
```bash
FIREBASE_STORAGE_BUCKET=your-project-id.appspot.com
GOOGLE_CLOUD_PROJECT=your-project-id
```

### **3. Test the Deployment**

```bash
# Test health endpoint
curl https://your-service-url.run.app/health

# Test analysis endpoint
python test_local.py
```

## 🔧 API Integration

### **Request Format**
```json
POST /analyze_workout
{
  "video_url": "https://firebasestorage.googleapis.com/...",
  "workout_id": "uuid",
  "exercise_type": "squat",
  "workout_data": {
    "workout_id": "uuid",
    "video_file_name": "video.mp4",
    "upload_timestamp": 1234567890
  }
}
```

### **Response Format**
```json
{
  "success": true,
  "workout_id": "uuid",
  "analysis_results": {
    "exercise_type": "squat",
    "total_reps": 5,
    "average_form_score": 0.85,
    "rep_analyses": [...],
    "overall_feedback": [...],
    "recommendations": [...]
  },
  "results_url": "gs://bucket/workout-analysis/uuid/analysis_results.json"
}
```

## 📊 Analysis Features

### **Squat Analysis**
- **Depth Scoring**: Measures hip position relative to knees
- **Posture Analysis**: Evaluates torso alignment
- **Tempo Assessment**: Analyzes rep timing
- **Rep Detection**: Automatic rep counting and segmentation

### **Scoring System**
- **Excellent (80-100%)**: Perfect form
- **Good (60-80%)**: Minor issues
- **Fair (40-60%)**: Needs improvement
- **Poor (0-40%)**: Significant issues

### **Feedback Categories**
- **Depth Issues**: "Insufficient depth - aim to get hips below knee level"
- **Posture Issues**: "Poor posture - keep chest up and back straight"
- **Tempo Issues**: "Tempo too fast - slow down for better control"

## 🎯 User Experience

### **Workout Flow**
1. User starts workout → Video recording begins
2. User performs exercises → Real-time form feedback
3. User finishes set → Video uploads to Firebase
4. Cloud function analyzes video → Results stored
5. User views detailed analysis → Personalized recommendations

### **Analysis Display**
- **Overall Form Score**: Circular progress indicator
- **Rep-by-rep Breakdown**: Individual rep analysis
- **Detailed Feedback**: Specific form issues
- **Recommendations**: Personalized improvement tips

## 🔍 Monitoring & Debugging

### **iOS App Logs**
```swift
// Check cloud function configuration
print("Cloud function URL: \(CloudConfig.shared.getCloudFunctionURL() ?? "Not configured")")

// Monitor upload progress
print("Upload progress: \(uploadProgress * 100)%")

// Check analysis status
print("Analysis results: \(analysisResults ?? [:])")
```

### **Cloud Function Logs**
```bash
# View recent logs
gcloud logs read --service=workout-analyzer --region=us-central1 --limit=20

# Monitor service status
gcloud run services describe workout-analyzer --region=us-central1
```

## 🛠️ Troubleshooting

### **Common Issues**

#### **1. Cloud Function Not Called**
- ✅ Check cloud function URL configuration
- ✅ Verify Firebase Storage permissions
- ✅ Check network connectivity

#### **2. Analysis Results Not Received**
- ✅ Check cloud function logs
- ✅ Verify video upload success
- ✅ Check polling timeout settings

#### **3. Upload Failures**
- ✅ Check Firebase Storage rules
- ✅ Verify video file format
- ✅ Check device storage space

### **Debug Commands**

```bash
# Test cloud function health
curl https://your-service-url.run.app/health

# Test analysis endpoint
curl -X POST https://your-service-url.run.app/analyze_workout \
  -H "Content-Type: application/json" \
  -d '{"test": "data"}'

# Check Firebase Storage
gsutil ls gs://your-bucket/workout-videos/
```

## 📈 Performance Optimization

### **Cloud Function Settings**
- **Memory**: 4GB (required for MediaPipe)
- **CPU**: 2 vCPU
- **Timeout**: 900 seconds (15 minutes)
- **Concurrency**: 1 (single request at a time)

### **iOS App Optimization**
- **Video Compression**: Automatic before upload
- **Polling Interval**: 10 seconds
- **Timeout**: 5 minutes maximum
- **Caching**: Results stored locally

## 🔒 Security Considerations

### **Firebase Security Rules**
```javascript
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

### **Cloud Function Security**
- ✅ Non-root user in Docker container
- ✅ Input validation on all requests
- ✅ Error handling and logging
- ✅ Timeout limits to prevent abuse

## 🚀 Deployment Checklist

### **Before Deployment**
- [ ] Google Cloud project created
- [ ] Firebase project configured
- [ ] Firebase Storage enabled
- [ ] Google Cloud SDK installed
- [ ] Docker installed

### **Cloud Function Deployment**
- [ ] Run `./setup_cloud_function.sh`
- [ ] Set environment variables
- [ ] Test health endpoint
- [ ] Verify Firebase Storage access

### **iOS App Configuration**
- [ ] Add Firebase dependencies
- [ ] Configure `GoogleService-Info.plist`
- [ ] Set cloud function URL
- [ ] Test video upload
- [ ] Test analysis flow

### **Final Testing**
- [ ] Record workout video
- [ ] Verify upload to Firebase
- [ ] Check cloud function logs
- [ ] Verify analysis results
- [ ] Test results display

## 🎉 Success Indicators

### **Working Integration**
- ✅ Video uploads to Firebase Storage
- ✅ Cloud function receives download URL
- ✅ Analysis completes successfully
- ✅ Results appear in iOS app
- ✅ User sees detailed form feedback

### **Performance Metrics**
- ✅ Upload time < 30 seconds
- ✅ Analysis time < 5 minutes
- ✅ Results display < 10 seconds
- ✅ App responsiveness maintained

## 📚 Additional Resources

- [Google Cloud Run Documentation](https://cloud.google.com/run/docs)
- [Firebase Storage Documentation](https://firebase.google.com/docs/storage)
- [MediaPipe Documentation](https://mediapipe.dev/)
- [iOS URLSession Documentation](https://developer.apple.com/documentation/foundation/urlsession)

The integration is now complete and ready for production use! 🚀 