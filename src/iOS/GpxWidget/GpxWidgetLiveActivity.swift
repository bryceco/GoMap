//
//  GpxWidgetLiveActivity.swift
//  GpxWidget
//
//  Created by Bryce Cogswell on 5/5/24.
//  Copyright © 2024 Bryce Cogswell. All rights reserved.
//

#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
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

			// MARK: Lock Screen UI

			Group {
				HStack(alignment: .center) {
					Image("AppIconTransparent")
						.resizable()
						.aspectRatio(contentMode: .fit)
					VStack(alignment: .leading) {
						Text("Go Map!!")
						Text("GPX Trace")
							.foregroundStyle(.secondary)
					}
					Spacer()
					if context.state.status == .running {
						Button(intent: StopGpxTrackIntent()) {
							Text("\(Image(systemName: "stop.circle")) Stop")
								.font(.callout)
						}
						.tint(.red)
						.clipShape(Capsule())
					}
				}
				.frame(height: 30)
				.padding(.vertical)
				.font(.caption)
				HStack {
					Image(systemName: "point.bottomleft.forward.to.point.topright.scurvepath")
						.dynamicTypeSize(.xxLarge)
					VStack(alignment: .leading) {
						Text("Points")
							.font(.caption)
							.foregroundStyle(.secondary)
						Text("\(context.state.pointCount)")
							.contentTransition(.numericText())
							.font(.largeTitle)
					}
					Spacer()
					VStack(alignment: .trailing) {
						Text("Duration")
							.font(.caption)
							.foregroundStyle(.secondary)
						Text(context.state.durationHMS)
							.contentTransition(.numericText())
							.font(.largeTitle)
					}
					Image(systemName: "stopwatch")
						.dynamicTypeSize(.xxLarge)
				}
				.padding(.bottom, 5)
				Text("Started at \(context.state.startTime.formatted(date: .omitted, time: .shortened))")
					.foregroundStyle(.secondary)
					.font(.footnote)
					.padding(.bottom, 5)
			}
			.padding()
		} dynamicIsland: { context in

			// MARK: Dynamic Island (Expanded)

			DynamicIsland {
				DynamicIslandExpandedRegion(.leading) {
					HStack {
						Image(systemName: "point.bottomleft.forward.to.point.topright.scurvepath")
							.dynamicTypeSize(.xxLarge)
						VStack(alignment: .leading) {
							Text("Points")
								.font(.caption)
								.foregroundStyle(.secondary)
							Text("\(context.state.pointCount)")
								.contentTransition(.numericText())
								.font(.largeTitle)
								.minimumScaleFactor(0.5)
								.lineLimit(1)
								.truncationMode(.tail)
						}
					}
					.padding(.top)
				}
				DynamicIslandExpandedRegion(.trailing) {
					HStack {
						VStack(alignment: .trailing) {
							Text("Duration")
								.font(.caption)
								.foregroundStyle(.secondary)
							Text(context.state.durationHMS)
								.contentTransition(.numericText())
								.font(.largeTitle)
								.minimumScaleFactor(0.5)
								.lineLimit(1)
								.truncationMode(.tail)
						}
						Image(systemName: "stopwatch")
							.dynamicTypeSize(.xxLarge)
					}
					.padding(.top)
				}
				DynamicIslandExpandedRegion(.center) {
					VStack {
						Text("Go Map!!")
						Text("GPX Trace")
							.foregroundStyle(.secondary)
						Text(
							"\(Image(systemName: "info.circle")) \(context.state.startTime.formatted(date: .omitted, time: .shortened))")
							.foregroundStyle(.secondary)
					}
					.font(.caption)
				}
			}

			// MARK: Dynamic Island (Compact)

			compactLeading: {
				Text(
					"\(Image(systemName: "point.bottomleft.forward.to.point.topright.scurvepath")) \(context.state.pointCount)")
			} compactTrailing: {
				Text("\(context.state.durationHMS) \(Image(systemName: "stopwatch"))")
			} minimal: {
				Image("AppIconTransparent")
					.resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
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
