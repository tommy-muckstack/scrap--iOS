# 🔤 Space Grotesk Typography System

## Design Hierarchy Implementation

### 🏆 **Headings / Titles → SpaceGrotesk-Medium/Bold for emphasis**

```swift
// Large hero titles
.font(GentleLightning.Typography.hero)           // SpaceGrotesk-Bold, 34pt

// Standard titles/headings  
.font(GentleLightning.Typography.title)          // SpaceGrotesk-Medium, 20pt

// Emphasized titles
.font(GentleLightning.Typography.titleEmphasis)  // SpaceGrotesk-SemiBold, 20pt

// Subtitles
.font(GentleLightning.Typography.subtitle)       // SpaceGrotesk-Medium, 18pt

// Section headings
.font(GentleLightning.Typography.heading)        // SpaceGrotesk-Medium, 16pt
```

### 📖 **Body Text → SpaceGrotesk-Regular (regular reading weight)**

```swift
// Primary body text
.font(GentleLightning.Typography.body)           // SpaceGrotesk-Regular, 16pt

// Input fields
.font(GentleLightning.Typography.bodyInput)      // SpaceGrotesk-Regular, 17pt

// Larger body text
.font(GentleLightning.Typography.bodyLarge)      // SpaceGrotesk-Regular, 18pt
```

### 🌫️ **Secondary / Subtle Text → SpaceGrotesk-Light**

```swift
// Subtle captions
.font(GentleLightning.Typography.caption)        // SpaceGrotesk-Light, 13pt

// Small subtle text  
.font(GentleLightning.Typography.small)          // SpaceGrotesk-Light, 11pt

// Secondary information
.font(GentleLightning.Typography.secondary)      // SpaceGrotesk-Light, 14pt

// Timestamps, metadata
.font(GentleLightning.Typography.metadata)       // SpaceGrotesk-Light, 12pt
```

## Current Usage in App

### 📝 **Note List View (ItemRowSimple)**
- **Note Title**: `Typography.title` (SpaceGrotesk-Medium, 20pt)
- **Note Content**: `Typography.body` or `Typography.secondary` (when title exists)
- **Category Pills**: `Typography.metadata` (SpaceGrotesk-Light, 12pt) ← **More subtle now!**

### ✏️ **Note Editor View**
- **Title Field**: `Typography.title` (SpaceGrotesk-Medium, 20pt)
- **Text Content**: `Typography.bodyInput` (SpaceGrotesk-Regular, 17pt)

### 🏷️ **Category Management**
- **Section Headers**: `Typography.heading` (SpaceGrotesk-Medium, 16pt)
- **Category Names**: `Typography.small` (SpaceGrotesk-Light, 11pt)
- **Helper Text**: `Typography.secondary` (SpaceGrotesk-Light, 14pt)

## Typography Best Practices

### ✅ **Do:**
- Use `Typography.title` for all main headings
- Use `Typography.body` for primary readable content
- Use `Typography.secondary` for supporting information
- Use `Typography.metadata` for timestamps and small details

### ❌ **Don't:**
- Mix different font weights for the same content type
- Use SemiBold unless you need strong emphasis
- Use Regular weight for subtle/secondary content (use Light instead)

## Weight Mapping

| **Purpose** | **Weight** | **Usage** |
|-------------|------------|-----------|
| **Hero Titles** | Bold | App names, major sections |
| **Titles/Headings** | Medium/SemiBold | Note titles, section headers |
| **Body Text** | Regular | Main content, input fields |
| **Subtle Text** | Light | Captions, metadata, timestamps |

## Visual Hierarchy

```
🔥 HERO (Bold, 34pt)         ← App title, major features
📋 TITLE (Medium, 20pt)      ← Note titles, main headings  
📖 BODY (Regular, 16-17pt)   ← Main content, readable text
🌫️ SUBTLE (Light, 11-14pt)   ← Secondary info, metadata
```

This creates a **clean, readable hierarchy** that guides users through your content! ✨