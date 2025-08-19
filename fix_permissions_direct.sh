#!/bin/bash

echo "🔧 Adding missing permissions directly to project file..."

# Check if we can modify the project file
if [ ! -w "Chiron.xcodeproj/project.pbxproj" ]; then
    echo "❌ Cannot write to project file. Please close Xcode first."
    exit 1
fi

echo "📋 Current permissions in project:"
grep "INFOPLIST_KEY" Chiron.xcodeproj/project.pbxproj

echo ""
echo "🎯 Missing permissions that need to be added:"
echo "1. INFOPLIST_KEY_NSMicrophoneUsageDescription"
echo "2. INFOPLIST_KEY_NSSpeechRecognitionUsageDescription"
echo ""

echo "💡 Solution:"
echo "1. Close Xcode completely"
echo "2. In Xcode Build Settings, try adding these with slightly different names:"
echo ""
echo "   For Microphone:"
echo "   Name: INFOPLIST_KEY_NSMicrophoneUsageDescription"
echo "   Value: This app uses the microphone for voice commands during workouts."
echo ""
echo "   For Speech Recognition:"
echo "   Name: INFOPLIST_KEY_NSSpeechRecognitionUsageDescription"
echo "   Value: This app uses speech recognition to understand voice commands for workout control."
echo ""
echo "3. If you still get errors, try this alternative approach:"
echo "   - Delete any existing microphone/speech settings first"
echo "   - Then add them fresh"
echo ""
echo "4. Alternative: Add permissions to Info.plist manually"
echo "   - Create a new Info.plist file"
echo "   - Add the permissions there"
echo "   - Set GENERATE_INFOPLIST_FILE = NO" 