#!/bin/bash

echo "🔧 Fixing Chiron build issues..."

# Clean derived data
echo "📁 Cleaning derived data..."
rm -rf ~/Library/Developer/Xcode/DerivedData/Chiron-*

# Clean build folder
echo "🔨 Cleaning build folder..."
rm -rf build/

# Clean Xcode cache
echo "🗑️ Cleaning Xcode cache..."
rm -rf ~/Library/Caches/com.apple.dt.Xcode/

# Remove any remaining duplicate PNG files
echo "🖼️ Removing duplicate PNG files..."
find . -name "*.png" -not -path "./Chiron/Assets.xcassets/*" -not -path "./.git/*" -delete

echo "✅ Build cleanup complete!"
echo ""
echo "📋 Next steps in Xcode:"
echo "1. Open Xcode"
echo "2. Go to Project Settings → Build Settings"
echo "3. Search for 'Generate Info.plist'"
echo "4. Set GENERATE_INFOPLIST_FILE to NO"
echo "5. Add Info.plist to project if not already added"
echo "6. Check for red files in project navigator"
echo "7. Add any missing Swift files to project"
echo "8. Add Firebase dependencies:"
echo "   - File → Add Package Dependencies"
echo "   - https://github.com/firebase/firebase-ios-sdk.git"
echo "   - Select FirebaseCore and FirebaseStorage"
echo "9. Clean Build Folder (Cmd+Shift+K)"
echo "10. Build (Cmd+B)"
echo ""
echo "🎯 If issues persist:"
echo "- Check Build Phases for duplicates"
echo "- Verify all files are in correct target"
echo "- Look for duplicate file references" 