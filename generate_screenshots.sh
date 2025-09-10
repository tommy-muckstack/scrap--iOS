#!/bin/bash

# App Store Screenshot Generator for Scrap
# This script will capture screenshots for App Store submission

set -e

# Configuration
DEVICE_ID="2B4B21E3-B3C7-464C-97D1-DD7BC867C1B7"  # iPhone 16 Pro Max
APP_SCHEME="Scrap"
PROJECT_FILE="Scrap.xcodeproj"
SCREENSHOTS_DIR="Screenshots"
BUNDLE_ID="com.muckstack.scrap"  # Updated to match actual bundle ID

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Starting App Store Screenshot Generation${NC}"
echo -e "${BLUE}Device: iPhone 16 Pro Max${NC}"
echo -e "${BLUE}Resolution: 1320x2868 points${NC}"

# Create screenshots directory
mkdir -p "$SCREENSHOTS_DIR"

# Function to capture screenshot
capture_screenshot() {
    local filename=$1
    local description=$2
    
    echo -e "${YELLOW}📸 Capturing: $description${NC}"
    xcrun simctl io "$DEVICE_ID" screenshot "$SCREENSHOTS_DIR/$filename"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Saved: $SCREENSHOTS_DIR/$filename${NC}"
    else
        echo -e "${RED}❌ Failed to capture: $filename${NC}"
    fi
}

# Function to wait for app to load
wait_for_app() {
    echo -e "${YELLOW}⏳ Waiting for app to load...${NC}"
    sleep 3
}

# Step 1: Boot the simulator
echo -e "${BLUE}🔥 Booting iPhone 16 Pro Max simulator...${NC}"
xcrun simctl boot "$DEVICE_ID" 2>/dev/null || echo "Simulator already booted"
sleep 5

# Step 2: Build and install the app  
echo -e "${BLUE}🔨 Building and installing Scrap in screenshot mode...${NC}"
xcodebuild -project "$PROJECT_FILE" \
           -scheme "$APP_SCHEME" \
           -destination "platform=iOS Simulator,id=$DEVICE_ID" \
           -configuration Debug \
           build

# Step 3: Install the app
echo -e "${BLUE}📱 Installing app on simulator...${NC}"
APP_PATH="/Users/tommykeeley/Library/Developer/Xcode/DerivedData/Scrap-gqjbxafssexhklfazoxhuobtqwni/Build/Products/Debug-iphonesimulator/Scrap.app"
xcrun simctl install "$DEVICE_ID" "$APP_PATH"

# Step 4: Launch the app in screenshot mode
echo -e "${BLUE}🚀 Launching Scrap in screenshot mode...${NC}"
xcrun simctl launch "$DEVICE_ID" "$BUNDLE_ID" --setenv SCREENSHOT_MODE true
wait_for_app

# Step 5: Capture main interface with demo data
echo -e "${YELLOW}📱 App should now be showing demo data instead of authentication...${NC}"
sleep 3
capture_screenshot "01-main-interface-with-notes.png" "Main Interface with Demo Notes"

# Step 6: Capture close-up of note list
sleep 2  
capture_screenshot "02-note-list-detail.png" "Note List Detail View"

# Step 7: Try to navigate to note editing
echo -e "${YELLOW}📝 Attempting to tap on first note for editing...${NC}"
# Tap on the first note in the list (approximate coordinates for iPhone 16 Pro Max)
xcrun simctl io "$DEVICE_ID" click 660 400
sleep 3
capture_screenshot "03-note-editing-clean.png" "Clean Note Editing Interface"

# Step 8: Return to main and try voice recording
echo -e "${YELLOW}🔙 Returning to main interface...${NC}"
xcrun simctl io "$DEVICE_ID" click 100 100  # Back button area
sleep 2

echo -e "${YELLOW}🎤 Attempting to activate voice recording...${NC}"
# Try to tap microphone button (approximate position)
xcrun simctl io "$DEVICE_ID" click 660 800
sleep 2
capture_screenshot "04-voice-recording-active.png" "Voice Recording Interface"

# Step 9: Try to access account area
echo -e "${YELLOW}👤 Attempting to access account settings...${NC}"
# Tap on account/profile area (bottom of screen)
xcrun simctl io "$DEVICE_ID" click 660 1200
sleep 2
capture_screenshot "05-account-management.png" "Account Management Interface"

# Step 10: Capture app overview
echo -e "${YELLOW}📱 Capturing final overview...${NC}"
sleep 1
capture_screenshot "06-app-overview.png" "App Overview"

# Step 11: Generate summary
echo -e "${GREEN}🎉 Screenshot capture complete!${NC}"
echo -e "${BLUE}📁 Screenshots saved to: $SCREENSHOTS_DIR/${NC}"
echo ""
echo -e "${BLUE}App Store Screenshot Requirements:${NC}"
echo -e "${BLUE}• iPhone 16 Pro Max: 1320x2868 points${NC}"
echo -e "${BLUE}• File format: PNG${NC}"
echo -e "${BLUE}• Color space: sRGB or P3${NC}"
echo ""
echo -e "${BLUE}Generated Screenshots:${NC}"
ls -la "$SCREENSHOTS_DIR"/*.png 2>/dev/null || echo "No screenshots found"

echo ""
echo -e "${YELLOW}📋 Next Steps:${NC}"
echo -e "${YELLOW}1. Review screenshots in $SCREENSHOTS_DIR${NC}"
echo -e "${YELLOW}2. Add marketing copy/text overlays if needed${NC}"
echo -e "${YELLOW}3. Upload to App Store Connect${NC}"
echo -e "${YELLOW}4. Repeat for other device sizes if needed${NC}"

echo -e "${GREEN}✨ All done! Your App Store screenshots are ready.${NC}"