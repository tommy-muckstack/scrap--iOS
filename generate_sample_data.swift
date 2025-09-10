#!/usr/bin/env swift

import Foundation

// Sample data generator for App Store screenshots
// This script creates sample notes that will make the screenshots look great

struct SampleNote {
    let title: String
    let content: String
    let isTask: Bool
    
    init(title: String, content: String, isTask: Bool = false) {
        self.title = title
        self.content = content
        self.isTask = isTask
    }
}

let sampleNotes: [SampleNote] = [
    SampleNote(
        title: "Self-Exploration and Identity Discovery",
        content: "Who am I really beneath all the roles I play? This question has been echoing in my mind lately. I realize I've been so focused on meeting others' expectations that I've lost touch with my authentic self."
    ),
    
    SampleNote(
        title: "Morning Meditation Insights",
        content: "During today's 20-minute sit, I noticed how my mind immediately goes to my to-do list. But underneath that mental chatter, there's a stillness that feels like home."
    ),
    
    SampleNote(
        title: "Creative Flow State",
        content: "There's something magical about those moments when time disappears and the work just flows through you. Had that experience today while writing - felt completely connected to the process."
    ),
    
    SampleNote(
        title: "Gratitude Practice",
        content: "Three things I'm grateful for today:\n• The way morning light filters through my kitchen window\n• That unexpected call from an old friend\n• The feeling of completing a challenging project"
    ),
    
    SampleNote(
        title: "Learning from Setbacks",
        content: "Failed to stick to my exercise routine this week. Instead of beating myself up, I'm curious about what got in the way. Maybe I need to start smaller - just 10 minutes daily."
    ),
    
    SampleNote(
        title: "Book Quote",
        content: "\"The cave you fear to enter holds the treasure you seek.\" - Joseph Campbell\n\nThis resonates deeply right now. What caves am I avoiding?"
    ),
    
    SampleNote(
        title: "Weekend Adventure Ideas",
        content: "• Hike the coastal trail at sunrise\n• Visit that new art gallery downtown\n• Try cooking something completely unfamiliar\n• Have a phone-free afternoon in the park",
        isTask: true
    ),
    
    SampleNote(
        title: "Conversation with Mom",
        content: "She shared stories about her childhood I'd never heard before. Amazing how much we don't know about the people closest to us. Made me realize I should ask more questions."
    )
]

// Print sample data in a format that could be imported
print("// Sample notes for App Store screenshots")
print("let sampleNotesForScreenshots = [")

for (index, note) in sampleNotes.enumerated() {
    print("    SampleNote(")
    print("        title: \"\(note.title)\",")
    print("        content: \"\(note.content.replacingOccurrences(of: "\n", with: "\\n"))\",")
    print("        isTask: \(note.isTask)")
    print("    )\(index < sampleNotes.count - 1 ? "," : "")")
}

print("]")

print("\n// Instructions:")
print("// 1. Add these notes manually in the app before capturing screenshots")
print("// 2. Or integrate this data into your Firebase test data")
print("// 3. Make sure to have a good mix of short and long content")
print("// 4. Include both regular notes and tasks for variety")

print("\n🎯 Perfect screenshot notes created!")
print("📱 These will make your App Store screenshots look professional and engaging.")