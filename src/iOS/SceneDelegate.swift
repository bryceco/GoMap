//
//  SceneDelegate.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 6/14/25.
//  Copyright © 2025 Bryce Cogswell. All rights reserved.
//
import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
	var window: UIWindow?

	func scene(_ scene: UIScene,
	           willConnectTo session: UISceneSession,
	           options connectionOptions: UIScene.ConnectionOptions)
	{
		// open any URLs that we were passed
		for urlContext in connectionOptions.urlContexts {
			_ = openUrl(urlContext.url)
		}
	}

	func dataForScopedUrl(_ url: URL) throws -> Data {
		// sometimes we don't need to do scoping and the scoping calls will fail
		if let data = try? Data(contentsOf: url, options: []) {
			return data
		}

		guard url.isFileURL else {
			throw NSError(domain: "dataForScopedUrl",
			              code: 1,
			              userInfo: [NSLocalizedDescriptionKey: "Not a file URL"])
		}
		guard url.startAccessingSecurityScopedResource() else {
			throw NSError(domain: "dataForScopedUrl",
			              code: 1,
			              userInfo: [NSLocalizedDescriptionKey: "startAccessingSecurityScopedResource failed"])
		}
		defer {
			url.stopAccessingSecurityScopedResource()
		}
		return try Data(contentsOf: url, options: [])
	}

	func setMapLocation(_ location: MapLocation) {
		MainActor.runAfter(nanoseconds: 100_000000) {
			AppDelegate.shared.mainView.moveToLocation(location)
		}
	}

	func displayImportError(_ error: Error, filetype: String) {
		var message = String.localizedStringWithFormat(
			NSLocalizedString("Sorry, an error occurred while loading the %@ file",
			                  comment: "Argument is a file type like 'GPX' or 'GeoJSON'"),
			filetype)
		message += "\n\n"
		message += error.localizedDescription
		MessageDisplay.shared.showAlert(NSLocalizedString("Open URL", comment: ""),
		                                message: message)
	}

	func displayImageLocationStatus(success: Bool) {
		let message: String
		if success {
			message = NSLocalizedString("Location updated to the location and orientation stored in the photo.",
			                            comment: "")
		} else {
			message = NSLocalizedString("The selected image file does not contain location information.",
			                            comment: "")
		}
		MessageDisplay.shared.showAlert(NSLocalizedString("Open Image File", comment: ""),
		                                message: message)
	}

	func openUrl(_ url: URL) -> Bool {
		let localizedGPX = NSLocalizedString("GPX", comment: "The name of a GPX file")
		let mainView = AppDelegate.shared.mainView!

		func openGPX(data: Data, name: String) {
			do {
				let track = try AppState.shared.gpxTracks.loadGpxTrack(with: data, name: name)
				if let center = track?.center() {
					mainView.settings.displayGpxTracks = true // ensure GPX tracks are visible
					mainView.viewPort.centerOn(latLon: center, metersWide: nil)
					mainView.updateMapMarkers(including: [.gpx])
				}
			} catch {
				self.displayImportError(error, filetype: localizedGPX)
			}
		}

		if url.isFileURL {
			let data: Data
			do {
				data = try dataForScopedUrl(url)
			} catch {
				MainActor.runAfter(nanoseconds: 100_000000) {
					MessageDisplay.shared.showAlert(NSLocalizedString("Invalid URL", comment: ""),
					                                message: error.localizedDescription)
				}
				return false
			}
			switch url.pathExtension.lowercased() {
			case "gpx":
				// Load GPX
				MainActor.runAfter(nanoseconds: 100_000000) {
					openGPX(data: data, name: url.lastPathComponent)
				}
				return true
			case "jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "heic", "heif", "webp", "ico", "raw", "svg":
				// image file: try to extract location of image from EXIF
				guard
					let exif = EXIFInfo(url: url)
				else {
					MainActor.runAfter(nanoseconds: 100_000000) {
						self.displayImageLocationStatus(success: false)
					}
					return false
				}
				MainActor.runAfter(nanoseconds: 100_000000) {
					let loc = MapLocation(exif: exif)
					self.setMapLocation(loc)
					self.displayImageLocationStatus(success: true)
				}
				return true
			case "geojson":
				// Load GeoJSON into user custom data layer
				MainActor.runAfter(nanoseconds: 100_000000) {
					do {
						let geo = try GeoJSONFile(data: data)
						try geoJsonList.add(name: url.lastPathComponent, data: data)
						if let loc = geo.firstPoint() {
							mainView.viewPort.centerOn(latLon: loc, metersWide: nil)
							mainView.mapLayersView.displayDataOverlayLayers = true
						}
					} catch {
						self.displayImportError(
							error,
							filetype: NSLocalizedString("GeoJSON", comment: "The name of a GeoJSON file"))
					}
				}
				return true
			default:
				return false
			}

		} else {
			guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return false }

			if components.scheme == "gomaposm",
			   components.host == "oauth",
			   components.path == "/callback"
			{
				// OAuth result
				OSM_SERVER.oAuth2?.redirectHandler(url: url)
				return true
			}

			if components.scheme == "gomaposm",
			   let encoded = components.queryItems?.first(where: { $0.name == "gpxurl" })?.value,
			   let gpxUrl = encoded.removingPercentEncoding,
			   let gpxUrl = URL(string: gpxUrl)
			{
				Task {
					do {
						let data = try await URLSession.shared.data(with: gpxUrl)
						try await Task.sleep(nanoseconds: 500_000000)
						await MainActor.run {
							openGPX(data: data, name: "")
						}
					} catch {
						await MainActor.run {
							displayImportError(error, filetype: localizedGPX)
						}
					}
				}
				return true
			}

			// geo: gomaposm: and arbitrary URLs containing lat/lon coordinates
			if let parserResult = LocationParser.mapLocationFrom(url: url) {
				MainActor.runAfter(nanoseconds: 100_000000) {
					self.setMapLocation(parserResult)
				}
				return true
			} else {
				MainActor.runAfter(nanoseconds: 100_000000) {
					MessageDisplay.shared.showAlert(NSLocalizedString("Invalid URL", comment: ""),
					                                message: url.absoluteString)
				}
				return false
			}
		}
	}

	func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
		for urlContext in URLContexts {
			_ = openUrl(urlContext.url)
		}
	}

	var gpsLastActive = Date.distantPast

	func sceneDidEnterBackground(_ scene: UIScene) {
		// set app badge if edits are pending
		let mapView = AppDelegate.shared.mapView!
		let mainView = AppDelegate.shared.mainView!
		let pendingEdits = mapView.mapData.modificationCount()
		if pendingEdits != 0 {
			UNUserNotificationCenter.current().requestAuthorization(options: .badge,
			                                                        completionHandler: { _, _ in
			                                                        })
		}
		UIApplication.shared.applicationIconBadgeNumber = pendingEdits

		// Save when we last used GPS
		gpsLastActive = Date()

		// Save preferences in case user force-kills us while we're in background
		UserPrefs.shared.synchronize()

		if mainView.gpsState != .NONE,
		   AppState.shared.gpxTracks.recordTracksInBackground,
		   mainView.settings.displayGpxTracks
		{
			// Show GPX activity widget
			if #available(iOS 16.2, *) {
#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
				GpxTrackWidgetManager.shared.startTrack(fromWidget: false)
#endif
			}
		} else {
			// turn off GPS tracking
			LocationProvider.shared.stop()
		}

		// save all our data in case we never come back
		AppDelegate.shared.mainView.applicationWillEnterBackground()
	}

	func scene(_ scene: UIScene,
	           continue userActivity: NSUserActivity)
	{
		if userActivity.activityType == NSUserActivityTypeBrowsingWeb,
		   let url = userActivity.webpageURL
		{
			_ = openUrl(url)
		}
	}

	// Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
	func sceneWillEnterForeground(_ scene: UIScene) {
		let mainView = AppDelegate.shared.mainView!
		if mainView.gpsState != .NONE {
			if AppState.shared.gpxTracks.recordTracksInBackground,
			   mainView.settings.displayGpxTracks
			{
				// GPS was running in the background
				LocationProvider.shared.start()
			} else {
				// If the user recently closed the app with GPS running, then enable GPS again
				if Date().timeIntervalSince(gpsLastActive) < 30 * 60 {
					LocationProvider.shared.start()
				} else {
					// turn off GPS on resume when user hasn't used app recently
					mainView.gpsState = .NONE
				}
			}
		} else {
			// GPS wasn't enabled when we went to background
		}

		// remove icon badge now, so it disappears promptly on exit
		UIApplication.shared.applicationIconBadgeNumber = 0

		// Update preferences in case ubiquitous values changed while in the background
		UserPrefs.shared.synchronize()

// Remove GPX activity widget
#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
		if #available(iOS 16.2, *) {
			// This doesn't end the track itself, just the widget presentation:
			GpxTrackWidgetManager.shared.endTrack(fromWidget: false)
		}
#endif
	}
}
