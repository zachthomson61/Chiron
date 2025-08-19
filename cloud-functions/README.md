# Workout Analyzer Cloud Function

A Google Cloud Run service that analyzes workout videos using MediaPipe and provides detailed form analysis.

## Features

- **Video Analysis**: Analyzes workout videos uploaded to Firebase Storage
- **MediaPipe Integration**: Uses Google's MediaPipe for pose detection
- **Exercise-Specific Analysis**: Currently supports squat analysis with depth, posture, and tempo scoring
- **Detailed Feedback**: Provides rep-by-rep analysis with specific recommendations
- **Scalable**: Runs on Google Cloud Run with automatic scaling

## Architecture

```
iOS App → Firebase Storage → Cloud Function → Analysis Results
```

1. iOS app uploads video to Firebase Storage
2. Cloud function is triggered with video URL
3. Function downloads video and analyzes with MediaPipe
4. Results are uploaded back to Firebase Storage
5. iOS app can retrieve analysis results

## Setup Instructions

### 1. Prerequisites

- Google Cloud Project with billing enabled
- Google Cloud SDK installed
- Docker installed
- Firebase project with Storage enabled

### 2. Configure Google Cloud

```bash
# Set your project ID
export PROJECT_ID="your-project-id"

# Enable required APIs
gcloud services enable cloudbuild.googleapis.com
gcloud services enable run.googleapis.com
gcloud services enable storage.googleapis.com

# Set default project
gcloud config set project $PROJECT_ID
```

### 3. Deploy the Service

```bash
# Make deployment script executable
chmod +x deploy.sh

# Edit deploy.sh and set your PROJECT_ID
# Then run deployment
./deploy.sh
```

### 4. Configure Environment Variables

After deployment, set these environment variables in Cloud Run:

```bash
FIREBASE_STORAGE_BUCKET=your-project-id.appspot.com
GOOGLE_CLOUD_PROJECT=your-project-id
```

### 5. Test the Deployment

```bash
# Test health endpoint
curl https://your-service-url.run.app/health

# Test analysis endpoint
python test_local.py
```

## API Endpoints

### Health Check
```
GET /health
```
Returns service status and timestamp.

### Workout Analysis
```
POST /analyze_workout
```

**Request Body:**
```json
{
  "video_url": "gs://bucket/path/to/video.mp4",
  "workout_id": "uuid",
  "exercise_type": "squat",
  "workout_data": {
    "total_reps": 5,
    "form_score": 85,
    "duration": 120.5
  }
}
```

**Response:**
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

## Analysis Features

### Squat Analysis

The service analyzes squats for:

1. **Depth**: Measures hip position relative to knees
2. **Posture**: Analyzes torso angle and alignment
3. **Tempo**: Evaluates rep timing and control
4. **Rep Detection**: Automatically counts and segments reps

### Scoring System

- **Excellent (0.8-1.0)**: Perfect form
- **Good (0.6-0.8)**: Minor issues
- **Fair (0.4-0.6)**: Needs improvement
- **Poor (0.0-0.4)**: Significant issues

### Feedback Categories

- **Depth Issues**: Insufficient squat depth
- **Posture Issues**: Poor torso alignment
- **Tempo Issues**: Too fast or slow movement
- **General Recommendations**: Exercise-specific advice

## Local Development

### 1. Install Dependencies

```bash
pip install -r requirements.txt
```

### 2. Set Environment Variables

```bash
cp env.example .env
# Edit .env with your configuration
```

### 3. Run Locally

```bash
python main.py
```

### 4. Test

```bash
python test_local.py
```

## Deployment Configuration

### Cloud Run Settings

- **Memory**: 4GB (required for MediaPipe)
- **CPU**: 2 vCPU
- **Timeout**: 900 seconds (15 minutes)
- **Concurrency**: 1 (single request at a time)
- **Max Instances**: 10

### Docker Configuration

The Dockerfile includes:
- Python 3.11 slim image
- OpenCV and MediaPipe dependencies
- Non-root user for security
- Health checks
- Gunicorn server

## Monitoring and Logging

### View Logs

```bash
gcloud logs read --service=workout-analyzer --region=us-central1 --limit=50
```

### Monitor Performance

```bash
gcloud run services describe workout-analyzer --region=us-central1
```

### Health Checks

The service includes automatic health checks:
- Endpoint: `/health`
- Interval: 30 seconds
- Timeout: 30 seconds
- Retries: 3

## Security

- **Authentication**: Service is public but can be secured with IAM
- **Non-root User**: Docker container runs as non-root user
- **Input Validation**: All inputs are validated
- **Error Handling**: Comprehensive error handling and logging

## Cost Optimization

- **Auto-scaling**: Scales to zero when not in use
- **Resource Limits**: Configured for optimal performance/cost
- **Timeout Limits**: Prevents runaway processes

## Troubleshooting

### Common Issues

1. **Memory Errors**: Increase memory allocation in Cloud Run
2. **Timeout Errors**: Increase timeout or optimize video processing
3. **Permission Errors**: Check Firebase Storage permissions
4. **Build Errors**: Ensure all dependencies are in requirements.txt

### Debug Commands

```bash
# Check service status
gcloud run services describe workout-analyzer --region=us-central1

# View recent logs
gcloud logs read --service=workout-analyzer --region=us-central1 --limit=20

# Test endpoint
curl -X POST https://your-service-url.run.app/analyze_workout \
  -H "Content-Type: application/json" \
  -d '{"test": "data"}'
```

## Integration with iOS App

The iOS app should:

1. Upload video to Firebase Storage
2. Call the cloud function with video URL
3. Poll for analysis results
4. Display results in the app

### iOS Integration Code

```swift
// In FirebaseManager.swift
func triggerCloudAnalysis(workoutData: [String: Any], workoutId: String) {
    // Implementation provided in the main codebase
}
```

## Future Enhancements

- Support for more exercises (deadlift, pushup, etc.)
- Real-time analysis streaming
- Advanced form correction suggestions
- Integration with fitness tracking apps
- Machine learning model improvements 