# Scrap iOS Setup Guide

## Required Configuration

### OpenAI API Key Setup

The app requires an OpenAI API key for automatic title generation. Choose one of these methods:

#### Method 1: Xcode Build Settings (Recommended)
1. Open the project in Xcode
2. Click on "Scrap" project (blue icon)
3. Select "Scrap" target
4. Go to "Build Settings" tab
5. Search for "User-Defined"
6. Click "+" to add: `OPENAI_API_KEY` = `your-api-key-here`

#### Method 2: Config File
1. Copy `Config.xcconfig.template` to `Config.xcconfig`
2. Replace `YOUR_OPENAI_API_KEY_HERE` with your actual API key
3. Add Config.xcconfig to your Xcode project

#### Method 3: Environment Variable
```bash
export OPENAI_API_KEY="your-api-key-here"
```

### Getting an OpenAI API Key
1. Go to https://platform.openai.com/api-keys
2. Sign in to your OpenAI account
3. Click "Create new secret key"
4. Copy the key (starts with `sk-`)

## Features Enabled by API Key
- ✅ Automatic title generation for notes
- ✅ Smart categorization
- ✅ Voice-to-text transcription enhancement

## Testing
After setup, create a new note and check the console for:
```
✅ OpenAI API key configured successfully
✅ Title generated: [meaningful title]
```