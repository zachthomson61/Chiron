# MediaPipe Pose Analysis Service

This is a Google Cloud Run service that provides MediaPipe pose analysis for workout videos uploaded to Firebase Storage.

## Features

- **MediaPipe Integration**: Uses Google's MediaPipe for accurate pose detection
- **Firebase Storage**: Downloads videos from Firebase Storage for analysis
- **Squat Detection**: Specifically optimized for squat exercise analysis
- **Form Scoring**: Calculates form consistency and quality scores
- **REST API**: Provides HTTP endpoints for pose analysis

## Architecture

```
iOS App → Firebase Storage → Cloud Run (MediaPipe) → Analysis Results
```

## Setup Instructions

### Prerequisites

1. **Google Cloud Project**: You need a Google Cloud project with billing enabled
2. **gcloud CLI**: Install and authenticate with Google Cloud CLI
3. **Firebase Project**: Set up Firebase Storage in your project

### 1. Initial Setup

```bash
# Navigate to the cloud-run-service directory
cd cloud-run-service

# Run the setup script
./setup-gcp.sh
```

This script will:
- Enable necessary Google Cloud APIs
- Create a service account with proper permissions
- Set up Firebase integration

### 2. Deploy the Service

```bash
# Deploy to Cloud Run
./deploy.sh
```

The deployment script will:
- Build the Docker container
- Deploy to Google Cloud Run
- Configure memory, CPU, and timeout settings
- Make the service publicly accessible

### 3. Get the Service URL

After deployment, you'll get a service URL like:
```
https://mediapipe-pose-analysis-xxxxx-uc.a.run.app
```

## API Endpoints

### Health Check
```
GET /health
```

Response:
```json
{
  "status": "healthy",
  "service": "mediapipe-pose-analysis",
  "version": "1.0.0"
}
```

### Pose Analysis
```
POST /analyze-pose
```

Request Body:
```json
{
  "video_url": "https://firebasestorage.googleapis.com/v0/b/bucket/o/video.mp4",
  "workout_id": "workout-123",
  "exercise_type": "squat"
}
```

Response:
```json
{
  "workout_id": "workout-123",
  "exercise_type": "squat",
  "total_frames": 150,
  "rep_count": 5,
  "form_score": 0.85,
  "pose_data": [...],
  "analysis_quality": "good",
  "issues": []
}
```

## Configuration

### Environment Variables

The service uses these environment variables:

- `PORT`: Port number (default: 8080)
- `GOOGLE_CLOUD_PROJECT`: Your Google Cloud project ID
- `FIREBASE_STORAGE_BUCKET`: Firebase Storage bucket name

### Resource Allocation

The service is configured with:
- **Memory**: 4GB (required for MediaPipe)
- **CPU**: 2 cores
- **Timeout**: 600 seconds (10 minutes)
- **Concurrency**: 1 request at a time
- **Max Instances**: 10

## Local Development

### Prerequisites

```bash
pip install -r requirements.txt
```

### Run Locally

```bash
python main.py
```

The service will be available at `http://localhost:8080`

### Test Locally

```bash
# Health check
curl http://localhost:8080/health

# Test pose analysis (replace with actual video URL)
curl -X POST http://localhost:8080/analyze-pose \
  -H "Content-Type: application/json" \
  -d '{
    "video_url": "your-video-url",
    "workout_id": "test-123",
    "exercise_type": "squat"
  }'
```

## Integration with iOS App

### Update FirebaseManager.swift

Replace the placeholder URL in your iOS app:

```swift
private let cloudRunURL: String = "https://your-service-url.run.app"
```

### Test Integration

1. Upload a workout video from your iOS app
2. Check the Cloud Run logs for analysis progress
3. Verify the results are returned to your app

## Monitoring and Logging

### View Logs

```bash
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=mediapipe-pose-analysis" --limit=50
```

### Monitor Performance

- Check Cloud Run metrics in Google Cloud Console
- Monitor Firebase Storage usage
- Track API response times

## Troubleshooting

### Common Issues

1. **Service won't start**: Check if all APIs are enabled
2. **Memory errors**: Increase memory allocation in deployment
3. **Timeout errors**: Increase timeout or optimize video processing
4. **Firebase access errors**: Verify service account permissions

### Debug Commands

```bash
# Check service status
gcloud run services describe mediapipe-pose-analysis --region=us-central1

# View recent logs
gcloud logs read "resource.type=cloud_run_revision" --limit=10

# Test service directly
curl https://your-service-url.run.app/health
```

## Security Considerations

- The service is configured to allow unauthenticated access
- For production, consider adding authentication
- Service account has minimal required permissions
- Videos are processed in memory and not stored permanently

## Cost Optimization

- Service scales to zero when not in use
- Configure max instances based on expected load
- Monitor usage and adjust resources as needed
- Consider using Cloud Run's CPU allocation for cost savings

## Future Enhancements

- Support for multiple exercise types
- Real-time streaming analysis
- Advanced form correction suggestions
- Integration with other ML models
- Caching for repeated analysis

## Support

For issues or questions:
1. Check the Cloud Run logs
2. Verify Firebase Storage permissions
3. Test the service endpoints directly
4. Review the MediaPipe documentation 