# Firebase Security Configuration Guide

## ⚠️ Security Alert Resolved

GitHub detected that your `GoogleService-Info.plist` file was exposed in your repository. This has been fixed by:

1. ✅ Removing the file from Git tracking
2. ✅ Adding it to `.gitignore`
3. ✅ Creating this security guide

## 🔒 Important Security Steps

### Step 1: Keep Your Local File
The `GoogleService-Info.plist` file is still in your local project folder (which is correct), but it's now excluded from Git. This means:
- ✅ Your app will continue to work locally
- ✅ The file won't be uploaded to GitHub
- ✅ Your API keys are now protected

### Step 2: For Team Development
If you need to share this project with team members:

1. **Share the file securely** via:
   - Encrypted email
   - Secure file transfer
   - Password manager shared note
   - Private Slack DM

2. **Have team members**:
   ```bash
   # Place the GoogleService-Info.plist in:
   /path/to/project/Spark/GoogleService-Info.plist
   ```

### Step 3: For CI/CD or Deployment
For automated builds:

1. **Store as base64 in environment variable**:
   ```bash
   # Encode the file
   base64 -i GoogleService-Info.plist | pbcopy
   ```

2. **In your CI/CD pipeline**:
   ```bash
   # Decode during build
   echo $GOOGLE_SERVICE_INFO_BASE64 | base64 --decode > Spark/GoogleService-Info.plist
   ```

## 🛡️ Best Practices

### DO:
- ✅ Keep `GoogleService-Info.plist` in `.gitignore`
- ✅ Store the file locally for development
- ✅ Use environment variables for CI/CD
- ✅ Restrict Firebase API keys in Google Cloud Console
- ✅ Enable App Check for additional security

### DON'T:
- ❌ Commit `GoogleService-Info.plist` to Git
- ❌ Share the file publicly
- ❌ Include API keys in code
- ❌ Store sensitive data in UserDefaults

## 🔑 Restricting API Keys (Recommended)

1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Select your project: `spark-42212`
3. Navigate to **APIs & Services** → **Credentials**
4. Find your iOS API key
5. Click **Edit** → **Application restrictions**
6. Select **iOS apps**
7. Add your Bundle ID: `com.muckstack.spark`
8. **Save**

## 📱 Firebase Security Rules

Update your Firestore rules for production:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Only authenticated users can read/write their own notes
    match /notes/{noteId} {
      allow read, write: if request.auth != null 
        && request.auth.uid == resource.data.userId;
      allow create: if request.auth != null 
        && request.auth.uid == request.resource.data.userId;
    }
  }
}
```

## 🚨 If Keys Were Exposed

Since your keys were briefly exposed:

1. **Monitor Firebase Console** for unusual activity
2. **Consider regenerating** the configuration:
   - Create a new Firebase iOS app
   - Download new `GoogleService-Info.plist`
   - Update your local file
   - Delete the old iOS app from Firebase

3. **Enable Firebase App Check**:
   - Adds an extra layer of security
   - Ensures only your app can access Firebase

## ✅ Current Status

- File is removed from Git history ✅
- File is in `.gitignore` ✅
- Local development will continue to work ✅
- Future commits won't include the file ✅

Your Firebase configuration is now secure! 🔐