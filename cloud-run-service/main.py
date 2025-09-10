import os
import json
import logging
import tempfile
import requests
import time
from flask import Flask, request, jsonify
import cv2
import numpy as np
from google.cloud import storage
import firebase_admin
from firebase_admin import credentials, storage as firebase_storage
import mediapipe as mp

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize Flask app
app = Flask(__name__)

# Initialize Firebase Admin SDK
try:
    # Use service account if available, otherwise use default credentials
    if os.path.exists('service-account-key.json'):
        cred = credentials.Certificate('service-account-key.json')
        firebase_admin.initialize_app(cred, {
            'storageBucket': 'chiron-6c955.firebasestorage.app'
        })
    else:
        firebase_admin.initialize_app(options={
            'storageBucket': 'chiron-6c955.firebasestorage.app'
        })
    logger.info("Firebase Admin SDK initialized successfully")
except Exception as e:
    logger.warning(f"Firebase Admin SDK initialization failed: {e}")

def download_video_from_firebase(video_url):
    """Download video from Firebase Storage"""
    try:
        import urllib.parse
        
        # Extract bucket and blob name from URL
        # URL format: https://firebasestorage.googleapis.com/v0/b/bucket/o/blob
        if 'firebasestorage.googleapis.com' in video_url:
            # Parse Firebase Storage URL
            bucket_name = 'chiron-6c955.firebasestorage.app'
            # Extract blob name from URL and decode it
            blob_name_encoded = video_url.split('/o/')[-1].split('?')[0]
            blob_name = urllib.parse.unquote(blob_name_encoded)
        else:
            # Direct URL
            bucket_name = 'chiron-6c955.firebasestorage.app'
            blob_name = video_url.split('/')[-1]
        
        logger.info(f"Attempting to download blob: {blob_name}")
        bucket = firebase_storage.bucket(bucket_name)
        blob = bucket.blob(blob_name)
        
        # Download to temporary file
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.mp4')
        blob.download_to_filename(temp_file.name)
        logger.info(f"Video downloaded successfully: {temp_file.name}")
        return temp_file.name
    except Exception as e:
        logger.error(f"Error downloading video: {e}")
        raise

def analyze_pose_from_video(video_path):
    """Analyze pose from video using MediaPipe (optimized for speed)"""
    import mediapipe as mp
    
    mp_pose = mp.solutions.pose
    pose = mp_pose.Pose(
        static_image_mode=False,
        model_complexity=0,  # Faster processing
        smooth_landmarks=True,
        enable_segmentation=False,
        smooth_segmentation=True,
        min_detection_confidence=0.3,  # Lower threshold for faster detection
        min_tracking_confidence=0.3
    )
    
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise ValueError("Could not open video file")
    
    frame_count = 0
    pose_data = []
    motion_detected = False
    
    # Get video properties
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    fps = cap.get(cv2.CAP_PROP_FPS)
    
    # Sample every 3rd frame for faster processing
    sample_rate = max(1, int(fps / 10))  # Process ~10 fps regardless of video fps
    
    logger.info(f"📹 Video: {total_frames} frames, {fps} fps, sampling every {sample_rate} frames")
    
    while cap.isOpened():
        ret, frame = cap.read()
        if not ret:
            break
            
        frame_count += 1
        
        # Only process every Nth frame for speed
        if frame_count % sample_rate != 0:
            continue
        
        # Convert BGR to RGB
        rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        results = pose.process(rgb_frame)
        
        if results.pose_landmarks:
            # Extract pose landmarks
            landmarks = results.pose_landmarks.landmark
            pose_metrics = calculate_pose_metrics(landmarks, frame.shape)
            pose_data.append(pose_metrics)
            motion_detected = True
    
    cap.release()
    pose.close()
    
    logger.info(f"⚡ Processed {len(pose_data)} pose frames from {frame_count} total frames")
    
    if not pose_data:
        return {
            "total_frames": frame_count,
            "rep_count": 0,
            "form_score": 0.0,
            "motion_detected": False,
            "motion_percentage": 0,
            "analysis_quality": "poor",
            "pose_summary": "No pose detected",
            "feedback": "No human pose detected in the video. Please ensure you are visible in the camera frame.",
            "note": "MediaPipe pose detection failed."
        }
    
    # Analyze pose data
    pose_summary = summarize_pose(pose_data)
    feedback = get_feedback_from_gpt(pose_summary)
    
    # Calculate overall metrics
    total_frames = len(pose_data)
    motion_percentage = (total_frames / frame_count) * 100 if frame_count > 0 else 0
    form_score = calculate_form_score(pose_data)
    rep_count = estimate_rep_count(pose_data)
    
    return {
        "total_frames": frame_count,
        "rep_count": rep_count,
        "form_score": form_score,
        "motion_detected": motion_detected,
        "motion_percentage": motion_percentage,
        "analysis_quality": "good" if motion_detected else "poor",
        "pose_summary": pose_summary,
        "feedback": feedback,
        "note": "MediaPipe pose analysis completed."
    }

def calculate_pose_metrics(landmarks, frame_shape):
    """Calculate pose metrics from MediaPipe landmarks"""
    height, width = frame_shape[:2]
    
    # Convert normalized coordinates to pixel coordinates
    def get_coord(landmark):
        return (int(landmark.x * width), int(landmark.y * height))
    
    # Key landmarks for squat analysis
    left_hip = get_coord(landmarks[mp.solutions.pose.PoseLandmark.LEFT_HIP])
    right_hip = get_coord(landmarks[mp.solutions.pose.PoseLandmark.RIGHT_HIP])
    left_knee = get_coord(landmarks[mp.solutions.pose.PoseLandmark.LEFT_KNEE])
    right_knee = get_coord(landmarks[mp.solutions.pose.PoseLandmark.RIGHT_KNEE])
    left_ankle = get_coord(landmarks[mp.solutions.pose.PoseLandmark.LEFT_ANKLE])
    right_ankle = get_coord(landmarks[mp.solutions.pose.PoseLandmark.RIGHT_ANKLE])
    left_shoulder = get_coord(landmarks[mp.solutions.pose.PoseLandmark.LEFT_SHOULDER])
    right_shoulder = get_coord(landmarks[mp.solutions.pose.PoseLandmark.RIGHT_SHOULDER])
    
    # Calculate metrics
    hip_center = ((left_hip[0] + right_hip[0]) // 2, (left_hip[1] + right_hip[1]) // 2)
    knee_center = ((left_knee[0] + right_knee[0]) // 2, (left_knee[1] + right_knee[1]) // 2)
    ankle_center = ((left_ankle[0] + right_ankle[0]) // 2, (left_ankle[1] + right_ankle[1]) // 2)
    shoulder_center = ((left_shoulder[0] + right_shoulder[0]) // 2, (left_shoulder[1] + right_shoulder[1]) // 2)
    
    # Squat depth (vertical distance from hips to knees)
    depth = abs(hip_center[1] - knee_center[1])
    max_depth = height * 0.4  # Expected maximum depth
    depth_percentage = min(1.0, depth / max_depth)
    
    # Back angle (angle between shoulder-hip-ankle)
    back_angle = calculate_angle(shoulder_center, hip_center, ankle_center)
    
    # Knee alignment (horizontal knee deviation)
    knee_deviation = abs(left_knee[0] - right_knee[0]) - abs(left_ankle[0] - right_ankle[0])
    knee_deviation_normalized = knee_deviation / width
    
    return {
        "depth_percentage": depth_percentage,
        "back_angle": back_angle,
        "knee_alignment": knee_deviation_normalized,  # Positive = knees caving in, Negative = knees bowing out
        "hip_y": hip_center[1],
        "knee_y": knee_center[1]
    }

def calculate_angle(point1, point2, point3):
    """Calculate angle between three points"""
    import math
    
    a = math.sqrt((point2[0] - point3[0])**2 + (point2[1] - point3[1])**2)
    b = math.sqrt((point1[0] - point3[0])**2 + (point1[1] - point3[1])**2)
    c = math.sqrt((point1[0] - point2[0])**2 + (point1[1] - point2[1])**2)
    
    if a == 0 or b == 0 or c == 0:
        return 0
    
    angle = math.acos((a**2 + b**2 - c**2) / (2 * a * b))
    return math.degrees(angle)

def summarize_pose(pose_data):
    """Summarize pose data into natural language metrics"""
    if not pose_data:
        return "No pose data available"
    
    # Calculate averages
    avg_depth = sum(p["depth_percentage"] for p in pose_data) / len(pose_data)
    avg_back_angle = sum(p["back_angle"] for p in pose_data) / len(pose_data)
    avg_knee_alignment = sum(p.get("knee_alignment", p.get("knee_valgus", 0)) for p in pose_data) / len(pose_data)
    
    # Determine depth quality
    if avg_depth < 0.3:
        depth_desc = "very shallow"
    elif avg_depth < 0.6:
        depth_desc = "shallow"
    elif avg_depth < 0.8:
        depth_desc = "moderate"
    else:
        depth_desc = "good"
    
    # Determine back angle quality
    if avg_back_angle < 45:
        back_desc = "very rounded"
    elif avg_back_angle < 60:
        back_desc = "rounded"
    elif avg_back_angle < 75:
        back_desc = "slightly rounded"
    else:
        back_desc = "straight"
    
    # Determine knee position
    if abs(avg_knee_alignment) > 0.1:
        knee_desc = "caving inward" if avg_knee_alignment > 0 else "bowing outward"
    else:
        knee_desc = "aligned"
    
    return f"depth: {depth_desc}, back: {back_desc}, knees: {knee_desc}"

def calculate_form_score(pose_data):
    """Calculate overall form score based on pose metrics"""
    if not pose_data:
        return 0.0
    
    scores = []
    for pose in pose_data:
        # Depth score (0-1)
        depth_score = min(1.0, pose["depth_percentage"] / 0.8)
        
        # Back angle score (0-1)
        back_angle = pose["back_angle"]
        if back_angle > 75:
            back_score = 1.0
        elif back_angle > 60:
            back_score = 0.8
        elif back_angle > 45:
            back_score = 0.6
        else:
            back_score = 0.3
        
        # Knee alignment score (0-1)
        knee_alignment = abs(pose.get("knee_alignment", pose.get("knee_valgus", 0)))
        if knee_alignment < 0.05:
            knee_score = 1.0
        elif knee_alignment < 0.1:
            knee_score = 0.7
        else:
            knee_score = 0.4
        
        # Overall score
        frame_score = (depth_score + back_score + knee_score) / 3
        scores.append(frame_score)
    
    return sum(scores) / len(scores)

def estimate_rep_count(pose_data):
    """Estimate rep count based on pose depth changes"""
    if len(pose_data) < 10:
        return 1
    
    # Look for depth variations that indicate squat cycles
    depths = [p["depth_percentage"] for p in pose_data]
    threshold = 0.3  # Minimum depth to count as a rep
    
    reps = 0
    in_squat = False
    
    for depth in depths:
        if depth > threshold and not in_squat:
            reps += 1
            in_squat = True
        elif depth < threshold:
            in_squat = False
    
    return max(1, reps)

def get_feedback_from_gpt(summary):
    """Get feedback from GPT-4 based on pose summary"""
    try:
        prompt = f"""You are an AI fitness coach analyzing a squat workout. The form analysis shows: {summary}

Please provide:
1. A brief assessment of the squat form
2. Specific improvement suggestions
3. Encouragement and motivation
4. Next steps for improvement

Keep the response concise (2-3 sentences), positive, and actionable. Focus on form quality and safety."""
        
        openai_request = {
            "model": "gpt-4",
            "messages": [
                {
                    "role": "user",
                    "content": prompt
                }
            ],
            "max_tokens": 200,
            "temperature": 0.7
        }
        
        headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {openAIAPIKey}"
        }
        
        response = requests.post(
            "https://api.openai.com/v1/chat/completions",
            json=openai_request,
            headers=headers,
            timeout=30
        )
        
        if response.status_code == 200:
            result = response.json()
            return result["choices"][0]["message"]["content"].strip()
        else:
            return f"Form analysis: {summary}. Keep practicing and focus on proper form."
            
    except Exception as e:
        logger.error(f"OpenAI API error: {e}")
        return f"Form analysis: {summary}. Keep practicing and focus on proper form."

def generateOpenAIPrompt(mediaPipeResults):
    """Generate a prompt for OpenAI based on MediaPipe results"""
    repCount = mediaPipeResults.get("rep_count", 0)
    formScore = mediaPipeResults.get("form_score", 0.0)
    totalFrames = mediaPipeResults.get("total_frames", 0)
    issues = mediaPipeResults.get("issues", [])
    
    issues_text = ", ".join(issues) if issues else "None"
    
    return f"""You are an AI fitness coach analyzing a workout video. Here are the analysis results:

- Exercise Type: Squat
- Repetitions Detected: {repCount}
- Form Score: {formScore * 100:.1f}%
- Total Frames: {totalFrames}
- Issues Detected: {issues_text}

Please provide:
1. A brief assessment of the workout quality
2. Specific form improvement suggestions
3. Encouragement and motivation
4. Next steps for improvement

Keep the response concise, positive, and actionable. Focus on form quality and safety."""

def callOpenAIAPI(request, workoutId):
    """Call OpenAI API with the analysis results"""
    try:
        prompt = generateOpenAIPrompt(request)
        
        openai_request = {
            "model": "gpt-3.5-turbo",
            "messages": [
                {
                    "role": "user",
                    "content": prompt
                }
            ],
            "max_tokens": 500,
            "temperature": 0.7
        }
        
        headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {openAIAPIKey}"
        }
        
        response = requests.post(
            "https://api.openai.com/v1/chat/completions",
            headers=headers,
            json=openai_request,
            timeout=30
        )
        
        if response.status_code == 200:
            data = response.json()
            if "choices" in data and len(data["choices"]) > 0:
                content = data["choices"][0]["message"]["content"]
                
                # Store results in Firebase
                results = {
                    "workout_id": workoutId,
                    "openai_feedback": content,
                    "timestamp": int(time.time()),
                    "model": "gpt-3.5-turbo"
                }
                
                storeAnalysisResults(results, workoutId)
                logger.info(f"OpenAI analysis completed for workout: {workoutId}")
                return True
            else:
                logger.error("Invalid response format from OpenAI API")
                return False
        else:
            logger.error(f"OpenAI API error: {response.status_code} - {response.text}")
            return False
            
    except Exception as e:
        logger.error(f"Error calling OpenAI API: {e}")
        return False

def storeAnalysisResults(results, workoutId):
    """Store analysis results in Firebase Storage"""
    try:
        bucket = firebase_storage.bucket('chiron-6c955.firebasestorage.app')
        blob = bucket.blob(f"analysis-results/{workoutId}/results.json")
        
        # Convert results to JSON
        results_json = json.dumps(results, indent=2)
        logger.info(f"📁 Storing analysis results for workout: {workoutId}")
        logger.info(f"📊 Results size: {len(results_json)} bytes")
        logger.info(f"📋 Results keys: {list(results.keys())}")
        
        blob.upload_from_string(results_json, content_type='application/json')
        
        logger.info(f"✅ Analysis results stored successfully for workout: {workoutId}")
        logger.info(f"📁 File path: analysis-results/{workoutId}/results.json")
    except Exception as e:
        logger.error(f"❌ Error storing analysis results: {e}")
        logger.error(f"❌ Error details: {str(e)}")

# OpenAI API Key (you can set this as an environment variable)
openAIAPIKey = "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"

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({
        "status": "healthy",
        "service": "pose-analysis-service",
        "version": "1.0.0",
        "features": ["video_download", "motion_detection", "basic_analysis"]
    }), 200

@app.route('/analyze-pose', methods=['POST'])
def analyze_pose():
    """Analyze pose from video URL using MediaPipe"""
    try:
        data = request.get_json()
        
        if not data:
            return jsonify({"error": "No JSON data provided"}), 400
        
        video_url = data.get('video_url')
        workout_id = data.get('workout_id')
        exercise_type = data.get('exercise_type', 'squat')
        
        if not video_url:
            return jsonify({"error": "video_url is required"}), 400
        
        logger.info(f"Starting MediaPipe pose analysis for workout: {workout_id}")
        
        # Download video from Firebase
        video_path = download_video_from_firebase(video_url)
        
        try:
            # Analyze pose using MediaPipe
            analysis_result = analyze_pose_from_video(video_path)
            
            # Add metadata
            analysis_result.update({
                "workout_id": workout_id,
                "exercise_type": exercise_type,
                "video_url": video_url,
                "analysis_timestamp": int(time.time()),
                "analysis_type": "mediapipe_openai"
            })
            
            # Store analysis results
            storeAnalysisResults(analysis_result, workout_id)
            
            logger.info(f"MediaPipe pose analysis completed for workout: {workout_id}")
            
            # Return structured response
            return jsonify({
                "feedback": analysis_result.get("feedback", "No feedback available"),
                "summary": analysis_result.get("pose_summary", "No pose data available"),
                "form_score": analysis_result.get("form_score", 0.0),
                "rep_count": analysis_result.get("rep_count", 0),
                "motion_detected": analysis_result.get("motion_detected", False),
                "analysis_quality": analysis_result.get("analysis_quality", "poor"),
                "workout_id": workout_id,
                "exercise_type": exercise_type,
                "analysis_timestamp": analysis_result.get("analysis_timestamp"),
                "analysis_type": "mediapipe_openai"
            }), 200
            
        finally:
            # Clean up temporary file
            if os.path.exists(video_path):
                os.unlink(video_path)
                
    except Exception as e:
        logger.error(f"Error in MediaPipe pose analysis: {e}")
        return jsonify({
            "error": "MediaPipe pose analysis failed",
            "details": str(e)
        }), 500

@app.route('/', methods=['GET'])
def root():
    """Root endpoint"""
    return jsonify({
        "service": "Pose Analysis Service",
        "version": "1.0.0",
        "endpoints": {
            "health": "/health",
            "analyze": "/analyze-pose"
        },
        "note": "Simplified version without MediaPipe. Full MediaPipe integration coming soon."
    }), 200

if __name__ == '__main__':
    # Get port from environment variable or default to 8080
    port = int(os.environ.get('PORT', 8080))
    
    # Run the app
    app.run(host='0.0.0.0', port=port, debug=False) 