# 🔤 SharpGrotesk Typography System

## Design Hierarchy Implementation

### 🏆 **Headings / Titles → SharpGrotesk-Medium (sometimes SemiBold for emphasis)**

```swift
// Large hero titles
.font(GentleLightning.Typography.hero)           // SharpGrotesk-SemiBold, 34pt

// Standard titles/headings  
.font(GentleLightning.Typography.title)          // SharpGrotesk-Medium, 20pt

// Emphasized titles
.font(GentleLightning.Typography.titleEmphasis)  // SharpGrotesk-SemiBold, 20pt

// Subtitles
.font(GentleLightning.Typography.subtitle)       // SharpGrotesk-Medium, 18pt

// Section headings
.font(GentleLightning.Typography.heading)        // SharpGrotesk-Medium, 16pt
```

### 📖 **Body Text → SharpGrotesk-Book (regular reading weight)**

```swift
// Primary body text
.font(GentleLightning.Typography.body)           // SharpGrotesk-Book, 16pt

// Input fields
.font(GentleLightning.Typography.bodyInput)      // SharpGrotesk-Book, 17pt

// Larger body text
.font(GentleLightning.Typography.bodyLarge)      // SharpGrotesk-Book, 18pt
```

### 🌫️ **Secondary / Subtle Text → SharpGrotesk-Light**

```swift
// Subtle captions
.font(GentleLightning.Typography.caption)        // SharpGrotesk-Light, 13pt

// Small subtle text  
.font(GentleLightning.Typography.small)          // SharpGrotesk-Light, 11pt

// Secondary information
.font(GentleLightning.Typography.secondary)      // SharpGrotesk-Light, 14pt

// Timestamps, metadata
.font(GentleLightning.Typography.metadata)       // SharpGrotesk-Light, 12pt
```

## Current Usage in App

### 📝 **Note List View (ItemRowSimple)**
- **Note Title**: `Typography.title` (SharpGrotesk-Medium, 20pt)
- **Note Content**: `Typography.body` or `Typography.secondary` (when title exists)
- **Category Pills**: `Typography.metadata` (SharpGrotesk-Light, 12pt) ← **More subtle now!**

### ✏️ **Note Editor View**
- **Title Field**: `Typography.title` (SharpGrotesk-Medium, 20pt)
- **Text Content**: `Typography.bodyInput` (SharpGrotesk-Book, 17pt)

### 🏷️ **Category Management**
- **Section Headers**: `Typography.heading` (SharpGrotesk-Medium, 16pt)
- **Category Names**: `Typography.small` (SharpGrotesk-Light, 11pt)
- **Helper Text**: `Typography.secondary` (SharpGrotesk-Light, 14pt)

## Typography Best Practices

### ✅ **Do:**
- Use `Typography.title` for all main headings
- Use `Typography.body` for primary readable content
- Use `Typography.secondary` for supporting information
- Use `Typography.metadata` for timestamps and small details

### ❌ **Don't:**
- Mix different font weights for the same content type
- Use SemiBold unless you need strong emphasis
- Use Book weight for subtle/secondary content

## Weight Mapping

| **Purpose** | **Weight** | **Usage** |
|-------------|------------|-----------|
| **Hero Titles** | SemiBold | App names, major sections |
| **Titles/Headings** | Medium | Note titles, section headers |
| **Body Text** | Book | Main content, input fields |
| **Subtle Text** | Light | Captions, metadata, timestamps |

## Visual Hierarchy

```
🔥 HERO (SemiBold, 34pt)     ← App title, major features
📋 TITLE (Medium, 20pt)      ← Note titles, main headings  
📖 BODY (Book, 16-17pt)      ← Main content, readable text
🌫️ SUBTLE (Light, 11-14pt)   ← Secondary info, metadata
```

This creates a **clean, readable hierarchy** that guides users through your content! ✨