#!/bin/bash

echo "🧹 Cleaning Chiron build issues..."

# Clean derived data
echo "📁 Cleaning derived data..."
rm -rf ~/Library/Developer/Xcode/DerivedData/Chiron-*

# Clean build folder
echo "🔨 Cleaning build folder..."
rm -rf build/

# Clean Xcode cache
echo "🗑️ Cleaning Xcode cache..."
rm -rf ~/Library/Caches/com.apple.dt.Xcode/

# Remove any duplicate files that might cause issues
echo "🔍 Checking for duplicate files..."

# Check for duplicate PNG files
find . -name "*.png" -not -path "./Chiron/Assets.xcassets/*" -not -path "./.git/*" | while read file; do
    echo "⚠️ Found potential duplicate: $file"
done

echo "✅ Build cleanup complete!"
echo ""
echo "📋 Next steps:"
echo "1. Open Xcode"
echo "2. Clean Build Folder (Cmd+Shift+K)"
echo "3. Build the project (Cmd+B)"
echo "4. If issues persist, check the project navigator for any red files"
echo ""
echo "🔧 If you still see build errors:"
echo "- Check that all Swift files are properly added to the project"
echo "- Verify Firebase dependencies are added in Xcode"
echo "- Ensure Info.plist is properly configured" 