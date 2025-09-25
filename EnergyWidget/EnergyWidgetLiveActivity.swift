#if os(iOS)
//
//  EnergyWidgetLiveActivity.swift
//  EnergyWidget
//
//  Created by Max Brown on 9/24/25.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct EnergyWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

@available(iOS 16.1, *)
struct EnergyWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: EnergyWidgetAttributes.self) { context in
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

extension EnergyWidgetAttributes {
    fileprivate static var preview: EnergyWidgetAttributes {
        EnergyWidgetAttributes(name: "World")
    }
}

extension EnergyWidgetAttributes.ContentState {
    fileprivate static var smiley: EnergyWidgetAttributes.ContentState {
        EnergyWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: EnergyWidgetAttributes.ContentState {
         EnergyWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#if DEBUG
#Preview("Notification", as: .content, using: EnergyWidgetAttributes.preview) {
   EnergyWidgetLiveActivity()
} contentStates: {
    EnergyWidgetAttributes.ContentState.smiley
    EnergyWidgetAttributes.ContentState.starEyes
}
#endif

#endif
