#!/bin/bash

echo "🔍 Checking for common warnings in the codebase..."

echo ""
echo "📋 Common Swift warnings to look for:"
echo "1. Unused variables (let/var that are never used)"
echo "2. Unused imports"
echo "3. Deprecated API usage"
echo "4. Force unwrapping (!) without proper checks"
echo "5. Unused function parameters"
echo "6. Missing documentation comments"
echo ""

echo "🔍 Checking for unused imports..."
grep -r "import " Chiron/ --include="*.swift" | sort | uniq

echo ""
echo "🔍 Checking for force unwrapping..."
grep -r "!" Chiron/ --include="*.swift" | head -10

echo ""
echo "🔍 Checking for unused variables..."
grep -r "let " Chiron/ --include="*.swift" | head -10

echo ""
echo "🎯 To fix warnings in Xcode:"
echo "1. Open Xcode"
echo "2. Go to Product → Build (Cmd+B)"
echo "3. Look at the warnings in the Issue Navigator"
echo "4. Click on each warning to see the specific issue"
echo "5. Fix each warning one by one"
echo ""
echo "💡 Common fixes:"
echo "- Remove unused imports"
echo "- Remove unused variables"
echo "- Add proper nil checks instead of force unwrapping"
echo "- Add documentation comments for public functions"
echo "- Use optional binding instead of force unwrapping" 