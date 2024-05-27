//
//  GpxWidgetLiveActivity.swift
//  GpxWidget
//
//  Created by Bryce Cogswell on 5/5/24.
//  Copyright © 2024 Bryce Cogswell. All rights reserved.
//

#if canImport(ActivityKit)
import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

func widgetStartGPS() {
	// This is a dummy function that doesn't get called inside the widget. The app has its own implementation.
}

func widgetPauseGPS() {
	// This is a dummy function that doesn't get called inside the widget. The app has its own implementation.
}

func widgetStopGPS() {
	// This is a dummy function that doesn't get called inside the widget. The app has its own implementation.
}

struct GpxWidgetLiveActivity: Widget {
	var body: some WidgetConfiguration {
		ActivityConfiguration(for: GpxTrackAttributes.self) { context in
			// Lock screen/banner UI goes here
			HStack {
				Spacer()
				VStack(alignment: .leading) {
					Text(context.state.startTime.formatted(date: .omitted, time: .shortened))
					Text("\(context.state.durationHMS)")
						.contentTransition(.numericText())
					Text("\(context.state.pointCount) points")
						.contentTransition(.numericText())
				}
				.foregroundStyle(.white)
				Spacer()
				Image("AppIcon")
					.cornerRadius(8)

				if context.state.status == .running {
					Spacer()
					Button(intent: StopGpxTrackIntent()) {
						Text("Stop")
					}
					.background(Color.green)
					.foregroundStyle(.red)
					.clipShape(Capsule())
					Spacer()
				}
			}
			.activityBackgroundTint(Color.green)
			.activitySystemActionForegroundColor(Color.black)
		} dynamicIsland: { context in
			DynamicIsland {
				// Expanded UI goes here.  Compose the expanded UI through
				// various regions, like leading/trailing/center/bottom
				DynamicIslandExpandedRegion(.leading) {
					Text("\(context.state.pointCount) GPX points")
				}
				DynamicIslandExpandedRegion(.trailing) {
					Text("\(context.state.durationHMS)")
				}
				DynamicIslandExpandedRegion(.center) {
					Image("AppIconTransparent")
				}
			} compactLeading: {
				Image("AppIconTransparent")
					.resizable()
					.aspectRatio(contentMode: .fill)
			} compactTrailing: {
				Text("\(context.state.durationHMS)")
			} minimal: {
				Image("AppIconTransparent")
					.resizable()
					.aspectRatio(contentMode: .fill)
			}
		}
	}
}

private extension GpxTrackAttributes {
	static var preview: GpxTrackAttributes {
		GpxTrackAttributes()
	}
}

private extension GpxTrackAttributes.ContentState {
	static var smiley: GpxTrackAttributes.ContentState {
		GpxTrackAttributes.ContentState(startTime: Date())
	}
}

#Preview("Notification", as: .content, using: GpxTrackAttributes.preview) {
	GpxWidgetLiveActivity()
} contentStates: {
	GpxTrackAttributes.ContentState.smiley
}
#endif
