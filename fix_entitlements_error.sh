#!/bin/bash

echo "🔧 Fixing Code Signing and Entitlements Error..."

echo ""
echo "📋 Error Analysis:"
echo "Domain: IXUserPresentableErrorDomain"
echo "Code: 14"
echo "Issue: The executable was signed with invalid entitlements"
echo ""

echo "🔍 Checking current entitlements..."

# Check if entitlements file exists
if [ -f "Chiron/Chiron.entitlements" ]; then
    echo "✅ Entitlements file found: Chiron/Chiron.entitlements"
    echo "📋 Current entitlements:"
    plutil -p "Chiron/Chiron.entitlements"
else
    echo "❌ No entitlements file found"
fi

echo ""
echo "🔍 Checking Xcode project settings..."

# Check code signing settings in project
if [ -f "Chiron.xcodeproj/project.pbxproj" ]; then
    echo "📋 Code signing settings:"
    grep -A 2 -B 2 "CODE_SIGN" Chiron.xcodeproj/project.pbxproj | head -10
    
    echo ""
    echo "📋 Development team settings:"
    grep -A 2 -B 2 "DEVELOPMENT_TEAM" Chiron.xcodeproj/project.pbxproj | head -10
    
    echo ""
    echo "📋 Provisioning profile settings:"
    grep -A 2 -B 2 "PROVISIONING_PROFILE" Chiron.xcodeproj/project.pbxproj | head -10
else
    echo "❌ Project file not found"
fi

echo ""
echo "🔍 Checking built app entitlements..."
BUILT_APP=$(find ~/Library/Developer/Xcode/DerivedData/Chiron-*/Build/Products/Debug-iphoneos/Chiron.app -maxdepth 0 -type d 2>/dev/null | head -1)

if [ -n "$BUILT_APP" ]; then
    echo "✅ Built app found: $BUILT_APP"
    
    echo ""
    echo "📋 Built app entitlements:"
    codesign -d --entitlements :- "$BUILT_APP" 2>/dev/null | plutil -p - || echo "Could not extract entitlements"
    
    echo ""
    echo "📋 Code signing details:"
    codesign -dv "$BUILT_APP" 2>&1 | grep -E "(Identifier|TeamIdentifier|Format|Authority)"
else
    echo "❌ Built app not found"
fi

echo ""
echo "🎯 Solutions to try:"

echo ""
echo "1. **Reset Code Signing (Recommended):**"
echo "   - In Xcode: Target → Signing & Capabilities"
echo "   - Check 'Automatically manage signing'"
echo "   - Select your development team"
echo "   - Let Xcode regenerate provisioning profile"

echo ""
echo "2. **Remove Custom Entitlements:**"
echo "   - In Xcode: Target → Signing & Capabilities"
echo "   - Remove any custom entitlements"
echo "   - Let Xcode use default entitlements"

echo ""
echo "3. **Check Provisioning Profile:**"
echo "   - In Xcode: Target → Signing & Capabilities"
echo "   - Verify provisioning profile is valid"
echo "   - Try 'Download Manual Profiles'"

echo ""
echo "4. **Reset Derived Data and Clean:**"
echo "   - Product → Clean Build Folder"
echo "   - Delete derived data again"
echo "   - Rebuild project"

echo ""
echo "5. **Check Device Trust:**"
echo "   - On device: Settings → General → VPN & Device Management"
echo "   - Trust your developer certificate"
echo "   - Remove and re-trust if needed"

echo ""
echo "6. **Alternative: Use Simulator First:**"
echo "   - Select iOS Simulator instead of device"
echo "   - Test app functionality in simulator"
echo "   - Then try device deployment"

echo ""
echo "🚀 Quick Fix Commands:"
echo "The following will reset code signing and rebuild:" 