#!/bin/bash

echo "🔧 Fixing Info.plist conflict..."

# Check if Info.plist exists
if [ -f "Chiron/Info.plist" ]; then
    echo "✅ Found manual Info.plist file"
    echo ""
    echo "📋 The issue is that your project has:"
    echo "1. GENERATE_INFOPLIST_FILE = YES (auto-generates Info.plist)"
    echo "2. Manual Info.plist file"
    echo ""
    echo "This causes 'Multiple commands produce' error."
    echo ""
    echo "🔧 Solution:"
    echo "1. Open Xcode"
    echo "2. Select your project in the navigator"
    echo "3. Select the 'Chiron' target"
    echo "4. Go to 'Build Settings' tab"
    echo "5. Search for 'Generate Info.plist'"
    echo "6. Set 'GENERATE_INFOPLIST_FILE' to 'NO'"
    echo "7. Make sure Info.plist is added to your project"
    echo ""
    echo "📁 Alternative solution (if you prefer auto-generated):"
    echo "1. Delete the manual Info.plist file"
    echo "2. Add permissions to project settings:"
    echo "   - INFOPLIST_KEY_NSMicrophoneUsageDescription"
    echo "   - INFOPLIST_KEY_NSSpeechRecognitionUsageDescription"
    echo "   - INFOPLIST_KEY_NSCameraUsageDescription"
    echo ""
    echo "🎯 After fixing:"
    echo "1. Clean Build Folder (Cmd+Shift+K)"
    echo "2. Build (Cmd+B)"
else
    echo "❌ No manual Info.plist found"
    echo "The project should be using auto-generated Info.plist"
fi

echo ""
echo "🔍 Current project structure:"
ls -la Chiron/ | grep -E "\.(plist|swift)$" 