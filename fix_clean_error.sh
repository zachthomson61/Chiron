#!/bin/bash

echo "🔧 Fixing Xcode Clean Error..."

echo ""
echo "📋 Error Analysis:"
echo "Could not compute dependency graph: unable to load transferred PIF"
echo "The workspace contains multiple references with the same GUID"
echo ""

echo "🔍 Checking for duplicate package references..."

# Check for duplicate package references in project file
echo "📋 Checking project.pbxproj for duplicate GUIDs..."
if grep -q "PACKAGE:1H6HLX20X79KCNOWHJNU159CNTB8HJSG7" Chiron.xcodeproj/project.pbxproj; then
    echo "⚠️ Found package reference with GUID: PACKAGE:1H6HLX20X79KCNOWHJNU159CNTB8HJSG7"
    echo "This is likely causing the duplicate reference error"
else
    echo "✅ No problematic package GUID found in project file"
fi

echo ""
echo "🔍 Checking for duplicate Swift Package Manager references..."
if [ -f "Package.resolved" ]; then
    echo "📋 Package.resolved file found:"
    cat Package.resolved | head -10
else
    echo "✅ No Package.resolved file found"
fi

echo ""
echo "🔍 Checking for duplicate .xcodeproj files..."
find . -name "*.xcodeproj" -type d

echo ""
echo "🔍 Checking for duplicate .xcworkspace files..."
find . -name "*.xcworkspace" -type d

echo ""
echo "🎯 Solutions to try:"

echo ""
echo "1. **Reset Xcode Derived Data (Recommended):**"
echo "   rm -rf ~/Library/Developer/Xcode/DerivedData/*"
echo "   rm -rf ~/Library/Developer/Xcode/UserData/IDEPackageSupport"

echo ""
echo "2. **Reset Xcode Package Cache:**"
echo "   rm -rf ~/Library/Caches/org.swift.swiftpm"
echo "   rm -rf ~/Library/Developer/Xcode/DerivedData/*/SourcePackages"

echo ""
echo "3. **Close Xcode and Reset:**"
echo "   - Close Xcode completely"
echo "   - Kill any remaining Xcode processes"
echo "   - Reopen Xcode"
echo "   - Try clean again"

echo ""
echo "4. **Check for Duplicate Package Dependencies:**"
echo "   - In Xcode: File → Add Package Dependencies"
echo "   - Look for duplicate Firebase entries"
echo "   - Remove any duplicates"

echo ""
echo "5. **Reset Package Dependencies:**"
echo "   - In Xcode: File → Packages → Reset Package Caches"
echo "   - File → Packages → Resolve Package Versions"

echo ""
echo "6. **Manual Project Cleanup:**"
echo "   - Close Xcode"
echo "   - Delete .xcworkspace file if it exists"
echo "   - Reopen .xcodeproj file"
echo "   - Re-add package dependencies"

echo ""
echo "🚀 Quick Fix Commands:"
echo "The following commands will reset Xcode's cache and should fix the issue:" 