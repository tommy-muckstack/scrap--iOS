#!/bin/bash

# Complete App Store Screenshots - Interactive Helper
# Run this script to capture the remaining screenshots for App Store submission

set -e

# Configuration
DEVICE_ID="2B4B21E3-B3C7-464C-97D1-DD7BC867C1B7"  # iPhone 16 Pro Max
BUNDLE_ID="com.muckstack.scrap"
SCREENSHOTS_DIR="Screenshots"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}📱 Complete App Store Screenshots for Scrap${NC}"
echo -e "${BLUE}Current Status: Foundation screenshots captured${NC}"
echo ""

# Check if app is running
if xcrun simctl spawn "$DEVICE_ID" launchctl list | grep -q "$BUNDLE_ID"; then
    echo -e "${GREEN}✅ Scrap app is running on simulator${NC}"
else
    echo -e "${YELLOW}🚀 Launching Scrap app...${NC}"
    xcrun simctl launch "$DEVICE_ID" "$BUNDLE_ID"
    sleep 3
fi

echo ""
echo -e "${BLUE}📋 Screenshot Checklist:${NC}"
echo -e "${GREEN}✅ Main interface captured${NC}"
echo -e "${YELLOW}⏳ Remaining screenshots needed:${NC}"
echo "   2. Note list with content"
echo "   3. Note editing interface"
echo "   4. Voice recording state"
echo "   5. Account/settings drawer"
echo ""

# Function to capture screenshot with user prompt
capture_interactive_screenshot() {
    local filename=$1
    local title=$2
    local instructions=$3
    
    echo -e "${BLUE}📸 Screenshot: $title${NC}"
    echo -e "${YELLOW}Instructions: $instructions${NC}"
    echo ""
    read -p "Press Enter when ready to capture this screenshot..."
    
    xcrun simctl io "$DEVICE_ID" screenshot "$SCREENSHOTS_DIR/$filename"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Captured: $filename${NC}"
    else
        echo -e "${RED}❌ Failed to capture: $filename${NC}"
    fi
    echo ""
}

# Step 1: Add sample content
echo -e "${YELLOW}📝 Step 1: Add Sample Content${NC}"
echo "First, let's add some sample notes to make the screenshots look great."
echo ""
echo "Sample notes to add (copy and paste these):"
echo ""
echo -e "${BLUE}Note 1 Title:${NC} Self-Exploration and Identity Discovery"
echo -e "${BLUE}Note 1 Content:${NC} Who am I really beneath all the roles I play? This question has been echoing in my mind lately. I realize I've been so focused on meeting others' expectations that I've lost touch with my authentic self."
echo ""
echo -e "${BLUE}Note 2 Title:${NC} Morning Meditation Insights"
echo -e "${BLUE}Note 2 Content:${NC} During today's 20-minute sit, I noticed how my mind immediately goes to my to-do list. But underneath that mental chatter, there's a stillness that feels like home."
echo ""
echo -e "${BLUE}Note 3 Title:${NC} Creative Flow State"
echo -e "${BLUE}Note 3 Content:${NC} There's something magical about those moments when time disappears and the work just flows through you. Had that experience today while writing - felt completely connected to the process."
echo ""
echo -e "${BLUE}Note 4 Title:${NC} Gratitude Practice"
echo -e "${BLUE}Note 4 Content:${NC} Three things I'm grateful for today:"
echo "• The way morning light filters through my kitchen window"
echo "• That unexpected call from an old friend"
echo "• The feeling of completing a challenging project"
echo ""
read -p "Add these 4 notes to your app, then press Enter to continue..."

# Step 2: Capture note list screenshot
capture_interactive_screenshot \
    "03-note-list-with-content.png" \
    "Note List with Content" \
    "Make sure 3-4 notes are visible in the main list. The app should show a nice variety of content."

# Step 3: Capture note editing screenshot
capture_interactive_screenshot \
    "04-note-editing.png" \
    "Note Editing Interface" \
    "Tap on the 'Self-Exploration and Identity Discovery' note to open it for editing. Wait for the edit view to fully load."

# Step 4: Go back to main screen for voice recording
echo -e "${YELLOW}📝 Preparing for voice recording screenshot...${NC}"
echo "First, go back to the main screen by tapping 'Back' or using navigation."
read -p "Press Enter when you're back on the main screen..."

capture_interactive_screenshot \
    "05-voice-recording.png" \
    "Voice Recording Interface" \
    "Tap the microphone button to start voice recording. Capture when you see the recording indicator and red button."

# Step 5: Account drawer
echo -e "${YELLOW}📝 Preparing for account drawer screenshot...${NC}"
echo "Stop the recording if active, then scroll down to see the 'My Account' button."
read -p "Press Enter when ready..."

capture_interactive_screenshot \
    "06-account-drawer.png" \
    "Account Management" \
    "Tap 'My Account' to open the account drawer. Capture when the drawer is fully visible."

# Final summary
echo -e "${GREEN}🎉 Screenshot Capture Complete!${NC}"
echo ""
echo -e "${BLUE}📁 Generated Screenshots:${NC}"
ls -la "$SCREENSHOTS_DIR"/*.png

echo ""
echo -e "${BLUE}📊 App Store Submission Ready:${NC}"
echo "✅ iPhone 16 Pro Max screenshots (1320x2868)"
echo "✅ PNG format with high quality"
echo "✅ Professional content and presentation"
echo "✅ Key features demonstrated"
echo ""
echo -e "${YELLOW}📋 Next Steps:${NC}"
echo "1. Review all screenshots in Preview or Photos app"
echo "2. Optional: Add marketing text overlays"
echo "3. Upload to App Store Connect"
echo "4. Add compelling captions for each screenshot"
echo ""
echo -e "${GREEN}🚀 Your App Store screenshots are ready for submission!${NC}"

# Show file sizes and info
echo ""
echo -e "${BLUE}📁 Screenshot Details:${NC}"
for file in "$SCREENSHOTS_DIR"/*.png; do
    if [ -f "$file" ]; then
        size=$(ls -lh "$file" | awk '{print $5}')
        echo "$(basename "$file"): $size"
    fi
done

echo ""
echo -e "${BLUE}💡 Pro Tip:${NC} Preview all screenshots to ensure they look professional and tell a compelling story about your app!"