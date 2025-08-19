#!/bin/bash

# Set your project ID
PROJECT_ID="nodal-descent-467821-t2"

echo "Deploying Pose Analysis service to App Engine..."

# Deploy to App Engine
gcloud app deploy app.yaml --project=$PROJECT_ID --quiet

# Get the service URL
SERVICE_URL=$(gcloud app describe --project=$PROJECT_ID --format="value(defaultHostname)")

echo "Service deployed successfully!"
echo "Service URL: https://$SERVICE_URL"
echo ""
echo "Test the service:"
echo "curl https://$SERVICE_URL/health"
echo ""
echo "Update your app configuration with this URL:"
echo "https://$SERVICE_URL" 