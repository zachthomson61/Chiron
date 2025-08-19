# Adding Firebase Dependencies - Step by Step

## 🎯 **Current Issue**
The error "No such module 'FirebaseCore'" means Firebase isn't added to your project.

## 🔧 **Step-by-Step Solution**

### **Step 1: Add Firebase Package**
1. **In Xcode**, go to **File → Add Package Dependencies**
2. **In the search field**, paste this URL exactly:
   ```
   https://github.com/firebase/firebase-ios-sdk.git
   ```
3. **Click "Add Package"**
4. **Wait for the package to load** (you should see Firebase options)

### **Step 2: Select Firebase Products**
1. **In the package selection screen**, you'll see a list of Firebase products
2. **Check these boxes:**
   - ✅ **FirebaseCore**
   - ✅ **FirebaseStorage**
3. **Click "Add Package"**

### **Step 3: Verify Dependencies**
1. **In the Project Navigator**, look for a new section called **"Package Dependencies"**
2. **You should see "firebase-ios-sdk"** listed there
3. **Expand it** to see the Firebase products

### **Step 4: Check Target Linking**
1. **Select your project** in the navigator
2. **Select the "Chiron" target**
3. **Go to "General" tab**
4. **Scroll down to "Frameworks, Libraries, and Embedded Content"**
5. **You should see:**
   - FirebaseCore
   - FirebaseStorage

### **Step 5: Clean and Build**
1. **Product → Clean Build Folder** (Cmd+Shift+K)
2. **Product → Build** (Cmd+B)

## 🚨 **If Package Dependencies Doesn't Work**

### **Alternative Method: Manual Framework Addition**
1. **In Xcode**, select your project in the navigator
2. **Select the "Chiron" target**
3. **Go to "General" tab**
4. **Scroll down to "Frameworks, Libraries, and Embedded Content"**
5. **Click the "+" button**
6. **Search for "Firebase"**
7. **Add these frameworks:**
   - FirebaseCore
   - FirebaseStorage

## ✅ **Expected Result**
After adding Firebase dependencies:
- ✅ No more "No such module 'FirebaseCore'" errors
- ✅ Build succeeds
- ✅ Firebase upload functionality works
- ✅ Speech integration works

## 🎤 **Speech Integration Status**
All files are ready:
- ✅ **SpeechManager.swift** - Core speech functionality
- ✅ **SpeechControlView.swift** - Speech settings UI
- ✅ **Info.plist** - All permissions configured
- ✅ **WorkoutViewModel** - Speech integration added
- ❌ **Firebase Dependencies** - Need to add (this is what we're fixing)

**Follow these steps exactly and the build should succeed!** 🚀 