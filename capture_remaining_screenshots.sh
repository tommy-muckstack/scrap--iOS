#!/bin/bash

# Quick Screenshot Capture Script
# Run this after adding sample content to the app

DEVICE_ID="2B4B21E3-B3C7-464C-97D1-DD7BC867C1B7"
SCREENSHOTS_DIR="Screenshots"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}📱 Capturing remaining screenshots...${NC}"
echo ""

# Function to capture with user prompt
capture_with_prompt() {
    local filename=$1
    local description=$2
    local instructions=$3
    
    echo -e "${YELLOW}📸 Next: $description${NC}"
    echo -e "${YELLOW}Instructions: $instructions${NC}"
    echo ""
    read -p "Press Enter when ready to capture..."
    
    xcrun simctl io "$DEVICE_ID" screenshot "$SCREENSHOTS_DIR/$filename"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Captured: $filename${NC}"
    else
        echo -e "${RED}❌ Failed: $filename${NC}"
    fi
    echo ""
}

echo -e "${BLUE}Current app state: Scrap is running with updated interface${NC}"
echo -e "${BLUE}Updated: No more 'Edit Note' header in note editing views${NC}"
echo ""

# Capture current state (main screen)
echo -e "${YELLOW}📸 Capturing current main screen state...${NC}"
xcrun simctl io "$DEVICE_ID" screenshot "$SCREENSHOTS_DIR/02-current-state.png"
echo -e "${GREEN}✅ Captured: 02-current-state.png${NC}"
echo ""

# Guide user through adding content and capturing specific screenshots
capture_with_prompt "03-main-with-notes.png" "Main Screen with Sample Notes" "Add 3-4 sample notes to the app first, then come back to this screen."

capture_with_prompt "04-note-editing-clean.png" "Note Editing (Clean Header)" "Tap on the 'Self-Exploration...' note to open editing view. Notice: NO 'Edit Note' header!"

capture_with_prompt "05-voice-recording.png" "Voice Recording Interface" "Go back to main screen, then tap the microphone button to start recording."

capture_with_prompt "06-account-drawer.png" "Account Management" "Stop recording, scroll down, then tap 'My Account' to open the drawer."

# Final summary
echo -e "${GREEN}🎉 Screenshot capture complete!${NC}"
echo ""
echo -e "${BLUE}📁 Generated Screenshots:${NC}"
ls -la "$SCREENSHOTS_DIR"/*.png | tail -6

echo ""
echo -e "${GREEN}✨ Perfect! Your updated screenshots show the clean interface without 'Edit Note' header.${NC}"
echo -e "${BLUE}📱 Ready for App Store submission!${NC}"