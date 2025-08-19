#!/bin/bash

echo "🔍 Diagnosing installation error..."

echo ""
echo "📋 Error Analysis:"
echo "Domain: com.apple.dt.CoreDeviceError"
echo "Code: 3000/3002"
echo "Issue: 'The item at Chiron.app is not a valid bundle'"
echo ""

echo "🔍 Checking built app bundle..."
BUILT_APP=$(find ~/Library/Developer/Xcode/DerivedData/Chiron-*/Build/Products/Debug-iphoneos/Chiron.app -maxdepth 0 -type d 2>/dev/null | head -1)

if [ -n "$BUILT_APP" ]; then
    echo "✅ Built app found: $BUILT_APP"
    
    echo ""
    echo "📋 Bundle contents:"
    ls -la "$BUILT_APP/"
    
    echo ""
    echo "📋 Info.plist contents:"
    if [ -f "$BUILT_APP/Info.plist" ]; then
        plutil -p "$BUILT_APP/Info.plist" | grep -E "(CFBundleIdentifier|CFBundleName|CFBundleVersion|CFBundlePackageType)"
    else
        echo "❌ Info.plist not found in built app"
    fi
    
    echo ""
    echo "📋 Code signing status:"
    codesign -dv "$BUILT_APP" 2>&1 | grep -E "(Identifier|TeamIdentifier|Format)"
    
    echo ""
    echo "📋 Provisioning profile:"
    if [ -f "$BUILT_APP/embedded.mobileprovision" ]; then
        echo "✅ embedded.mobileprovision exists"
        security cms -D -i "$BUILT_APP/embedded.mobileprovision" 2>/dev/null | plutil -extract Entitlements.plist raw - | plutil -extract com.apple.developer.team-identifier raw - 2>/dev/null || echo "Could not extract team identifier"
    else
        echo "❌ embedded.mobileprovision not found"
    fi
else
    echo "❌ Built app not found"
fi

echo ""
echo "🔍 Checking Xcode project settings..."
if [ -f "Chiron.xcodeproj/project.pbxproj" ]; then
    echo "📋 Bundle Identifier settings:"
    grep -A 2 -B 2 "PRODUCT_BUNDLE_IDENTIFIER" Chiron.xcodeproj/project.pbxproj | head -10
    
    echo ""
    echo "📋 Info.plist settings:"
    grep -A 2 -B 2 "INFOPLIST_FILE\|GENERATE_INFOPLIST_FILE" Chiron.xcodeproj/project.pbxproj | head -10
    
    echo ""
    echo "📋 Development Team settings:"
    grep -A 2 -B 2 "DEVELOPMENT_TEAM" Chiron.xcodeproj/project.pbxproj | head -10
else
    echo "❌ Project file not found"
fi

echo ""
echo "🔍 Checking connected devices..."
xcrun devicectl list devices | grep -E "(iPhone|iPad)" | head -3

echo ""
echo "🎯 Potential Solutions:"
echo ""
echo "1. **Clean and Rebuild:**"
echo "   - Product → Clean Build Folder (Cmd+Shift+K)"
echo "   - Product → Build (Cmd+B)"
echo "   - Product → Run (Cmd+R)"
echo ""
echo "2. **Check Xcode Project Settings:**"
echo "   - Target → General → Bundle Identifier: com.zachthomson.Chiron"
echo "   - Target → General → Team: Your development team"
echo "   - Target → Build Settings → Info.plist File: Chiron/Info.plist"
echo "   - Target → Build Settings → Generate Info.plist File: NO"
echo ""
echo "3. **Check Provisioning Profile:**"
echo "   - Target → Signing & Capabilities → Automatically manage signing"
echo "   - Or manually select a valid provisioning profile"
echo ""
echo "4. **Check Device Trust:**"
echo "   - On device: Settings → General → VPN & Device Management"
echo "   - Trust your developer certificate"
echo ""
echo "5. **Alternative: Use Simulator First:**"
echo "   - Select iOS Simulator instead of device"
echo "   - Test app functionality in simulator"
echo "   - Then try device deployment"
echo ""
echo "6. **Reset Derived Data:**"
echo "   - Xcode → Preferences → Locations → Derived Data → Delete"
echo "   - Or: rm -rf ~/Library/Developer/Xcode/DerivedData/Chiron-*"
echo ""
echo "7. **Check Xcode Version Compatibility:**"
echo "   - Ensure Xcode 16.4 is compatible with iOS 18.5"
echo "   - Consider updating Xcode if needed" 