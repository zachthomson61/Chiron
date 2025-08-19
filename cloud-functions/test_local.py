#!/usr/bin/env python3
"""
Test script for the workout analyzer cloud function
"""

import requests
import json
import os
import time

# Configuration
LOCAL_URL = "http://localhost:8080"
CLOUD_URL = "https://your-service-url.run.app"  # Replace with your deployed URL

def test_health_endpoint(url):
    """Test the health check endpoint"""
    print(f"Testing health endpoint at {url}")
    try:
        response = requests.get(f"{url}/health", timeout=10)
        if response.status_code == 200:
            print("✅ Health check passed")
            print(f"Response: {response.json()}")
            return True
        else:
            print(f"❌ Health check failed: {response.status_code}")
            return False
    except Exception as e:
        print(f"❌ Health check error: {str(e)}")
        return False

def test_workout_analysis(url, test_data):
    """Test the workout analysis endpoint"""
    print(f"\nTesting workout analysis at {url}")
    try:
        response = requests.post(
            f"{url}/analyze_workout",
            json=test_data,
            timeout=300  # 5 minutes for video analysis
        )
        
        if response.status_code == 200:
            print("✅ Workout analysis completed successfully")
            result = response.json()
            print(f"Analysis results: {json.dumps(result, indent=2)}")
            return True
        else:
            print(f"❌ Workout analysis failed: {response.status_code}")
            print(f"Error: {response.text}")
            return False
    except Exception as e:
        print(f"❌ Workout analysis error: {str(e)}")
        return False

def create_test_data():
    """Create test data for analysis"""
    return {
        "video_url": "gs://your-bucket/workout-videos/test-workout.mp4",
        "workout_id": "test-workout-123",
        "exercise_type": "squat",
        "workout_data": {
            "total_reps": 5,
            "form_score": 85,
            "duration": 120.5,
            "exercise": "squat"
        }
    }

def main():
    """Main test function"""
    print("🧪 Testing Workout Analyzer Cloud Function")
    print("=" * 50)
    
    # Test local deployment
    print("\n🔧 Testing Local Deployment")
    print("-" * 30)
    
    if test_health_endpoint(LOCAL_URL):
        print("✅ Local service is running")
        
        # Test with sample data
        test_data = create_test_data()
        test_workout_analysis(LOCAL_URL, test_data)
    else:
        print("❌ Local service is not running")
        print("Start the service with: python main.py")
    
    # Test cloud deployment (if URL is provided)
    if CLOUD_URL != "https://your-service-url.run.app":
        print("\n☁️  Testing Cloud Deployment")
        print("-" * 30)
        
        if test_health_endpoint(CLOUD_URL):
            print("✅ Cloud service is running")
            
            # Test with sample data
            test_data = create_test_data()
            test_workout_analysis(CLOUD_URL, test_data)
        else:
            print("❌ Cloud service is not accessible")
    else:
        print("\n☁️  Skipping cloud test (URL not configured)")
    
    print("\n🎯 Test Summary")
    print("=" * 50)
    print("To run the tests:")
    print("1. Start local service: python main.py")
    print("2. Run this test: python test_local.py")
    print("3. Update CLOUD_URL in this script after deployment")

if __name__ == "__main__":
    main() 