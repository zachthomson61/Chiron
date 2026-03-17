#!/bin/bash
# Downloads the MediaPipe Pose Landmarker model bundle into the Chiron app target.
# Run from the repo root: ./download_pose_model.sh

set -euo pipefail

MODEL_DIR="Chiron/Models/MediaPipe"
MODEL_FILE="pose_landmarker_full.task"
MODEL_URL="https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_full/float16/latest/${MODEL_FILE}"

mkdir -p "$MODEL_DIR"

if [ -f "$MODEL_DIR/$MODEL_FILE" ]; then
    echo "Model already exists at $MODEL_DIR/$MODEL_FILE"
else
    echo "Downloading $MODEL_FILE..."
    curl -L -o "$MODEL_DIR/$MODEL_FILE" "$MODEL_URL"
    echo "Downloaded to $MODEL_DIR/$MODEL_FILE"
fi

echo ""
echo "Next steps:"
echo "  1. In Xcode, drag $MODEL_DIR/$MODEL_FILE into the Chiron target (check 'Copy items if needed')."
echo "  2. Verify it appears in Build Phases > Copy Bundle Resources."
echo "  3. Run 'pod install' in the project root, then open Chiron.xcworkspace."
