#!/bin/bash

SERVICE_URL="https://nodal-descent-467821-t2.uc.r.appspot.com"

echo "Testing Pose Analysis Service..."
echo "Service URL: $SERVICE_URL"
echo ""

echo "1. Testing health endpoint..."
curl -s "$SERVICE_URL/health" | jq .
echo ""

echo "2. Testing root endpoint..."
curl -s "$SERVICE_URL/" | jq .
echo ""

echo "3. Testing analyze-pose endpoint with sample data..."
curl -s -X POST "$SERVICE_URL/analyze-pose" \
  -H "Content-Type: application/json" \
  -d '{
    "video_url": "https://example.com/sample-video.mp4",
    "workout_id": "test-123",
    "exercise_type": "squat"
  }' | jq .
echo ""

echo "Service test completed!" 