# Deploy Firebase Security (Quick Setup)

## 🚀 One-Time Setup Required

Run these commands to secure your Firebase:

```bash
# 1. Install Firebase CLI (if needed)
npm install -g firebase-tools

# 2. Login to Firebase
firebase login

# 3. Deploy security rules
firebase deploy --only firestore:rules --project spark-42212
```

## ✅ What This Does

- Blocks unauthorized access to your database
- Users can only see their own notes
- Validates all data before saving
- Adds database performance indexes

## 🛡️ Security Rules Applied

- ✅ Authentication required for all operations
- ✅ Users isolated to their own data
- ✅ Content length limits (10k characters max)
- ✅ Category limits (10 max per note)
- ✅ Data type validation
- ✅ Timestamp validation

**Your Firebase is now production-ready and secure!**