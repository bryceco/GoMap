//
//  GpxComplication.swift
//  GoMapWatchWidget
//
//  Copyright © 2026 Bryce Cogswell. All rights reserved.
//

import SwiftUI
import WidgetKit

struct GpxComplicationProvider: TimelineProvider {
	struct Entry: TimelineEntry {
		let date: Date
		let state: GpxWatchState
	}

	func placeholder(in context: Context) -> Entry {
		Entry(date: .now, state: GpxWatchState())
	}

	func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
		completion(Entry(date: .now, state: GpxComplicationStore.load()))
	}

	func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
		completion(Timeline(entries: [Entry(date: .now, state: GpxComplicationStore.load())], policy: .never))
	}
}

struct GpxComplicationView: View {
	let state: GpxWatchState
	@Environment(\.widgetFamily) private var family

	var body: some View {
		if let start = state.startTime, state.status != .idle {
			recording(start: start)
		} else {
			launcher
		}
	}

	@ViewBuilder private var launcher: some View {
		switch family {
		case .accessoryCorner:
			Image(systemName: gpxTraceSymbol)
				.font(.title2)
				.widgetAccentable()
				.widgetLabel("GPX")
		case .accessoryRectangular:
			VStack(alignment: .leading) {
				Label("Go Map!!", systemImage: gpxTraceSymbol)
					.font(.headline)
					.widgetAccentable()
				Text("Start GPX trace")
					.foregroundStyle(.secondary)
			}
			.frame(maxWidth: .infinity, alignment: .leading)
		case .accessoryInline:
			Label("Start GPX", systemImage: gpxTraceSymbol)
		default:
			ZStack {
				AccessoryWidgetBackground()
				Image(systemName: gpxTraceSymbol)
					.font(.title3)
					.widgetAccentable()
			}
		}
	}

	@ViewBuilder private func recording(start: Date) -> some View {
		let duration = Text(timerInterval: start...Date.distantFuture, pauseTime: state.endTime, countsDown: false)
		let paused = state.status == .paused
		switch family {
		case .accessoryCorner:
			Image(systemName: paused ? "pause.fill" : gpxTraceSymbol)
				.font(.title3)
				.widgetAccentable()
				.widgetLabel {
					duration
				}
		case .accessoryRectangular:
			VStack(alignment: .leading, spacing: 0) {
				Label(paused ? "GPX Paused" : "GPX Trace", systemImage: paused ? "pause.fill" : "record.circle")
					.font(.headline)
					.foregroundStyle(paused ? Color.goMapYellow : Color.gpxTrace)
					.widgetAccentable()
				duration
					.font(.title2.weight(.semibold))
					.monospacedDigit()
				Text("\(state.pointCount) points")
					.foregroundStyle(.secondary)
			}
			.frame(maxWidth: .infinity, alignment: .leading)
		case .accessoryInline:
			Text("\(Image(systemName: gpxTraceSymbol)) ") + duration + Text(" · \(state.pointCount) pts")
		default:
			ZStack {
				AccessoryWidgetBackground()
				VStack(spacing: 0) {
					Image(systemName: paused ? "pause.fill" : gpxTraceSymbol)
						.font(.caption)
						.foregroundStyle(paused ? Color.goMapYellow : Color.gpxTrace)
						.widgetAccentable()
					duration
						.font(.caption.weight(.semibold))
						.monospacedDigit()
						.multilineTextAlignment(.center)
						.minimumScaleFactor(0.6)
				}
				.padding(4)
			}
		}
	}
}

@main
struct GpxComplication: Widget {
	var body: some WidgetConfiguration {
		StaticConfiguration(kind: GpxComplicationStore.widgetKind, provider: GpxComplicationProvider()) { entry in
			GpxComplicationView(state: entry.state)
				.containerBackground(for: .widget) {}
		}
		.configurationDisplayName("GPX Trace")
		.description("Start a Go Map!! GPX trace, or see the one being recorded.")
		.supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
	}
}
