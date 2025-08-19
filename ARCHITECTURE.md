# Chiron Architecture Documentation

## Overview

Chiron uses a modern cloud-based architecture for real-time workout form analysis and AI-powered feedback generation.

## Architecture Flow

```
iOS App (Capture Video)
        ↓
Firebase Storage (Upload)
        ↓
Cloud Run (MediaPipe Pose Extraction)
        ↓
OpenAI API (LLM Feedback Generation)
        ↓
App (Voice + Visual Feedback)
```

## Components

### 1. iOS App
- **Technology**: SwiftUI, AVFoundation, Vision Framework
- **Responsibilities**:
  - Video capture during workouts
  - Real-time pose detection using Vision Framework
  - Basic form analysis and rep counting
  - Upload videos to Firebase Storage
  - Display AI feedback and voice synthesis

### 2. Firebase Storage
- **Technology**: Firebase Storage
- **Responsibilities**:
  - Store workout videos securely
  - Store analysis results and metadata
  - Provide download URLs for Cloud Run processing

### 3. Cloud Run (MediaPipe)
- **Technology**: Python, MediaPipe, Google Cloud Run
- **Responsibilities**:
  - Download videos from Firebase Storage
  - Extract pose data using MediaPipe Pose
  - Analyze movement patterns and form metrics
  - Generate structured pose analysis data
  - Return results for OpenAI processing

### 4. OpenAI API
- **Technology**: OpenAI GPT-4 API
- **Responsibilities**:
  - Receive MediaPipe analysis results
  - Generate human-like coaching feedback
  - Provide safety recommendations
  - Create actionable improvement suggestions
  - Return structured feedback for the app

### 5. App Feedback System
- **Technology**: AVSpeechSynthesizer, SwiftUI
- **Responsibilities**:
  - Parse OpenAI feedback
  - Convert text to speech
  - Display visual feedback
  - Store feedback history

## Configuration

### Required Setup

1. **Firebase Project**
   - Enable Firebase Storage
   - Configure security rules
   - Set up authentication (optional)

2. **Cloud Run Service**
   - Deploy MediaPipe pose analysis service
   - Configure environment variables
   - Set up proper IAM permissions

3. **OpenAI API**
   - Obtain API key from OpenAI
   - Configure billing and usage limits
   - Test API connectivity

### App Configuration

Use the Cloud Configuration screen in the app to set:

```swift
// Cloud Run URL
"https://your-mediapipe-service.run.app"

// OpenAI API Key
"sk-your-openai-api-key"
```

## Data Flow

### 1. Video Upload
```swift
// App uploads video to Firebase Storage
firebaseManager.uploadWorkoutVideo(videoURL: url, workoutId: workoutId)
```

### 2. MediaPipe Analysis
```swift
// Trigger Cloud Run analysis
triggerMediaPipeAnalysis(downloadURL: url, workoutId: workoutId)
```

### 3. OpenAI Processing
```swift
// Send MediaPipe results to OpenAI
triggerOpenAIAnalysis(mediaPipeResults: results, workoutId: workoutId)
```

### 4. Feedback Delivery
```swift
// Parse and deliver feedback
addNewArchitectureFeedback(from: analysisResults)
```

## API Endpoints

### Cloud Run MediaPipe Service
- **Endpoint**: `POST /analyze-pose`
- **Input**: Video URL, workout ID, exercise type
- **Output**: Pose data, form metrics, rep analysis

### OpenAI API
- **Endpoint**: `POST /v1/chat/completions`
- **Model**: GPT-4
- **Input**: Structured pose analysis data
- **Output**: Human-like coaching feedback

## Security Considerations

1. **API Key Management**
   - Store OpenAI API key securely
   - Use environment variables in Cloud Run
   - Implement proper access controls

2. **Data Privacy**
   - Videos are processed and deleted from Cloud Run
   - No persistent storage of video data
   - Analysis results are stored securely

3. **Rate Limiting**
   - Implement OpenAI API rate limiting
   - Monitor Cloud Run usage
   - Set appropriate quotas

## Error Handling

### Network Failures
- Retry logic for upload failures
- Graceful degradation for analysis failures
- Offline mode for basic functionality

### API Limits
- Handle OpenAI rate limits
- Implement exponential backoff
- Queue analysis requests

### Data Validation
- Validate video format and size
- Check analysis result integrity
- Handle malformed feedback

## Performance Optimization

### Video Processing
- Compress videos before upload
- Use appropriate video quality settings
- Implement chunked uploads for large files

### Analysis Pipeline
- Parallel processing where possible
- Cache common analysis results
- Optimize MediaPipe model parameters

### Feedback Delivery
- Stream feedback as it becomes available
- Prioritize critical feedback
- Implement feedback caching

## Monitoring and Analytics

### Key Metrics
- Video upload success rate
- Analysis completion time
- OpenAI API response time
- User engagement with feedback

### Logging
- Structured logging for all components
- Error tracking and alerting
- Performance monitoring

## Future Enhancements

### Planned Features
- Real-time streaming analysis
- Multi-exercise support
- Advanced pose tracking
- Personalized coaching

### Technical Improvements
- Edge computing for faster processing
- Machine learning model optimization
- Enhanced feedback personalization
- Integration with fitness platforms

## Deployment Guide

### Prerequisites
- Google Cloud Platform account
- OpenAI API access
- Firebase project setup
- iOS development environment

### Steps
1. Deploy Cloud Run MediaPipe service
2. Configure Firebase Storage
3. Set up OpenAI API access
4. Configure app settings
5. Test end-to-end workflow

### Testing
- Unit tests for each component
- Integration tests for API calls
- End-to-end workflow testing
- Performance benchmarking

## Troubleshooting

### Common Issues
1. **Upload Failures**: Check Firebase configuration
2. **Analysis Timeouts**: Verify Cloud Run service health
3. **API Errors**: Validate OpenAI API key and limits
4. **Feedback Issues**: Check speech synthesis settings

### Debug Tools
- Firebase Console for storage monitoring
- Cloud Run logs for analysis debugging
- OpenAI API dashboard for usage tracking
- Xcode console for app debugging 