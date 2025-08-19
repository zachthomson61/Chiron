#!/bin/bash

echo "🔧 Fixing Info.plist path issue..."

# Check if Info.plist exists
if [ -f "Chiron/Info.plist" ]; then
    echo "✅ Info.plist file exists at Chiron/Info.plist"
else
    echo "❌ Info.plist file not found"
    exit 1
fi

echo ""
echo "📋 The error indicates Xcode can't find the Info.plist file."
echo "This happens when GENERATE_INFOPLIST_FILE = NO but the file isn't properly referenced."
echo ""
echo "🔧 Solution:"
echo "1. In Xcode, go to Project → Build Settings"
echo "2. Search for 'Info.plist File'"
echo "3. Set INFOPLIST_FILE to: Chiron/Info.plist"
echo ""
echo "Alternative solution:"
echo "1. Set GENERATE_INFOPLIST_FILE back to YES"
echo "2. Add the permissions to project settings instead"
echo ""
echo "🎯 Quick fix:"
echo "1. Open Xcode"
echo "2. Project → Build Settings"
echo "3. Search 'Info.plist File'"
echo "4. Set INFOPLIST_FILE = Chiron/Info.plist"
echo "5. Clean and Build" 