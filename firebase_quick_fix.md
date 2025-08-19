# Quick Fix for Firebase Dependencies

## 🎯 **Current Error**
`ChironApp.swift` line 9: `import FirebaseCore` - "No such module 'FirebaseCore'"

## 🔧 **Immediate Solution**

### **Step 1: Add Firebase Package**
1. **In Xcode**, go to **File → Add Package Dependencies**
2. **Copy and paste this URL** into the search field:
   ```
   https://github.com/firebase/firebase-ios-sdk.git
   ```
3. **Click "Add Package"**
4. **Wait for it to load** (you'll see Firebase options appear)

### **Step 2: Select Firebase Products**
1. **In the package selection screen**, you'll see a list of Firebase products
2. **Check these boxes:**
   - ✅ **FirebaseCore**
   - ✅ **FirebaseStorage**
3. **Click "Add Package"**

### **Step 3: Verify It's Added**
1. **In the Project Navigator** (left side), look for **"Package Dependencies"**
2. **You should see "firebase-ios-sdk"** listed there
3. **If you don't see it**, the package wasn't added properly

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

### **Alternative: Manual Framework Addition**
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
After adding Firebase:
- ✅ No more "No such module 'FirebaseCore'" errors
- ✅ `import FirebaseCore` works
- ✅ Build succeeds
- ✅ Speech integration works

**The key is adding the Firebase package dependencies to your project!** 🚀 