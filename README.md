# Spark - A Minimalist iOS Notes & Todo App

Spark is a beautifully simple note-taking and todo app that feels like having a conversation with a helpful friend. No setup, no categories, no complexity - just pure, effortless productivity.

## Philosophy

- Every interaction should feel effortless and natural
- No setup, categories, or configuration required
- The app should disappear and let thoughts flow

## Key Features

### Smart Natural Language Processing
- Type anything - the app automatically recognizes if it's a note or task
- "Call mom tomorrow at 3pm" becomes a reminder automatically
- Intelligent date and time parsing

### Beautiful, Minimalist Design
- Single input field that does everything
- Gorgeous typography and micro-animations
- Delightful interactions with haptic feedback

### Instant Search
- No folders needed - just type to find anything
- Lightning-fast search across all your notes and tasks
- Smart filtering with visual feedback

### Intuitive Gestures
- Swipe right to complete tasks
- Swipe left to delete
- Long-press to edit
- Everything feels natural

### Contextual Intelligence
- Smart suggestions based on time of day and your patterns
- Surfaces relevant notes when you need them
- Learns from your usage without being intrusive

## Build Instructions

1. Open `Spark.xcodeproj` in Xcode 14.0 or later
2. Select your development team in the project settings
3. Choose your target device or simulator
4. Press Cmd+R to build and run

## Requirements

- iOS 16.0 or later
- Xcode 14.0 or later
- Swift 5.8

## Architecture

The app follows MVVM architecture with:
- SwiftUI for the UI layer
- Core Data for persistence
- Combine for reactive updates
- Natural Language framework for text parsing

## Project Structure

```
Spark/
├── App/                    # App entry point
├── Models/                 # Core Data models
├── Views/                  # SwiftUI views
├── ViewModels/            # View models
├── Services/              # Business logic
├── Utilities/             # Helper classes
├── Extensions/            # Swift extensions
└── Resources/             # Colors, assets, etc.
```

## Design Principles

1. **Simplicity First**: Every feature must justify its existence
2. **Delight in Details**: Micro-animations and transitions matter
3. **Intelligent Defaults**: The app should do the right thing without asking
4. **No Configuration**: Zero setup required - it just works

## What's NOT Included

- Folders, tags, or categories
- Complex project management features
- Overwhelming customization options
- Subscription features or paywalls

The goal: Users should feel like the app reads their mind - it does what they want before they realize they want it, without ever getting in the way.