#!/bin/bash

# Set your project ID
PROJECT_ID="chiron-6c955"
SERVICE_NAME="mediapipe-pose-analysis"
REGION="us-central1"

echo "Deploying MediaPipe Pose Analysis service to Cloud Run..."

# Build and deploy to Cloud Run
gcloud run deploy $SERVICE_NAME \
    --source . \
    --platform managed \
    --region $REGION \
    --project $PROJECT_ID \
    --allow-unauthenticated \
    --memory 4Gi \
    --cpu 2 \
    --timeout 600 \
    --concurrency 1 \
    --max-instances 10

# Get the service URL
SERVICE_URL=$(gcloud run services describe $SERVICE_NAME --platform managed --region $REGION --project $PROJECT_ID --format="value(status.url)")

echo "Service deployed successfully!"
echo "Service URL: $SERVICE_URL"
echo ""
echo "Test the service:"
echo "curl $SERVICE_URL/health"
echo ""
echo "Update your app configuration with this URL:"
echo "$SERVICE_URL" 