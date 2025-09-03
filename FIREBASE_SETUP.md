# Firebase Web Setup for ArtListener

Follow these steps to set up Firebase for the web version of the ArtListener app:

1. Go to the [Firebase Console](https://console.firebase.google.com/)
2. Select your project or create a new one
3. Click on the web icon (`</>`) to add a web app to your Firebase project
4. Register your app with a nickname (e.g., "ArtListener Web")
5. Copy the Firebase configuration object
6. Replace the placeholder values in `web/firebase-config.js` with your actual Firebase configuration

Your `firebase-config.js` should look like this (but with your actual values):

```javascript
const firebaseConfig = {
  apiKey: "YOUR_API_KEY",
  authDomain: "YOUR_PROJECT_ID.firebaseapp.com",
  projectId: "YOUR_PROJECT_ID",
  storageBucket: "YOUR_PROJECT_ID.appspot.com",
  messagingSenderId: "YOUR_MESSAGING_SENDER_ID",
  appId: "YOUR_APP_ID"
};

// Initialize Firebase
firebase.initializeApp(firebaseConfig);
```

## Enabling Authentication

1. In the Firebase Console, go to the Authentication section
2. Click on "Get started"
3. Go to the "Sign-in method" tab
4. Enable "Email/Password" authentication

## Setting up Firestore

1. In the Firebase Console, go to the Firestore section
2. Click "Create database" if you haven't already
3. Start in test mode for development (or set up security rules for production)
4. Choose a location for your database

## Security Rules (for development)

For development, you can use these basic rules. For production, make sure to implement proper security rules:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /{document=**} {
      allow read, write: if request.auth != null;
    }
  }
}
```

## Testing

After setting up the configuration, run the app with:

```bash
flutter run -d chrome
```

Make sure to test both authentication and database operations to ensure everything is working correctly.
