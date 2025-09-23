//
//  QuickNoteWidget.swift
//  ScrapWidget
//
//  Interactive widget that mimics the main app's InputField design
//  and launches the app for note creation
//

import SwiftUI
import WidgetKit

// MARK: - Quick Note Widget
struct QuickNoteWidget: Widget {
    let kind: String = "QuickNoteWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            QuickNoteWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Quick Note")
        .description("Tap to quickly create a new note")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Widget Entry
struct QuickNoteEntry: TimelineEntry {
    let date: Date
}

// MARK: - Provider
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> QuickNoteEntry {
        QuickNoteEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickNoteEntry) -> ()) {
        let entry = QuickNoteEntry(date: Date())
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickNoteEntry>) -> ()) {
        let entries: [QuickNoteEntry] = [
            QuickNoteEntry(date: Date())
        ]
        
        // Update every hour to keep the widget fresh
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        let timeline = Timeline(entries: entries, policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Widget Entry View
struct QuickNoteWidgetEntryView: View {
    var entry: QuickNoteEntry
    @Environment(\.widgetFamily) var family
    
    var body: some View {
        switch family {
        case .systemSmall:
            SmallQuickNoteView()
        case .systemMedium:
            MediumQuickNoteView()
        default:
            SmallQuickNoteView()
        }
    }
}

// MARK: - Small Widget (2x2)
struct SmallQuickNoteView: View {
    var body: some View {
        Link(destination: URL(string: "com.muckstack.scrap://create-note")!) {
            VStack(spacing: 12) {
                // App name
                Text("Scrap")
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .foregroundColor(.primary)
                    .opacity(0.7)
                
                Spacer()
                
                // Input field mockup - matches main app design
                VStack(spacing: 0) {
                    HStack(alignment: .center, spacing: 12) {
                        // Placeholder text matching main app
                        HStack {
                            Text("What's on your mind?")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                            Spacer()
                        }
                        
                        // Microphone icon - matches main app styling
                        Image(systemName: "mic.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .fill(.blue)
                            )
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .background(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(.systemGray4), lineWidth: 1)
                    )
                }
                
                Spacer()
                
                // Tap hint
                Text("Tap to create")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }
}

// MARK: - Medium Widget (4x2)
struct MediumQuickNoteView: View {
    var body: some View {
        Link(destination: URL(string: "com.muckstack.scrap://create-note")!) {
            HStack(spacing: 16) {
                // Left side - Input field mockup
                VStack(spacing: 8) {
                    HStack(alignment: .center, spacing: 12) {
                        // Placeholder text area
                        VStack(alignment: .leading, spacing: 4) {
                            Text("What's on your mind?")
                                .font(.system(size: 15, weight: .regular))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                            
                            Text("Tap to start writing...")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        
                        Spacer()
                        
                        // Action buttons stack - matches main app
                        VStack(spacing: 6) {
                            // Microphone button
                            Image(systemName: "mic.fill")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 28, height: 28)
                                .background(
                                    Circle()
                                        .fill(.blue)
                                )
                            
                            // Text input button
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.blue)
                                .frame(width: 28, height: 28)
                                .background(
                                    Circle()
                                        .fill(.blue.opacity(0.1))
                                )
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .background(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(.systemGray4), lineWidth: 1)
                    )
                }
                
                Spacer()
                
                // Right side - App branding
                VStack(alignment: .trailing, spacing: 8) {
                    Text("Scrap")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text("Quick Note")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.trailing)
                    
                    Spacer()
                    
                    // Visual accent matching main app
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.blue.opacity(0.2))
                        .frame(width: 40, height: 20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(.blue.opacity(0.3), lineWidth: 1)
                        )
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }
}

// MARK: - Previews
#Preview(as: .systemSmall) {
    QuickNoteWidget()
} timeline: {
    QuickNoteEntry(date: .now)
}

#Preview(as: .systemMedium) {
    QuickNoteWidget()
} timeline: {
    QuickNoteEntry(date: .now)
}