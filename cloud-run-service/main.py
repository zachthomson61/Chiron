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

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Initialize Firebase Admin SDK
try:
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

# ---------------------------------------------------------------------------
# Coaching contract — mirrors docs/coaching_contract.json
# Swift and Python must stay in sync.
# ---------------------------------------------------------------------------

ISSUE_DEFINITIONS = {
    "insufficient_depth": {
        "display_name": "Insufficient Depth",
        "severity": "high",
        "cue": "Sit deeper until hips reach knee level",
    },
    "forward_lean": {
        "display_name": "Forward Lean",
        "severity": "high",
        "cue": "Keep your chest tall and proud",
    },
    "knee_valgus": {
        "display_name": "Knees Caving In",
        "severity": "medium",
        "cue": "Push your knees out over your toes",
    },
    "knee_varus": {
        "display_name": "Knees Bowing Out",
        "severity": "low",
        "cue": "Keep your knees tracking straight ahead",
    },
}

PRIORITY_ORDER = [
    "insufficient_depth",
    "forward_lean",
    "knee_valgus",
    "knee_varus",
]

THRESHOLDS = {
    "depth_shallow": 0.35,
    "depth_good": 0.6,
    "forward_lean": 35.0,
    "knee_valgus": -0.2,
    "knee_varus": 0.2,
}

POSITIVE_THRESHOLDS = {
    "good_depth": 0.6,
    "chest_tall": 25.0,
    "knees_tracking": 0.1,
}

POSITIVE_NOTES = {
    "good_depth": "good depth on that set",
    "chest_tall": "chest stayed nice and tall",
    "knees_tracking": "knees tracked well over your toes",
    "controlled_tempo": "tempo stayed controlled",
}

FEEDBACK_STATES = [
    "confidence_low",
    "insufficient_visibility",
    "too_few_reps",
    "metrics_inconclusive",
]

MAX_ISSUES_IN_PAYLOAD = 2

# ---------------------------------------------------------------------------
# Firebase download
# ---------------------------------------------------------------------------

def download_video_from_firebase(video_url):
    """Download video from Firebase Storage"""
    try:
        import urllib.parse

        if 'firebasestorage.googleapis.com' in video_url:
            bucket_name = 'chiron-6c955.firebasestorage.app'
            blob_name_encoded = video_url.split('/o/')[-1].split('?')[0]
            blob_name = urllib.parse.unquote(blob_name_encoded)
        else:
            bucket_name = 'chiron-6c955.firebasestorage.app'
            blob_name = video_url.split('/')[-1]

        logger.info(f"Attempting to download blob: {blob_name}")
        bucket = firebase_storage.bucket(bucket_name)
        blob = bucket.blob(blob_name)

        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.mp4')
        blob.download_to_filename(temp_file.name)
        logger.info(f"Video downloaded successfully: {temp_file.name}")
        return temp_file.name
    except Exception as e:
        logger.error(f"Error downloading video: {e}")
        raise

# ---------------------------------------------------------------------------
# Pose metrics extraction (unchanged)
# ---------------------------------------------------------------------------

def calculate_pose_metrics(landmarks, frame_shape):
    """Calculate pose metrics from MediaPipe landmarks"""
    height, width = frame_shape[:2]

    def get_coord(landmark):
        return (int(landmark.x * width), int(landmark.y * height))

    left_hip = get_coord(landmarks[mp.solutions.pose.PoseLandmark.LEFT_HIP])
    right_hip = get_coord(landmarks[mp.solutions.pose.PoseLandmark.RIGHT_HIP])
    left_knee = get_coord(landmarks[mp.solutions.pose.PoseLandmark.LEFT_KNEE])
    right_knee = get_coord(landmarks[mp.solutions.pose.PoseLandmark.RIGHT_KNEE])
    left_ankle = get_coord(landmarks[mp.solutions.pose.PoseLandmark.LEFT_ANKLE])
    right_ankle = get_coord(landmarks[mp.solutions.pose.PoseLandmark.RIGHT_ANKLE])
    left_shoulder = get_coord(landmarks[mp.solutions.pose.PoseLandmark.LEFT_SHOULDER])
    right_shoulder = get_coord(landmarks[mp.solutions.pose.PoseLandmark.RIGHT_SHOULDER])

    hip_center = ((left_hip[0] + right_hip[0]) // 2, (left_hip[1] + right_hip[1]) // 2)
    knee_center = ((left_knee[0] + right_knee[0]) // 2, (left_knee[1] + right_knee[1]) // 2)
    ankle_center = ((left_ankle[0] + right_ankle[0]) // 2, (left_ankle[1] + right_ankle[1]) // 2)
    shoulder_center = ((left_shoulder[0] + right_shoulder[0]) // 2,
                       (left_shoulder[1] + right_shoulder[1]) // 2)

    depth = abs(hip_center[1] - knee_center[1])
    max_depth = height * 0.4
    depth_percentage = min(1.0, depth / max_depth)

    back_angle = calculate_angle(shoulder_center, hip_center, ankle_center)

    knee_deviation = abs(left_knee[0] - right_knee[0]) - abs(left_ankle[0] - right_ankle[0])
    knee_deviation_normalized = knee_deviation / width

    return {
        "depth_percentage": depth_percentage,
        "back_angle": back_angle,
        "knee_alignment": knee_deviation_normalized,
        "hip_y": hip_center[1],
        "knee_y": knee_center[1],
    }


def calculate_angle(point1, point2, point3):
    """Calculate angle between three points"""
    import math

    a = math.sqrt((point2[0] - point3[0])**2 + (point2[1] - point3[1])**2)
    b = math.sqrt((point1[0] - point3[0])**2 + (point1[1] - point3[1])**2)
    c = math.sqrt((point1[0] - point2[0])**2 + (point1[1] - point2[1])**2)

    if a == 0 or b == 0 or c == 0:
        return 0

    cos_val = max(-1.0, min(1.0, (a**2 + b**2 - c**2) / (2 * a * b)))
    angle = math.acos(cos_val)
    return math.degrees(angle)


def calculate_form_score(pose_data):
    """Calculate overall form score (0-1) from per-frame metrics."""
    if not pose_data:
        return 0.0

    scores = []
    for pose in pose_data:
        depth_score = min(1.0, pose["depth_percentage"] / 0.8)
        back_angle = pose["back_angle"]
        if back_angle > 75:
            back_score = 1.0
        elif back_angle > 60:
            back_score = 0.8
        elif back_angle > 45:
            back_score = 0.6
        else:
            back_score = 0.3
        knee_alignment = abs(pose.get("knee_alignment", 0))
        if knee_alignment < 0.05:
            knee_score = 1.0
        elif knee_alignment < 0.1:
            knee_score = 0.7
        else:
            knee_score = 0.4
        scores.append((depth_score + back_score + knee_score) / 3)

    return sum(scores) / len(scores)


def estimate_rep_count(pose_data):
    """Estimate rep count from depth oscillations."""
    if len(pose_data) < 10:
        return 1

    depths = [p["depth_percentage"] for p in pose_data]
    threshold = 0.3
    reps = 0
    in_squat = False

    for depth in depths:
        if depth > threshold and not in_squat:
            reps += 1
            in_squat = True
        elif depth < threshold:
            in_squat = False

    return max(1, reps)


# ---------------------------------------------------------------------------
# Pipeline: metrics → flags → issues → phrasing payload
# ---------------------------------------------------------------------------

def compute_issues_from_metrics(avg_depth, avg_back_angle, avg_knee_alignment):
    """Deterministic issue detection from aggregated metrics.
    Returns a list of issue_code strings, already in priority order."""
    issues = []
    if avg_depth < THRESHOLDS["depth_shallow"]:
        issues.append("insufficient_depth")
    if avg_back_angle > THRESHOLDS["forward_lean"]:
        issues.append("forward_lean")
    if avg_knee_alignment < THRESHOLDS["knee_valgus"]:
        issues.append("knee_valgus")
    elif avg_knee_alignment > THRESHOLDS["knee_varus"]:
        issues.append("knee_varus")
    return issues


def rank_issues(issues):
    """Sort by contract priority and cap at MAX_ISSUES_IN_PAYLOAD."""
    priority_map = {code: idx for idx, code in enumerate(PRIORITY_ORDER)}
    ranked = sorted(issues, key=lambda c: priority_map.get(c, 999))
    return ranked[:MAX_ISSUES_IN_PAYLOAD]


def detect_positive_note(avg_depth, avg_back_angle, avg_knee_alignment):
    """Pick the best positive note, or default to controlled_tempo."""
    if avg_depth >= POSITIVE_THRESHOLDS["good_depth"]:
        return POSITIVE_NOTES["good_depth"]
    if avg_back_angle <= POSITIVE_THRESHOLDS["chest_tall"]:
        return POSITIVE_NOTES["chest_tall"]
    if abs(avg_knee_alignment) <= POSITIVE_THRESHOLDS["knees_tracking"]:
        return POSITIVE_NOTES["knees_tracking"]
    return POSITIVE_NOTES["controlled_tempo"]


def determine_feedback_state(rep_count, form_score, pose_frame_count):
    """Gate: check confidence / data quality before generating feedback."""
    if rep_count <= 0:
        return "too_few_reps"
    if pose_frame_count < 5:
        return "insufficient_visibility"
    if form_score < 0.08:
        return "metrics_inconclusive"
    return None  # normal


def build_phrasing_payload(issues, positive_note, rep_count, feedback_state):
    """Build the compact phrasing payload (the ONLY input to the LLM)."""
    ranked = rank_issues(issues)
    primary = ranked[0] if ranked else None
    secondary = ranked[1] if len(ranked) > 1 else None

    # Suppress secondary when primary is high severity
    if primary and ISSUE_DEFINITIONS.get(primary, {}).get("severity") == "high":
        secondary = None

    return {
        "primary_issue": primary,
        "secondary_issue": secondary,
        "positive_note": positive_note,
        "rep_count": rep_count,
        "feedback_state": feedback_state,
    }


# ---------------------------------------------------------------------------
# LLM phrasing (phrasing only — no assessment)
# ---------------------------------------------------------------------------

def get_phrased_feedback(payload):
    """Ask the LLM to phrase the pre-determined payload into one natural sentence.
    No raw metrics are sent. The model must NOT assess form or invent new issues."""
    primary_code = payload.get("primary_issue")
    primary_def = ISSUE_DEFINITIONS.get(primary_code, {}) if primary_code else {}
    secondary_code = payload.get("secondary_issue")
    secondary_def = ISSUE_DEFINITIONS.get(secondary_code, {}) if secondary_code else {}

    payload_json = json.dumps(payload, indent=2)

    prompt = f"""You are phrasing pre-determined coaching feedback for a squat set.

PHRASING_PAYLOAD:
{payload_json}

RESOLVED CONTEXT:
- Primary issue: {primary_def.get('display_name', 'none')} — cue: {primary_def.get('cue', 'none')}
- Secondary issue: {secondary_def.get('display_name', 'none')}
- Positive note: {payload.get('positive_note', 'none')}
- Rep count: {payload.get('rep_count', 0)}

RULES:
1. Start with a short positive phrase about what they did well (use the positive_note).
2. Then give ONE specific coaching cue for the primary issue (use the cue text, rephrased naturally).
3. If there is a secondary issue, weave it in briefly.
4. If there is no primary issue, give praise only.
5. Do NOT assess form, do NOT suggest new issues, do NOT interpret metrics.
6. Do NOT use technical terms (eccentric, concentric, valgus, varus).
7. Keep it 12-18 words, conversational, encouraging.

EXAMPLES:
"There we go, good depth — now push those knees out a bit more"
"Nice control there, just keep that chest tall on the way down"
"Solid set, everything looked great — keep that same form"
"""

    try:
        openai_request = {
            "model": "gpt-4",
            "messages": [
                {
                    "role": "system",
                    "content": (
                        "You are a natural, encouraging athletic trainer. "
                        "You only PHRASE pre-determined feedback — you never assess form "
                        "or invent new issues. Use simple everyday language."
                    ),
                },
                {"role": "user", "content": prompt},
            ],
            "max_tokens": 40,
            "temperature": 0.7,
        }

        headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {openAIAPIKey}",
        }

        response = requests.post(
            "https://api.openai.com/v1/chat/completions",
            json=openai_request,
            headers=headers,
            timeout=30,
        )

        if response.status_code == 200:
            result = response.json()
            return result["choices"][0]["message"]["content"].strip()
        else:
            return _fallback_feedback(payload)

    except Exception as e:
        logger.error(f"OpenAI API error: {e}")
        return _fallback_feedback(payload)


def _fallback_feedback(payload):
    """Deterministic fallback when LLM is unavailable."""
    positive = payload.get("positive_note") or "Nice effort there"
    primary = payload.get("primary_issue")
    if not primary:
        return f"{positive.capitalize()} — keep that same form."
    cue = ISSUE_DEFINITIONS.get(primary, {}).get("cue", "focus on your form")
    return f"{positive.capitalize()}, now {cue.lower()}."


# ---------------------------------------------------------------------------
# Main analysis pipeline
# ---------------------------------------------------------------------------

def analyze_pose_from_video(video_path):
    """Full pipeline: pose -> metrics -> flags -> issues -> phrasing payload -> LLM feedback."""
    mp_pose = mp.solutions.pose
    pose = mp_pose.Pose(
        static_image_mode=False,
        model_complexity=1,
        smooth_landmarks=True,
        enable_segmentation=False,
        smooth_segmentation=True,
        min_detection_confidence=0.3,
        min_tracking_confidence=0.3,
    )

    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise ValueError("Could not open video file")

    frame_count = 0
    pose_data = []
    motion_detected = False

    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    fps = cap.get(cv2.CAP_PROP_FPS)
    sample_rate = max(1, int(fps / 10))

    logger.info(f"Video: {total_frames} frames, {fps} fps, sampling every {sample_rate} frames")

    while cap.isOpened():
        ret, frame = cap.read()
        if not ret:
            break
        frame_count += 1
        if frame_count % sample_rate != 0:
            continue

        rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        results = pose.process(rgb_frame)

        if results.pose_landmarks:
            landmarks = results.pose_landmarks.landmark
            pose_metrics = calculate_pose_metrics(landmarks, frame.shape)
            pose_data.append(pose_metrics)
            motion_detected = True

    cap.release()
    pose.close()

    logger.info(f"Processed {len(pose_data)} pose frames from {frame_count} total frames")

    if not pose_data:
        return {
            "total_frames": frame_count,
            "rep_count": 0,
            "form_score": 0.0,
            "motion_detected": False,
            "motion_percentage": 0,
            "analysis_quality": "poor",
            "issues": [],
            "phrasing_payload": {"feedback_state": "insufficient_visibility"},
            "feedback": "No human pose detected in the video. Please ensure you are visible in the camera frame.",
        }

    # --- Aggregate metrics ---
    avg_depth = sum(p["depth_percentage"] for p in pose_data) / len(pose_data)
    avg_back_angle = sum(p["back_angle"] for p in pose_data) / len(pose_data)
    avg_knee_alignment = sum(p.get("knee_alignment", 0) for p in pose_data) / len(pose_data)

    form_score = calculate_form_score(pose_data)
    rep_count = estimate_rep_count(pose_data)
    pose_frame_count = len(pose_data)
    motion_percentage = (pose_frame_count / frame_count) * 100 if frame_count > 0 else 0

    # --- Deterministic logic layer ---
    feedback_state = determine_feedback_state(rep_count, form_score, pose_frame_count)

    if feedback_state:
        payload = build_phrasing_payload([], None, rep_count, feedback_state)
        feedback = "Good set. When you're ready, start your next set."
    else:
        issues = compute_issues_from_metrics(avg_depth, avg_back_angle, avg_knee_alignment)
        positive_note = detect_positive_note(avg_depth, avg_back_angle, avg_knee_alignment)
        payload = build_phrasing_payload(issues, positive_note, rep_count, feedback_state)
        feedback = get_phrased_feedback(payload)

    return {
        "total_frames": frame_count,
        "rep_count": rep_count,
        "form_score": form_score,
        "motion_detected": motion_detected,
        "motion_percentage": motion_percentage,
        "analysis_quality": "good" if motion_detected else "poor",
        "issues": payload.get("primary_issue") and [
            i for i in [payload["primary_issue"], payload.get("secondary_issue")] if i
        ] or [],
        "phrasing_payload": payload,
        "feedback": feedback,
        # Metrics kept for logging / analytics / QA — not sent to LLM
        "metrics": {
            "avg_depth": round(avg_depth, 3),
            "avg_back_angle": round(avg_back_angle, 1),
            "avg_knee_alignment": round(avg_knee_alignment, 3),
        },
    }


# ---------------------------------------------------------------------------
# Firebase storage
# ---------------------------------------------------------------------------

def storeAnalysisResults(results, workoutId):
    """Store analysis results in Firebase Storage"""
    try:
        bucket = firebase_storage.bucket('chiron-6c955.firebasestorage.app')
        blob = bucket.blob(f"analysis-results/{workoutId}/results.json")
        results_json = json.dumps(results, indent=2)
        blob.upload_from_string(results_json, content_type='application/json')
        logger.info(f"Analysis results stored for workout: {workoutId}")
    except Exception as e:
        logger.error(f"Error storing analysis results: {e}")

# OpenAI API Key
openAIAPIKey = os.environ.get(
    "OPENAI_API_KEY",
    "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",
)

# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({
        "status": "healthy",
        "service": "pose-analysis-service",
        "version": "2.0.0",
        "pipeline": "pose -> metrics -> flags -> issues -> phrasing_payload -> LLM phrasing",
    }), 200


@app.route('/analyze-pose', methods=['POST'])
def analyze_pose():
    """Full pipeline: video → MediaPipe → metrics → flags → issues → phrasing → feedback."""
    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "No JSON data provided"}), 400

        video_url = data.get('video_url')
        workout_id = data.get('workout_id')
        exercise_type = data.get('exercise_type', 'squat')

        if not video_url:
            return jsonify({"error": "video_url is required"}), 400

        logger.info(f"Starting analysis for workout: {workout_id}")

        video_path = download_video_from_firebase(video_url)

        try:
            analysis_result = analyze_pose_from_video(video_path)

            analysis_result.update({
                "workout_id": workout_id,
                "exercise_type": exercise_type,
                "video_url": video_url,
                "analysis_timestamp": int(time.time()),
                "analysis_type": "mediapipe_phrasing_pipeline",
            })

            storeAnalysisResults(analysis_result, workout_id)

            logger.info(f"Analysis completed for workout: {workout_id}")

            return jsonify({
                "feedback": analysis_result.get("feedback", ""),
                "issues": analysis_result.get("issues", []),
                "phrasing_payload": analysis_result.get("phrasing_payload", {}),
                "form_score": analysis_result.get("form_score", 0.0),
                "rep_count": analysis_result.get("rep_count", 0),
                "motion_detected": analysis_result.get("motion_detected", False),
                "analysis_quality": analysis_result.get("analysis_quality", "poor"),
                "metrics": analysis_result.get("metrics", {}),
                "workout_id": workout_id,
                "exercise_type": exercise_type,
                "analysis_timestamp": analysis_result.get("analysis_timestamp"),
                "analysis_type": "mediapipe_phrasing_pipeline",
            }), 200

        finally:
            if os.path.exists(video_path):
                os.unlink(video_path)

    except Exception as e:
        logger.error(f"Error in analysis: {e}")
        return jsonify({
            "error": "Analysis failed",
            "details": str(e),
        }), 500


@app.route('/', methods=['GET'])
def root():
    return jsonify({
        "service": "Pose Analysis Service",
        "version": "2.0.0",
        "pipeline": "pose -> metrics -> flags -> issues -> phrasing_payload -> LLM phrasing",
        "endpoints": {
            "health": "/health",
            "analyze": "/analyze-pose",
        },
    }), 200


if __name__ == '__main__':
    port = int(os.environ.get('PORT', 8080))
    app.run(host='0.0.0.0', port=port, debug=False)
