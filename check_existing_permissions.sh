#!/bin/bash

echo "🔍 Checking existing project permissions..."

# Check the project file for existing Info.plist keys
echo "📋 Looking for existing INFOPLIST_KEY settings in project file..."

# Search for existing camera permission
if grep -q "INFOPLIST_KEY_NSCameraUsageDescription" Chiron.xcodeproj/project.pbxproj; then
    echo "✅ INFOPLIST_KEY_NSCameraUsageDescription already exists"
    grep "INFOPLIST_KEY_NSCameraUsageDescription" Chiron.xcodeproj/project.pbxproj
else
    echo "❌ INFOPLIST_KEY_NSCameraUsageDescription not found"
fi

echo ""

# Search for microphone permission
if grep -q "INFOPLIST_KEY_NSMicrophoneUsageDescription" Chiron.xcodeproj/project.pbxproj; then
    echo "✅ INFOPLIST_KEY_NSMicrophoneUsageDescription already exists"
    grep "INFOPLIST_KEY_NSMicrophoneUsageDescription" Chiron.xcodeproj/project.pbxproj
else
    echo "❌ INFOPLIST_KEY_NSMicrophoneUsageDescription not found"
fi

echo ""

# Search for speech recognition permission
if grep -q "INFOPLIST_KEY_NSSpeechRecognitionUsageDescription" Chiron.xcodeproj/project.pbxproj; then
    echo "✅ INFOPLIST_KEY_NSSpeechRecognitionUsageDescription already exists"
    grep "INFOPLIST_KEY_NSSpeechRecognitionUsageDescription" Chiron.xcodeproj/project.pbxproj
else
    echo "❌ INFOPLIST_KEY_NSSpeechRecognitionUsageDescription not found"
fi

echo ""
echo "🎯 Based on the error, you only need to add:"
echo "1. INFOPLIST_KEY_NSMicrophoneUsageDescription"
echo "2. INFOPLIST_KEY_NSSpeechRecognitionUsageDescription"
echo ""
echo "The camera permission is already configured!" 