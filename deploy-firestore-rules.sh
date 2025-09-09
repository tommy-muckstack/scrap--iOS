#!/bin/bash

# Deploy Firestore security rules
# This script deploys the security rules to your Firebase project

echo "🔥 Deploying Firestore security rules..."

# Check if Firebase CLI is installed
if ! command -v firebase &> /dev/null; then
    echo "❌ Firebase CLI not found. Installing..."
    npm install -g firebase-tools
fi

# Login to Firebase (if not already logged in)
echo "🔐 Checking Firebase authentication..."
firebase login --no-localhost

# Deploy the rules
echo "📡 Deploying security rules to Firebase project..."
firebase deploy --only firestore:rules --project spark-42212

echo "✅ Firestore security rules deployed successfully!"
echo ""
echo "🛡️ Your database is now secured with:"
echo "- User authentication required"
echo "- Users can only access their own notes"
echo "- Data validation for all writes"
echo "- Protection against unauthorized access"