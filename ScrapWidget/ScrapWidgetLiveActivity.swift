//
//  ScrapWidgetLiveActivity.swift
//  ScrapWidget
//
//  Created by Tommy Keeley on 9/12/25.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct ScrapWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct ScrapWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ScrapWidgetAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension ScrapWidgetAttributes {
    fileprivate static var preview: ScrapWidgetAttributes {
        ScrapWidgetAttributes(name: "World")
    }
}

extension ScrapWidgetAttributes.ContentState {
    fileprivate static var smiley: ScrapWidgetAttributes.ContentState {
        ScrapWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: ScrapWidgetAttributes.ContentState {
         ScrapWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: ScrapWidgetAttributes.preview) {
   ScrapWidgetLiveActivity()
} contentStates: {
    ScrapWidgetAttributes.ContentState.smiley
    ScrapWidgetAttributes.ContentState.starEyes
}
