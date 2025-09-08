# Deploy Chroma to Railway - Step by Step

Since we can't run interactive commands, here's the manual approach:

## Option 1: Railway Dashboard (Recommended)

1. **Go to Railway**: https://railway.app
2. **Sign up/Login** with your GitHub account
3. **Create New Project** → "Deploy from GitHub repo"
4. **Or use this one-click deploy**: [![Deploy on Railway](https://railway.app/button.svg)](https://railway.app/template/chroma-db)

## Option 2: Upload Files Directly

1. **Create new project** on Railway dashboard
2. **Select "Empty Project"**
3. **Add a service** → "GitHub Repo" → "Upload files"
4. **Upload this directory** (`chroma-deployment/`)
5. **Railway will auto-detect** the Dockerfile and deploy

## Option 3: CLI (if you want to install locally)

In Terminal:
```bash
# Install Railway CLI (you'll need to enter password)
sudo npm install -g @railway/cli

# Login (opens browser)
railway login

# Deploy from this folder
cd /Users/tommykeeley/MuckStack-Projects/spark--iOS/chroma-deployment
railway new --name spark-chroma
railway up
```

## What happens after deployment:

1. **Railway builds** the Docker container
2. **Assigns a URL** like `https://spark-chroma-production.up.railway.app`
3. **Chroma starts running** on that URL
4. **You get the URL** to put in your iOS app

## Test your deployment:

Once deployed, test with:
```bash
curl https://your-railway-url.up.railway.app/api/v1/heartbeat
```

Should return: `{"nanosecond heartbeat": 1234567890}`

## Next: Update iOS App

Once you have the Railway URL, we'll update `ChromaService.swift`:
```swift
// Replace this line:
self.baseURL = "https://your-chroma-deployment.up.railway.app"

// With your actual Railway URL:
self.baseURL = "https://spark-chroma-production.up.railway.app"
```

## Cost: $5/month
- 512MB RAM, 1GB storage
- More than enough for your vector database