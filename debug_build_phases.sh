#!/bin/bash

echo "🔍 Debugging build phase conflicts..."

# Check for any duplicate files in the project
echo "📁 Checking for duplicate files..."
find . -name "*.swift" -o -name "*.plist" -o -name "*.png" | sort | uniq -d

# Check if there are multiple Info.plist files
echo ""
echo "📋 Checking Info.plist files..."
find . -name "Info.plist" -type f

# Check for any files that might be causing conflicts
echo ""
echo "🔍 Checking for potential conflict sources..."
echo "Files in root directory:"
ls -la | grep -E "\.(plist|swift|png)$"

echo ""
echo "Files in Chiron directory:"
ls -la Chiron/ | grep -E "\.(plist|swift|png)$"

# Check if there are any hidden files that might be causing issues
echo ""
echo "🔍 Checking for hidden files..."
find . -name ".*" -type f | grep -E "\.(plist|swift|png)$"

echo ""
echo "🎯 The issue is likely one of these:"
echo "1. Multiple Info.plist files (manual + auto-generated)"
echo "2. Duplicate Swift files in project"
echo "3. Files added to multiple build phases"
echo "4. Asset catalog conflicts"
echo ""
echo "🔧 Quick fixes to try:"
echo "1. In Xcode: Project → Build Settings → Search 'Generate Info.plist' → Set to NO"
echo "2. In Xcode: Project → Build Phases → Check for duplicate entries"
echo "3. In Xcode: Project Navigator → Look for red files"
echo "4. In Xcode: Assets.xcassets → Check for duplicate images" 