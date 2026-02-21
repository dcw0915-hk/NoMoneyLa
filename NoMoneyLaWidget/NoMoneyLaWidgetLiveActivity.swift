//
//  NoMoneyLaWidgetLiveActivity.swift
//  NoMoneyLaWidget
//
//  Created by Ricky Ding on 22/2/2026.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct NoMoneyLaWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct NoMoneyLaWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NoMoneyLaWidgetAttributes.self) { context in
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

extension NoMoneyLaWidgetAttributes {
    fileprivate static var preview: NoMoneyLaWidgetAttributes {
        NoMoneyLaWidgetAttributes(name: "World")
    }
}

extension NoMoneyLaWidgetAttributes.ContentState {
    fileprivate static var smiley: NoMoneyLaWidgetAttributes.ContentState {
        NoMoneyLaWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: NoMoneyLaWidgetAttributes.ContentState {
         NoMoneyLaWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: NoMoneyLaWidgetAttributes.preview) {
   NoMoneyLaWidgetLiveActivity()
} contentStates: {
    NoMoneyLaWidgetAttributes.ContentState.smiley
    NoMoneyLaWidgetAttributes.ContentState.starEyes
}
