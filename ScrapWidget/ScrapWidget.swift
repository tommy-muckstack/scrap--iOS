//
//  ScrapWidget.swift
//  ScrapWidget
//
//  Created by Tommy Keeley on 9/12/25.
//

import WidgetKit
import SwiftUI

// MARK: - Simple Timeline Provider
struct ScrapWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> ScrapWidgetEntry {
        ScrapWidgetEntry(date: Date(), noteCount: 3)
    }

    func getSnapshot(in context: Context, completion: @escaping (ScrapWidgetEntry) -> ()) {
        let noteCount = UserDefaults(suiteName: "group.scrap.app")?.integer(forKey: "ScrapNoteCount") ?? 0
        let entry = ScrapWidgetEntry(date: Date(), noteCount: noteCount)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ScrapWidgetEntry>) -> ()) {
        let noteCount = UserDefaults(suiteName: "group.scrap.app")?.integer(forKey: "ScrapNoteCount") ?? 0
        
        var entries: [ScrapWidgetEntry] = []
        let currentDate = Date()
        
        // Create entry for now
        let entry = ScrapWidgetEntry(date: currentDate, noteCount: noteCount)
        entries.append(entry)
        
        // Refresh every 15 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: currentDate)!
        let timeline = Timeline(entries: entries, policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Widget Entry
struct ScrapWidgetEntry: TimelineEntry {
    let date: Date
    let noteCount: Int
}

// MARK: - Widget Views
struct ScrapWidgetEntryView: View {
    var entry: ScrapWidgetProvider.Entry
    @Environment(\.widgetFamily) var family
    
    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        case .systemLarge:
            LargeWidgetView(entry: entry)
        default:
            SmallWidgetView(entry: entry)
        }
    }
}

// MARK: - Small Widget (2x2)
struct SmallWidgetView: View {
    let entry: ScrapWidgetEntry
    
    var body: some View {
        VStack(spacing: 8) {
            // App name
            Text("Scrap")
                .font(.system(size: 12, weight: .medium, design: .default))
                .foregroundColor(.primary)
                .opacity(0.7)
            
            Spacer()
            
            // Note count - large and prominent
            Text("\(entry.noteCount)")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .minimumScaleFactor(0.5)
            
            // Label
            Text(entry.noteCount == 1 ? "note" : "notes")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
        )
    }
}

// MARK: - Medium Widget (4x2)
struct MediumWidgetView: View {
    let entry: ScrapWidgetEntry
    
    var body: some View {
        HStack(spacing: 16) {
            // Left side - Note count
            VStack(spacing: 4) {
                Text("\(entry.noteCount)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                Text(entry.noteCount == 1 ? "note" : "notes")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Right side - App branding and quick action
            VStack(alignment: .trailing, spacing: 8) {
                Text("Scrap")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text("Tap to add a note")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.trailing)
                
                Spacer()
                
                // Visual element
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
        )
    }
}

// MARK: - Large Widget (4x4)
struct LargeWidgetView: View {
    let entry: ScrapWidgetEntry
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("Scrap")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("Notes")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Main content - Note count
            VStack(spacing: 8) {
                Text("\(entry.noteCount)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                Text(entry.noteCount == 1 ? "note saved" : "notes saved")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Footer with motivational text
            VStack(spacing: 4) {
                if entry.noteCount == 0 {
                    Text("Start capturing your thoughts")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("Keep the ideas flowing")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                // Visual accent
                HStack(spacing: 4) {
                    ForEach(0..<min(entry.noteCount, 5), id: \.self) { _ in
                        Circle()
                            .fill(.blue.opacity(0.6))
                            .frame(width: 6, height: 6)
                    }
                    if entry.noteCount > 5 {
                        Text("...")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.blue.opacity(0.6))
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
        )
    }
}

// MARK: - Widget Configuration
struct ScrapWidget: Widget {
    let kind: String = "ScrapWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ScrapWidgetProvider()) { entry in
            ScrapWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Scrap Notes")
        .description("See your note count at a glance")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Previews
#Preview(as: .systemSmall) {
    ScrapWidget()
} timeline: {
    ScrapWidgetEntry(date: .now, noteCount: 0)
    ScrapWidgetEntry(date: .now, noteCount: 3)
    ScrapWidgetEntry(date: .now, noteCount: 27)
}

#Preview(as: .systemMedium) {
    ScrapWidget()
} timeline: {
    ScrapWidgetEntry(date: .now, noteCount: 12)
}

#Preview(as: .systemLarge) {
    ScrapWidget()
} timeline: {
    ScrapWidgetEntry(date: .now, noteCount: 8)
}
