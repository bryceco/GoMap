//
//  ContentView.swift
//  GoMapWatch
//
//  Copyright © 2026 Bryce Cogswell. All rights reserved.
//

import SwiftUI

private let screenBackground = LinearGradient(colors: [.black, Color.goMapSlate.opacity(0.9)],
                                              startPoint: .top,
                                              endPoint: .bottom)

struct ContentView: View {
	@EnvironmentObject private var model: WatchGpxModel
	@Environment(\.scenePhase) private var scenePhase
	@State private var page = Page.trace

	private enum Page {
		case controls
		case trace
	}

	var body: some View {
		NavigationStack {
			Group {
				if model.state.status == .idle {
					StartView()
				} else {
					TabView(selection: $page) {
						ControlsView().tag(Page.controls)
						TraceView().tag(Page.trace)
					}
					.tabViewStyle(.page)
				}
			}
			.containerBackground(screenBackground, for: .navigation)
		}
		.onChange(of: model.state.status) { _, status in
			if status == .running {
				page = .trace
			}
		}
		.onChange(of: scenePhase) { _, phase in
			if phase == .active {
				model.keepOnScreenIfRecording()
			}
		}
		.alert(model.errorMessage ?? "",
		       isPresented: Binding(get: { model.errorMessage != nil },
		                            set: { if !$0 { model.errorMessage = nil } }))
		{
			Button("OK", role: .cancel) {}
		}
	}

}

struct StartView: View {
	@EnvironmentObject private var model: WatchGpxModel
	@State private var askToRecordInBackground = false

	var body: some View {
		VStack(spacing: 6) {
			Image(systemName: gpxTraceSymbol)
				.font(.system(size: 36, weight: .semibold))
				.foregroundStyle(Color.goMapGreen)
			Text("GPX Trace")
				.font(.title3.weight(.semibold))
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.padding(.bottom, 16)
		.toolbar {
			ToolbarItem(placement: .topBarLeading) {
				NavigationLink {
					HistoryView()
				} label: {
					Image(systemName: "clock.arrow.circlepath")
				}
				.accessibilityLabel("History")
			}
			ToolbarItem(placement: .topBarTrailing) {
				NavigationLink {
					SettingsView()
				} label: {
					Image(systemName: needsAttention ? "exclamationmark.triangle.fill" : "gearshape")
						.foregroundStyle(needsAttention ? Color.goMapYellow : .primary)
				}
				.accessibilityLabel("Settings")
			}
			ToolbarItemGroup(placement: .bottomBar) {
				Spacer()
				Button {
					if model.state.recordsInBackground {
						model.send(.start)
					} else {
						askToRecordInBackground = true
					}
				} label: {
					Image(systemName: "play.fill")
				}
				.controlSize(.large)
				.disabled(model.isSending)
				.accessibilityLabel("Start GPX Trace")
				Spacer()
			}
		}
		.alert("Keep recording when your iPhone is locked?", isPresented: $askToRecordInBackground) {
			Button("Turn On and Start") {
				model.setBackgroundRecording(true)
				model.send(.start)
			}
			Button("Start Anyway") {
				model.send(.start)
			}
			Button("Cancel", role: .cancel) {}
		} message: {
			Text("Record in Background is off in Go Map!! on your iPhone, so recording stops when Go Map!! isn't open.")
		}
	}

	private var needsAttention: Bool {
		!model.state.recordsInBackground || !model.state.hasAlwaysLocationAccess
	}
}

struct SettingsView: View {
	@EnvironmentObject private var model: WatchGpxModel

	var body: some View {
		List {
			Section {
				Toggle("Record in Background",
				       isOn: Binding(get: { model.state.recordsInBackground },
				                     set: { model.setBackgroundRecording($0) }))
					.tint(.goMapGreen)
			} footer: {
				Text("Keeps recording when your iPhone is locked or Go Map!! isn't open. Also shows GPX traces on the iPhone's map.")
			}
			if model.state.recordsInBackground, !model.state.hasAlwaysLocationAccess {
				Section {
					Label("Location access", systemImage: "location.slash")
						.foregroundStyle(Color.goMapYellow)
				} footer: {
					Text("On your iPhone, open Settings › Apps › Go Map!! › Location and choose Always.")
				}
			}
		}
		.navigationTitle("Settings")
		.onAppear {
			model.send(.refresh)
		}
	}
}

struct TraceView: View {
	@EnvironmentObject private var model: WatchGpxModel

	var body: some View {
		let state = model.state
		VStack(spacing: 6) {
			TraceOutline(points: state.outline)
			HStack(alignment: .bottom) {
				metric("Points", alignment: .leading) {
					Text("\(state.pointCount)")
				}
				Spacer(minLength: 8)
				metric("Duration", alignment: .trailing) {
					if let start = state.startTime {
						HStack(spacing: 4) {
							if state.status == .paused {
								Image(systemName: "pause.fill")
									.font(.system(size: 20, weight: .semibold))
									.accessibilityLabel("Paused")
							}
							Text(timerInterval: start...Date.distantFuture, pauseTime: state.endTime, countsDown: false)
						}
						.foregroundStyle(state.status == .paused ? Color.goMapYellow : .primary)
					}
				}
			}
			.padding(.horizontal, 10)
		}
		.padding(.bottom, 4)
	}

	private func metric(_ caption: LocalizedStringKey, alignment: HorizontalAlignment,
	                    @ViewBuilder value: () -> some View) -> some View
	{
		VStack(alignment: alignment, spacing: -2) {
			value()
				.font(.system(size: 30, weight: .semibold))
				.monospacedDigit()
				.lineLimit(1)
				.minimumScaleFactor(0.6)
			Text(caption)
				.font(.footnote)
				.foregroundStyle(.secondary)
		}
	}
}

struct TraceOutline: View {
	let points: [[Double]]
	var lineWidth = 4.0
	var ringRadius = 5.0

	var body: some View {
		Canvas { context, size in
			guard points.count > 1 else { return }
			let lats = points.map { $0[0] }
			let midLat = (lats.min()! + lats.max()!) / 2
			let xs = points.map { $0[1] * cos(midLat * .pi / 180) }
			let (minX, maxX, minY, maxY) = (xs.min()!, xs.max()!, lats.min()!, lats.max()!)
			let inset = ringRadius + lineWidth
			let scale = min((size.width - 2 * inset) / max(maxX - minX, 1e-9),
			                (size.height - 2 * inset) / max(maxY - minY, 1e-9))
			func point(_ i: Int) -> CGPoint {
				CGPoint(x: size.width / 2 + (xs[i] - (minX + maxX) / 2) * scale,
				        y: size.height / 2 - (lats[i] - (minY + maxY) / 2) * scale)
			}
			var path = Path()
			path.move(to: point(0))
			for i in 1..<points.count {
				path.addLine(to: point(i))
			}
			let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
			context.stroke(path, with: .color(.gpxTrace), style: style)
			guard ringRadius > 0 else { return }
			for end in [point(0), point(points.count - 1)] {
				let r = ringRadius
				let ring = Path(ellipseIn: CGRect(x: end.x - r, y: end.y - r, width: 2 * r, height: 2 * r))
				context.fill(ring, with: .color(.black))
				context.stroke(ring, with: .color(.gpxTrace), style: style)
			}
		}
		.overlay {
			if points.count < 2, ringRadius > 0 {
				Text("Waiting for GPS…")
					.font(.footnote)
					.foregroundStyle(.secondary)
			}
		}
	}
}

struct ControlsView: View {
	@EnvironmentObject private var model: WatchGpxModel

	var body: some View {
		HStack(spacing: 10) {
			ControlButton(title: "End", systemImage: "xmark", tint: .red) {
				model.send(.stop)
			}
			if model.state.status == .paused {
				ControlButton(title: "Resume", systemImage: "play.fill", tint: .goMapGreen) {
					model.send(.start)
				}
			} else {
				ControlButton(title: "Pause", systemImage: "pause.fill", tint: .goMapYellow) {
					model.send(.pause)
				}
			}
		}
		.padding(.horizontal, 8)
		.disabled(model.isSending)
	}
}

private struct ControlButton: View {
	let title: LocalizedStringKey
	let systemImage: String
	let tint: Color
	let action: () -> Void

	var body: some View {
		VStack(spacing: 6) {
			Button(action: action) {
				Image(systemName: systemImage)
					.font(.title2)
					.frame(maxWidth: .infinity, minHeight: 44)
			}
			.buttonStyle(.bordered)
			.buttonBorderShape(.roundedRectangle)
			.tint(tint)
			Text(title)
				.font(.footnote)
		}
	}
}
