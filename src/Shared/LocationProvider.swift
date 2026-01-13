//
//  LocationProvider.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 1/13/26.
//  Copyright © 2026 Bryce Cogswell. All rights reserved.
//

import CoreLocation
import Foundation

final class LocationProvider: NSObject, CLLocationManagerDelegate {

	static let shared = LocationProvider()
	var ignoreInitialStatusUpdate = false

	private let locationManager: CLLocationManager!
	private(set) var currentLocation: CLLocation? {
		didSet {
			if let currentLocation {
				onChangeLocation.notify(currentLocation)
			}
		}
	}

	private(set) var currentHeading: CLHeading? {
		didSet {
			if let currentHeading {
				onChangeHeading.notify(currentHeading)
			}
		}
	}

	private(set) var smoothHeading = 0.0 {
		didSet {
			onChangeSmoothHeading.notify(smoothHeading)
		}
	}

	let onChangeHeading = NotificationService<CLHeading>()
	let onChangeSmoothHeading = NotificationService<Double>()
	let onChangeLocation = NotificationService<CLLocation>()

	var allowsBackgroundLocationUpdates: Bool {
		get {
			locationManager.allowsBackgroundLocationUpdates
		}
		set {
			locationManager.allowsBackgroundLocationUpdates = newValue
		}
	}

	override init() {
		locationManager = CLLocationManager()
		super.init()

		ignoreInitialStatusUpdate = true // flag that we're going to receive an extra notification from CL
		locationManager.delegate = self
		locationManager.pausesLocationUpdatesAutomatically = false
		locationManager.allowsBackgroundLocationUpdates = GpxLayer.recordTracksInBackground
			&& AppDelegate.shared.mapView.displayGpxTracks
		if #available(iOS 11.0, *) {
			locationManager.showsBackgroundLocationIndicator = true
		}
		locationManager.activityType = .other

		locationManager.delegate = self

		NotificationCenter.default.addObserver(
			self,
			selector: #selector(backgroundCollectionSettingChanged(_:)),
			name: NSNotification.Name("CollectGpxTracksInBackgroundChanged"),
			object: nil)
	}

	@objc func backgroundCollectionSettingChanged(_ notification: Notification) {
		if GpxLayer.recordTracksInBackground,
		   AppDelegate.shared.mapView.displayGpxTracks
		{
			allowsBackgroundLocationUpdates = true
			locationManager.requestAlwaysAuthorization()
		} else {
			allowsBackgroundLocationUpdates = false
		}
	}

	func start() {
		let mapView = AppDelegate.shared.mapView!
		let mainView = AppDelegate.shared.mainView!

		let status: CLAuthorizationStatus
		if #available(iOS 14.0, *) {
			status = locationManager.authorizationStatus
		} else {
			status = CLLocationManager.authorizationStatus()
		}
		switch status {
		case .notDetermined:
			// we haven't asked user before, so have iOS pop up the question
			locationManager.requestWhenInUseAuthorization()
			mapView.gpsState = .NONE
			return
		case .restricted, .denied:
			// user denied permission previously, so ask if they want to open Settings
			AppDelegate.askUser(toAllowLocationAccess: mainView)
			mapView.gpsState = .NONE
			return
		case .authorizedAlways, .authorizedWhenInUse:
			break
		default:
			break
		}

		locationManager.startUpdatingLocation()
		locationManager.startUpdatingHeading()
	}

	func stop() {
		locationManager.stopUpdatingLocation()
		locationManager.stopUpdatingHeading()
		currentLocation = nil
	}

	func updateToLocation(_ newLocation: CLLocation) {
		guard AppDelegate.shared.mapView.gpsState != .NONE else {
			// sometimes we get a notification after turning off notifications
			DLog("discard location notification")
			return
		}

		guard newLocation.timestamp >= Date(timeIntervalSinceNow: -10.0) else {
			// its old data
			DLog("discard old GPS data: \(newLocation.timestamp), \(Date())\n")
			return
		}

		if let currentLocation,
		   GreatCircleDistance(newLocation.coordinate, currentLocation.coordinate) >= 0.1 ||
		   abs(newLocation.horizontalAccuracy - currentLocation.horizontalAccuracy) >= 1.0
		{
			// didn't move far, and the accuracy didn't change either, so ignore it
			return
		}
		self.currentLocation = newLocation
	}

	// MARK: CLLocationManagerDelegate

	func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
		let viewPort = AppDelegate.shared.mapView.viewPort

		let accuracy = newHeading.headingAccuracy
		let heading = viewPort.headingAdjustedForInterfaceOrientation(newHeading)

		self.currentHeading = newHeading

		DisplayLink.shared.addName("smoothHeading", block: { [self] in
			var delta = heading - self.smoothHeading
			if delta > .pi {
				delta -= 2 * .pi
			} else if delta < -.pi {
				delta += 2 * .pi
			}
			delta *= 0.15
			if abs(delta) < .pi / 100.0 {
				self.smoothHeading = heading
			} else {
				self.smoothHeading += delta
			}
			viewPort.updateHeading(self.smoothHeading, accuracy: accuracy)
			if heading == self.smoothHeading {
				DisplayLink.shared.removeName("smoothHeading")
			}
		})
	}

	func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
		for location in locations {
			updateToLocation(location)
		}
	}

	func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
		print("GPS paused by iOS\n")
	}

	func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
		let mainView = AppDelegate.shared.mainView!

		var error = error
		if (error as? CLError)?.code == CLError.Code.denied {
			mainView.setGpsState(GPS_STATE.NONE)

			var text = String.localizedStringWithFormat(
				NSLocalizedString(
					"Ensure Location Services is enabled and you have granted this application access.\n\nError: %@",
					comment: ""),
				error.localizedDescription)
			text = NSLocalizedString("The current location cannot be determined: ", comment: "") + text
			error = NSError(domain: "Location", code: 100, userInfo: [
				NSLocalizedDescriptionKey: text
			])
			MessageDisplay.shared.presentError(title: nil, error: error, flash: false)
		} else {
			// driving through a tunnel or something
			let text = NSLocalizedString("Location unavailable", comment: "")
			error = NSError(domain: "Location", code: 100, userInfo: [
				NSLocalizedDescriptionKey: text
			])
			MessageDisplay.shared.presentError(title: nil, error: error, flash: true)
		}
	}

	func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
		if ignoreInitialStatusUpdate {
			// filter out extraneous notification we get when initializing CL
			ignoreInitialStatusUpdate = false
			return
		}

		var ok = false
		switch status {
		case .authorizedAlways, .authorizedWhenInUse:
			ok = true
		case .notDetermined, .restricted, .denied:
			fallthrough
		default:
			ok = false
		}
		AppDelegate.shared.mainView.setGpsState(ok ? .LOCATION : .NONE)
	}
}
