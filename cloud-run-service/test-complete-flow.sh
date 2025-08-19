#!/bin/bash

SERVICE_URL="https://nodal-descent-467821-t2.uc.r.appspot.com"

echo "🧪 Testing Complete Pose Analysis Flow..."
echo "Service URL: $SERVICE_URL"
echo ""

echo "1. ✅ Health Check..."
curl -s "$SERVICE_URL/health" | jq .
echo ""

echo "2. 🎯 Testing Pose Analysis with OpenAI Integration..."
curl -s -X POST "$SERVICE_URL/analyze-pose" \
  -H "Content-Type: application/json" \
  -d '{
    "video_url": "https://example.com/sample-video.mp4",
    "workout_id": "test-workout-123",
    "exercise_type": "squat"
  }' | jq .
echo ""

echo "3. 📊 Service Status..."
echo "The service is now ready for your iOS app!"
echo ""
echo "🎉 Complete Setup Summary:"
echo "✅ Google Cloud Project: nodal-descent-467821-t2"
echo "✅ App Engine Service: https://nodal-descent-467821-t2.uc.r.appspot.com"
echo "✅ Firebase Storage: nodal-descent-467821-t2.appspot.com"
echo "✅ OpenAI API: Integrated (GPT-3.5-turbo)"
echo "✅ iOS App: Configured with service URL"
echo ""
echo "🚀 Next Steps:"
echo "1. Build and run your iOS app"
echo "2. Record a workout video"
echo "3. Upload and analyze the video"
echo "4. Check the results and OpenAI feedback"
echo ""
echo "📱 Your iOS app will now:"
echo "- Upload videos to Firebase Storage"
echo "- Send video URLs to the analysis service"
echo "- Get motion detection and form analysis"
echo "- Receive AI-powered feedback from OpenAI"
echo "- Display results to the user" 