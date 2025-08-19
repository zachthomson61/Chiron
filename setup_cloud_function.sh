#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Setting up Workout Analyzer Cloud Function${NC}"
echo "=================================================="

# Configuration
PROJECT_ID=""
REGION="us-central1"
SERVICE_NAME="workout-analyzer"

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
echo -e "${YELLOW}📋 Checking prerequisites...${NC}"

if ! command_exists gcloud; then
    echo -e "${RED}❌ Google Cloud SDK is not installed.${NC}"
    echo "Please install it from: https://cloud.google.com/sdk/docs/install"
    exit 1
fi

if ! command_exists docker; then
    echo -e "${RED}❌ Docker is not installed.${NC}"
    echo "Please install it from: https://docs.docker.com/get-docker/"
    exit 1
fi

if ! command_exists python3; then
    echo -e "${RED}❌ Python 3 is not installed.${NC}"
    echo "Please install Python 3.8 or higher"
    exit 1
fi

echo -e "${GREEN}✅ All prerequisites are installed${NC}"

# Get project ID
echo -e "${YELLOW}🔧 Setting up Google Cloud project...${NC}"
echo "Available projects:"
gcloud projects list --format="table(projectId,name)"

echo ""
read -p "Enter your Google Cloud Project ID: " PROJECT_ID

if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}❌ Project ID is required${NC}"
    exit 1
fi

# Set project
echo -e "${YELLOW}📋 Setting project to $PROJECT_ID${NC}"
gcloud config set project $PROJECT_ID

# Enable required APIs
echo -e "${YELLOW}🔧 Enabling required Google Cloud APIs...${NC}"
gcloud services enable cloudbuild.googleapis.com
gcloud services enable run.googleapis.com
gcloud services enable storage.googleapis.com
gcloud services enable containerregistry.googleapis.com

# Navigate to cloud-functions directory
cd cloud-functions

# Update deploy.sh with project ID
echo -e "${YELLOW}📝 Updating deployment script...${NC}"
sed -i.bak "s/PROJECT_ID=\"your-project-id\"/PROJECT_ID=\"$PROJECT_ID\"/" deploy.sh

# Make scripts executable
chmod +x deploy.sh
chmod +x test_local.py

# Install Python dependencies locally for testing
echo -e "${YELLOW}📦 Installing Python dependencies...${NC}"
pip3 install -r requirements.txt

# Test local setup
echo -e "${YELLOW}🧪 Testing local setup...${NC}"
python3 test_local.py

# Deploy to Cloud Run
echo -e "${YELLOW}🚀 Deploying to Google Cloud Run...${NC}"
./deploy.sh

# Get service URL
SERVICE_URL=$(gcloud run services describe $SERVICE_NAME --region=$REGION --format="value(status.url)")

echo -e "${GREEN}✅ Cloud Function deployment complete!${NC}"
echo ""
echo -e "${GREEN}🌐 Service URL: $SERVICE_URL${NC}"
echo ""
echo -e "${YELLOW}📝 Next steps:${NC}"
echo "1. Update your iOS app with the service URL: $SERVICE_URL"
echo "2. Test the health endpoint: $SERVICE_URL/health"
echo "3. Configure Firebase Storage bucket permissions"
echo ""
echo -e "${YELLOW}🔧 Environment Variables for iOS app:${NC}"
echo "CLOUD_FUNCTION_URL=$SERVICE_URL"
echo "FIREBASE_STORAGE_BUCKET=$PROJECT_ID.appspot.com"
echo ""
echo -e "${YELLOW}📊 Monitor the service:${NC}"
echo "gcloud run services describe $SERVICE_NAME --region=$REGION"
echo "gcloud logs read --service=$SERVICE_NAME --region=$REGION --limit=50"
echo ""
echo -e "${YELLOW}🧪 Test the deployment:${NC}"
echo "curl $SERVICE_URL/health"
echo ""
echo -e "${GREEN}🎉 Setup complete! Your cloud function is ready to analyze workout videos.${NC}" 