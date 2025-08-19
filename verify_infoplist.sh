#!/bin/bash

echo "🔍 Verifying Info.plist file..."

if [ -f "Chiron/Info.plist" ]; then
    echo "✅ Info.plist file exists"
    
    # Check if it's valid XML
    if plutil -lint "Chiron/Info.plist" > /dev/null 2>&1; then
        echo "✅ Info.plist is valid XML"
    else
        echo "❌ Info.plist is not valid XML"
        exit 1
    fi
    
    # Check for required keys
    echo ""
    echo "📋 Checking for required keys:"
    
    # CFBundleIdentifier
    if plutil -extract CFBundleIdentifier raw "Chiron/Info.plist" > /dev/null 2>&1; then
        echo "✅ CFBundleIdentifier exists"
        plutil -extract CFBundleIdentifier raw "Chiron/Info.plist"
    else
        echo "❌ CFBundleIdentifier missing"
    fi
    
    # CFBundleName
    if plutil -extract CFBundleName raw "Chiron/Info.plist" > /dev/null 2>&1; then
        echo "✅ CFBundleName exists"
    else
        echo "❌ CFBundleName missing"
    fi
    
    # CFBundleVersion
    if plutil -extract CFBundleVersion raw "Chiron/Info.plist" > /dev/null 2>&1; then
        echo "✅ CFBundleVersion exists"
    else
        echo "❌ CFBundleVersion missing"
    fi
    
    # CFBundlePackageType
    if plutil -extract CFBundlePackageType raw "Chiron/Info.plist" > /dev/null 2>&1; then
        echo "✅ CFBundlePackageType exists"
    else
        echo "❌ CFBundlePackageType missing"
    fi
    
    # Check permissions
    echo ""
    echo "📋 Checking permissions:"
    
    # Camera permission
    if plutil -extract NSCameraUsageDescription raw "Chiron/Info.plist" > /dev/null 2>&1; then
        echo "✅ NSCameraUsageDescription exists"
    else
        echo "❌ NSCameraUsageDescription missing"
    fi
    
    # Microphone permission
    if plutil -extract NSMicrophoneUsageDescription raw "Chiron/Info.plist" > /dev/null 2>&1; then
        echo "✅ NSMicrophoneUsageDescription exists"
    else
        echo "❌ NSMicrophoneUsageDescription missing"
    fi
    
    # Speech recognition permission
    if plutil -extract NSSpeechRecognitionUsageDescription raw "Chiron/Info.plist" > /dev/null 2>&1; then
        echo "✅ NSSpeechRecognitionUsageDescription exists"
    else
        echo "❌ NSSpeechRecognitionUsageDescription missing"
    fi
    
    echo ""
    echo "🎯 Next steps:"
    echo "1. Clean Build Folder (Cmd+Shift+K)"
    echo "2. Build (Cmd+B)"
    echo "3. Run on device"
    
else
    echo "❌ Info.plist file not found"
    exit 1
fi 