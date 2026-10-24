//
//  WatchGpxModel.swift
//  GoMapWatch
//
//  Copyright © 2026 Bryce Cogswell. All rights reserved.
//

import SwiftUI
import WatchConnectivity
import WidgetKit

@MainActor
final class WatchGpxModel: NSObject, ObservableObject, WCSessionDelegate {
	@Published private(set) var state = GpxComplicationStore.load()
	@Published private(set) var history: [GpxTraceSummary]?
	@Published private(set) var isSending = false
	@Published var errorMessage: String?

	private static let minComplicationInterval = 60.0
	private var lastComplicationReload = Date.distantPast
	private let runtimeSession = TraceRuntimeSession()

	override init() {
		super.init()
		if WCSession.isSupported() {
			WCSession.default.delegate = self
			WCSession.default.activate()
		}
	}

	func send(_ command: GpxWatchState.Command, _ parameters: [String: Any] = [:]) {
		let session = WCSession.default
		let quiet = command == .refresh || command == .history
		guard session.activationState == .activated, session.isReachable else {
			if !quiet {
				errorMessage = String(localized: "Go Map!! needs your iPhone nearby to record GPX traces.")
			}
			return
		}
		isSending = !quiet
		var message = parameters
		message[GpxWatchState.commandKey] = command.rawValue
		session.sendMessage(message,
		                    replyHandler: { reply in
		                    	let state = GpxWatchState(reply)
		                    	let history = GpxTraceSummary.decoded(reply)
		                    	Task { @MainActor in
		                    		self.isSending = false
		                    		if let state {
		                    			self.apply(state)
		                    		}
		                    		if let history {
		                    			self.history = history
		                    		}
		                    	}
		                    },
		                    errorHandler: { error in
		                    	Task { @MainActor in
		                    		self.isSending = false
		                    		if !quiet {
		                    			self.errorMessage = error.localizedDescription
		                    		}
		                    	}
		                    })
	}

	func loadHistory() {
		send(.history)
	}

	func delete(_ trace: GpxTraceSummary) {
		history?.removeAll { $0.id == trace.id }
		send(.delete, [GpxWatchState.traceIdKey: trace.id])
	}

	func setBackgroundRecording(_ enabled: Bool) {
		send(.setBackgroundRecording, [GpxWatchState.enabledKey: enabled])
	}

	func keepOnScreenIfRecording() {
		runtimeSession.update(recording: state.status != .idle)
	}

	private func apply(_ newState: GpxWatchState) {
		let oldState = state
		state = newState
		keepOnScreenIfRecording()
		GpxComplicationStore.save(newState)
		if newState.status != oldState.status
			|| newState.startTime != oldState.startTime
			|| Date().timeIntervalSince(lastComplicationReload) >= Self.minComplicationInterval
		{
			lastComplicationReload = Date()
			WidgetCenter.shared.reloadTimelines(ofKind: GpxComplicationStore.widgetKind)
		}
	}

	nonisolated func session(_ session: WCSession,
	                         activationDidCompleteWith activationState: WCSessionActivationState,
	                         error: Error?)
	{
		let state = GpxWatchState(session.receivedApplicationContext)
		Task { @MainActor in
			if let state {
				self.apply(state)
			}
			self.send(.refresh)
		}
	}

	nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
		let state = GpxWatchState(applicationContext)
		Task { @MainActor in
			if let state {
				self.apply(state)
			}
		}
	}

	nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
		let state = GpxWatchState(userInfo)
		Task { @MainActor in
			if let state {
				self.apply(state)
			}
		}
	}

	nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
		let reachable = session.isReachable
		Task { @MainActor in
			if reachable {
				self.send(.refresh)
			}
		}
	}
}
