# Firebase Setup Guide for ArtListener

## 🚨 IMPORTANT: Fix Firebase Storage Object Not Found Errors

The error you're seeing indicates Firebase Storage security rules are blocking access. Here's how to fix it:

### Step 1: Apply Firebase Storage Security Rules

1. **Go to Firebase Console**: https://console.firebase.google.com/
2. **Select your project**
3. **Go to Storage** (left sidebar)
4. **Click "Rules"** tab
5. **Replace existing rules** with:

```javascript
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    // Allow read access to all files (for exhibit images)
    match /{allPaths=**} {
      allow read: if true;
    }

    // Allow authenticated uploads to exhibits folder
    match /exhibits/{exhibitId}/{allPaths=**} {
      allow create: if request.auth != null;
      allow write: if request.auth != null;
      allow delete: if request.auth != null;
      allow read: if true; // Public read for exhibit images
    }

    // Default deny for security
    match /{allPaths=**} {
      allow read: if false;
      allow write: if false;
      allow create: if false;
      allow delete: if false;
    }
  }
}
```

6. **Click "Publish"**

### Step 2: Enable Authentication

1. **Go to Authentication** (left sidebar)
2. **Click "Get started"** if not enabled
3. **Go to Sign-in method** tab
4. **Enable Anonymous** authentication (required for uploads)

### Step 3: Check Storage Bucket

1. **Go to Storage** → **Files** tab
2. **Make sure you have a storage bucket** (default one should exist)
3. **Check if bucket name matches** your Firebase config

### Step 4: Verify Firebase Configuration

1. **Check `google-services.json`** (Android) or `GoogleService-Info.plist`** (iOS)
2. **Ensure storage bucket URL is correct**
3. **Make sure Firebase project is properly linked**

### Step 5: Test the Fix

1. **Run the app again**
2. **Try creating an exhibit with images**
3. **Check console logs** for success messages

### Common Issues & Solutions:

#### ❌ "object-not-found" Error
**Solution**: Apply the security rules above and enable anonymous authentication

#### ❌ "unauthorized" Error
**Solution**: Make sure anonymous authentication is enabled in Firebase Console

#### ❌ "cancelled" Error
**Solution**: Check internet connection and Firebase project status

#### ❌ Upload Timeout
**Solution**: Use smaller images (< 5MB) and ensure stable internet connection

### Alternative: Disable Image Upload (Temporary)

If you want to test without images temporarily, you can modify the code to skip image uploads:

```dart
// In set_exhibit_page.dart, comment out this line:
// photoUrls = await _uploadAllPicked(exhibitId);

// And use:
// photoUrls = []; // Skip image upload
```

### Expected Behavior After Fix:

✅ Firebase Storage validation passes
✅ Image uploads work with progress indicators
✅ Exhibits created successfully with or without photos
✅ No more "object-not-found" errors

### Need More Help?

1. **Check Firebase Console**: Ensure project is active and properly configured
2. **Verify Rules**: Make sure security rules are published and match the format above
3. **Test Connection**: Try uploading a small image manually through Firebase Console
4. **Check Logs**: Look at Android Studio console for detailed error messages

---

**Apply the security rules first, then test the app. The upload errors should be resolved!** 🔑✨
