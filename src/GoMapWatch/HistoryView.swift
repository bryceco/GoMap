//
//  HistoryView.swift
//  GoMapWatch
//
//  Copyright © 2026 Bryce Cogswell. All rights reserved.
//

import SwiftUI

struct HistoryView: View {
	@EnvironmentObject private var model: WatchGpxModel

	var body: some View {
		Group {
			if let traces = model.history {
				if traces.isEmpty {
					ContentUnavailableView("No Traces",
					                       systemImage: gpxTraceSymbol,
					                       description: Text("GPX traces you record appear here."))
				} else {
					List {
						ForEach(traces) { trace in
							HistoryRow(trace: trace)
						}
						.onDelete { offsets in
							for trace in offsets.map({ traces[$0] }) {
								model.delete(trace)
							}
						}
					}
				}
			} else {
				ProgressView()
			}
		}
		.navigationTitle("History")
		.onAppear {
			model.loadHistory()
		}
	}
}

private struct HistoryRow: View {
	let trace: GpxTraceSummary

	var body: some View {
		HStack(spacing: 10) {
			TraceOutline(points: trace.outline, lineWidth: 2, ringRadius: 0)
				.frame(width: 34, height: 34)
			VStack(alignment: .leading, spacing: 2) {
				Text(trace.startTime, format: .dateTime.month(.abbreviated).day().hour().minute())
					.font(.headline)
					.lineLimit(1)
					.minimumScaleFactor(0.7)
				Text(details)
					.font(.footnote)
					.foregroundStyle(.secondary)
			}
		}
		.padding(.vertical, 2)
	}

	private var details: String {
		let duration = Duration.seconds(trace.duration.rounded())
			.formatted(.time(pattern: trace.duration >= 3600 ? .hourMinuteSecond : .minuteSecond))
		return String(localized: "\(duration) · \(trace.pointCount) points")
	}
}
