//
//  GpxTrackWidgetManager.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 5/5/24.
//  Copyright © 2024 Bryce Cogswell. All rights reserved.
//

#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit

func widgetStartGPS() {
	if #available(iOS 16.2, *) {
		GpxTrackWidgetManager.shared.startTrack(fromWidget: true)
	}
}

func widgetStopGPS() {
	if #available(iOS 16.2, *) {
		GpxTrackWidgetManager.shared.endTrack(fromWidget: true)
	}
}

func widgetPauseGPS() {
	if #available(iOS 16.2, *) {
		GpxTrackWidgetManager.shared.pauseTrack()
	}
}

protocol GpxTrackWidgetManagerProtocol {
	func startTrack(fromWidget: Bool)
	func updateTrack()
	func endTrack(fromWidget: Bool)
}

@available(iOS 16.2, *)
final class GpxTrackWidgetManager: GpxTrackWidgetManagerProtocol {
	var activity: Activity<GpxTrackAttributes>?

	public static let shared = GpxTrackWidgetManager()

	private init() {
		activity = nil
	}

	// These functions are called in response to user pressing a live widget button

	func startTrack(fromWidget: Bool) {
		guard activity == nil else {
			resumeTrack()
			return
		}

		if fromWidget {
			// start a new track
			AppDelegate.shared.mainView.gpsState = .LOCATION
		}

		// get the track
		guard let track = AppDelegate.shared.mapView.gpxLayer.activeTrack else {
			return
		}

		// create a new activity
		let attributes = GpxTrackAttributes()
		let state = GpxTrackAttributes.GpxTrackStatus(startTime: track.creationDate,
		                                              endTime: nil,
		                                              pointCount: 0,
		                                              status: .running)
		let s2 = ActivityContent<GpxTrackAttributes.GpxTrackStatus>(state: state,
		                                                            staleDate: nil)
		do {
			activity = try Activity<GpxTrackAttributes>.request(attributes: attributes,
			                                                    content: s2,
			                                                    pushType: nil)
		} catch {
			print("Live Activity: \(error.localizedDescription)")
		}
	}

	func resumeTrack() {
		guard let activity = activity else {
			// This shouldn't ever happen, but just in case...
			startTrack(fromWidget: true)
			return
		}

		// start a new track
		AppDelegate.shared.mainView.gpsState = .LOCATION

		// get the track
		guard let track = AppDelegate.shared.mapView.gpxLayer.activeTrack else {
			print("missing track")
			return
		}

		let state = GpxTrackAttributes.ContentState(startTime: track.creationDate,
		                                            endTime: nil,
		                                            pointCount: 0,
		                                            status: .running)
		Task {
			await activity.update(using: state)
		}
	}

	func updateTrack() {
		guard let activity = activity,
		      let track = AppDelegate.shared.mapView.gpxLayer.activeTrack
		else {
			return
		}
		let state = GpxTrackAttributes.ContentState(startTime: track.creationDate,
		                                            pointCount: track.points.count)
		Task {
			await activity.update(using: state)
		}
	}

	func pauseTrack() {
		print("pause")
		guard let activity = activity,
		      let track = AppDelegate.shared.mapView.gpxLayer.activeTrack
		else {
			return
		}
		AppDelegate.shared.mainView.gpsState = .NONE
		Task {
			var state = activity.content.state
			state.endTime = Date()
			state.pointCount = track.points.count
			state.status = .paused
			await activity.update(using: state)
		}
	}

	func endTrack(fromWidget: Bool) {
		guard let activity = activity,
		      let track = AppDelegate.shared.mapView.gpxLayer.activeTrack
		else {
			return
		}
		Task {
			var state = activity.content.state
			state.endTime = Date()
			state.pointCount = track.points.count
			state.status = .ended
			await activity.end(using: state, dismissalPolicy: .immediate)
		}
		if fromWidget {
			AppDelegate.shared.mainView.gpsState = .NONE
		}
		self.activity = nil
	}

	// If app is being terminated from the background we call this to remove any live widgets
	static func endAllActivitiesSynchronously() {
		let semaphore = DispatchSemaphore(value: 0)
		Task {
			for activity in Activity<GpxTrackAttributes>.activities {
				await activity.end(nil, dismissalPolicy: .immediate)
			}
			semaphore.signal()
		}
		semaphore.wait()
	}
}
#endif
