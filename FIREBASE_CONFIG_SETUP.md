# Firebase Configuration Setup

## Simple API Key Storage in Firebase

This setup allows you to store your Mistral API key in Firebase Firestore, just like an environment variable.

## Setup Steps

### 1. Create the Configuration Document

1. Go to your Firebase Console
2. Navigate to **Firestore Database**
3. Click **Start collection** (if you don't have any collections)
4. Create a collection called `config`
5. Create a document with ID `mistral`
6. Add a field:
   - **Field name**: `api_key`
   - **Field type**: `string`
   - **Field value**: `ptH5wGbKGViNR1oFfF7gFjtyRDyEVlyD`

### 2. Firestore Document Structure

Your Firestore should look like this:

```
/config/mistral
├── api_key: "ptH5wGbKGViNR1oFfF7gFjtyRDyEVlyD"
```

### 3. Set Up Firestore Security Rules

Update your Firestore rules to allow read access:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Allow authenticated users to read config
    match /config/{document} {
      allow read: if request.auth != null;
    }
    
    // Your existing rules for other collections
    match /users/{userId}/items/{itemId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
  }
}
```

Deploy the rules:
```bash
firebase deploy --only firestore:rules
```

## How It Works

- **Simple**: Just one Firestore document stores your API key
- **Cached**: API key is cached for 30 minutes to reduce Firestore reads
- **Secure**: Only authenticated users can read the configuration
- **Centralized**: Update the API key in one place (Firebase Console)

## Usage

The `ConfigService` automatically reads the API key from `/config/mistral` in Firestore:

```dart
// Get the API key
final apiKey = await ConfigService().getMistralApiKey();

// Check if API key is configured
final hasKey = await ConfigService().hasMistralApiKey();
```

## Updating the API Key

To update your API key:
1. Go to Firebase Console → Firestore Database
2. Navigate to `/config/mistral`
3. Update the `api_key` field
4. The app will pick up the new key within 30 minutes (or restart the app)

## Benefits

- ✅ **Simple**: No complex Cloud Functions needed
- ✅ **Secure**: API key not stored in app code
- ✅ **Centralized**: Manage all config in Firebase Console
- ✅ **Cached**: Efficient with 30-minute caching
- ✅ **Version controlled**: Firestore rules can be version controlled

That's it! Your API key is now stored securely in Firebase and accessible like an environment variable. 🚀
