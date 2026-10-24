//
//  WatchGpxSession.swift
//  Go Map!!
//
//  Copyright © 2026 Bryce Cogswell. All rights reserved.
//

import CoreLocation
import UIKit
import WatchConnectivity

final class WatchGpxSession: NSObject, WCSessionDelegate {
	static let shared = WatchGpxSession()

	private static let maxOutlinePoints = 200
	private static let maxHistoryOutlinePoints = 40
	private static let maxHistoryCount = 20
	private static let minUpdateInterval = 5.0
	private static let minComplicationInterval = 15.0 * 60

	private let locationManager = CLLocationManager()
	private var pausedState: GpxWatchState?
	private var lastUpdate = Date.distantPast
	private var lastComplicationUpdate = Date.distantPast
	private var lastComplicationStatus: GpxWatchState.Status?

	func activate() {
		guard WCSession.isSupported() else { return }
		WCSession.default.delegate = self
		WCSession.default.activate()
	}

	func update(force: Bool = false) {
		guard WCSession.isSupported(),
		      WCSession.default.activationState == .activated,
		      force || Date().timeIntervalSince(lastUpdate) >= Self.minUpdateInterval
		else {
			return
		}
		lastUpdate = Date()
		let session = WCSession.default
		var state = currentState()
		try? session.updateApplicationContext(state.encoded())

		if session.isComplicationEnabled,
		   state.status != lastComplicationStatus
		   || Date().timeIntervalSince(lastComplicationUpdate) >= Self.minComplicationInterval
		{
			state.outline = []
			session.transferCurrentComplicationUserInfo(state.encoded())
			lastComplicationStatus = state.status
			lastComplicationUpdate = Date()
		}
	}

	private func currentState() -> GpxWatchState {
		let tracks = AppState.shared.gpxTracks
		var state = pausedState ?? GpxWatchState()
		if let track = tracks.activeTrack {
			state = GpxWatchState()
			state.status = .running
			state.startTime = tracks.activeTrackStartDate
			state.pointCount = tracks.activeTrackTotalPointCount
			state.outline = Self.outline(of: track, maxCount: Self.maxOutlinePoints)
		}
		state.recordsInBackground = tracks.recordTracksInBackground
			&& (AppDelegate.shared.mainView?.settings.displayGpxTracks ?? false)
		state.hasAlwaysLocationAccess = locationManager.authorizationStatus == .authorizedAlways
		return state
	}

	private static func outline(of track: GpxTrack, maxCount: Int) -> [[Double]] {
		return track.points.map { [$0.latLon.lat, $0.latLon.lon] }.simplified(to: maxCount)
	}

	private func history() -> [GpxTraceSummary] {
		return AppState.shared.gpxTracks.savedTracks.prefix(Self.maxHistoryCount).map {
			GpxTraceSummary(id: $0.fileBaseName(),
			                startTime: $0.creationDate,
			                duration: $0.duration(),
			                pointCount: $0.points.count,
			                outline: Self.outline(of: $0, maxCount: Self.maxHistoryOutlinePoints))
		}
	}

	private func perform(_ command: GpxWatchState.Command, message: [String: Any]) -> [String: Any] {
		guard let mainView = AppDelegate.shared.mainView else { return [:] }
		let tracks = AppState.shared.gpxTracks
		switch command {
		case .refresh:
			return [:]
		case .history:
			return GpxTraceSummary.encoded(history())
		case .delete:
			if let id = message[GpxWatchState.traceIdKey] as? String,
			   let track = tracks.savedTracks.first(where: { $0.fileBaseName() == id })
			{
				tracks.delete(track: track)
			}
			return GpxTraceSummary.encoded(history())
		case .setBackgroundRecording:
			let enabled = message[GpxWatchState.enabledKey] as? Bool ?? true
			if enabled {
				mainView.settings.displayGpxTracks = true
			}
			tracks.recordTracksInBackground = enabled
		case .start, .pause, .stop:
			setRecording(command, mainView: mainView)
		}
		update(force: true)
		return [:]
	}

	private func setRecording(_ command: GpxWatchState.Command, mainView: MainViewController) {
		pausedState = nil
		if command == .pause, AppState.shared.gpxTracks.activeTrack != nil {
			var state = currentState()
			state.status = .paused
			state.endTime = Date()
			pausedState = state
		}

#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
		if UIApplication.shared.applicationState == .background {
			switch command {
			case .start: widgetStartGPS()
			case .pause: widgetPauseGPS()
			default: widgetStopGPS()
			}
		}
#endif
		if command == .start {
			if mainView.gpsState == .NONE {
				mainView.gpsState = .LOCATION
			}
		} else if mainView.gpsState != .NONE {
			mainView.gpsState = .NONE
		}
	}

	func session(_ session: WCSession,
	             activationDidCompleteWith activationState: WCSessionActivationState,
	             error: Error?)
	{
		DispatchQueue.main.async {
			self.update(force: true)
		}
	}

	func session(_ session: WCSession,
	             didReceiveMessage message: [String: Any],
	             replyHandler: @escaping ([String: Any]) -> Void)
	{
		DispatchQueue.main.async {
			var reply: [String: Any] = [:]
			if let name = message[GpxWatchState.commandKey] as? String,
			   let command = GpxWatchState.Command(rawValue: name)
			{
				reply = self.perform(command, message: message)
			}
			reply.merge(self.currentState().encoded()) { current, _ in current }
			replyHandler(reply)
		}
	}

	func sessionDidBecomeInactive(_ session: WCSession) {}

	func sessionDidDeactivate(_ session: WCSession) {
		session.activate()
	}
}
