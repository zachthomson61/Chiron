#!/bin/bash

# Set your project ID
PROJECT_ID="nodal-descent-467821-t2"

echo "Setting up Google Cloud project for MediaPipe Pose Analysis..."

# Set the project
gcloud config set project $PROJECT_ID

# Enable required APIs
echo "Enabling required APIs..."
gcloud services enable run.googleapis.com
gcloud services enable cloudbuild.googleapis.com
gcloud services enable containerregistry.googleapis.com
gcloud services enable firebase.googleapis.com
gcloud services enable firebaseadmin.googleapis.com
gcloud services enable firebasestorage.googleapis.com

# Create a service account for the Cloud Run service
echo "Creating service account..."
gcloud iam service-accounts create mediapipe-service \
    --display-name="MediaPipe Pose Analysis Service" \
    --description="Service account for MediaPipe pose analysis"

# Grant necessary permissions
echo "Granting permissions..."
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:mediapipe-service@$PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/firebase.admin"

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:mediapipe-service@$PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/storage.admin"

# Create and download service account key (optional, for local testing)
echo "Creating service account key..."
gcloud iam service-accounts keys create service-account-key.json \
    --iam-account=mediapipe-service@$PROJECT_ID.iam.gserviceaccount.com

echo "Google Cloud setup completed!"
echo ""
echo "Next steps:"
echo "1. Deploy the service: ./deploy.sh"
echo "2. Test the service: curl <service-url>/health"
echo "3. Update your app configuration with the service URL" 