#!/bin/bash

# Setup script to configure Chroma URL in iOS app
# Usage: ./setup-chroma-url.sh https://your-railway-url.up.railway.app

if [ $# -eq 0 ]; then
    echo "Usage: $0 <railway-url>"
    echo "Example: $0 https://spark-chroma-production.up.railway.app"
    exit 1
fi

CHROMA_URL=$1

echo "🚀 Setting up Chroma URL: $CHROMA_URL"

# Update ChromaService.swift with the new URL
sed -i '' "s|https://your-chroma-deployment.up.railway.app|$CHROMA_URL|g" Spark/ChromaService.swift

echo "✅ Updated ChromaService.swift with URL: $CHROMA_URL"

# Test the connection
echo "🔍 Testing connection..."
if curl -f "$CHROMA_URL/api/v1/heartbeat" > /dev/null 2>&1; then
    echo "✅ Chroma is running and accessible!"
else
    echo "❌ Could not connect to Chroma. Make sure it's deployed and running."
fi

echo ""
echo "Next steps:"
echo "1. Build and run your iOS app"
echo "2. The app will automatically connect to Chroma"
echo "3. Try creating a note to test vector storage"