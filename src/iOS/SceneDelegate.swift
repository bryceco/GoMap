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
		guard let windowScene = scene as? UIWindowScene else { return }
		let window = UIWindow(windowScene: windowScene)

		// Load the initial view controller from Main.storyboard
		let storyboard = UIStoryboard(name: "MainStoryboard", bundle: nil)
		let rootViewController = storyboard.instantiateInitialViewController()

		window.rootViewController = rootViewController
		self.window = window
		window.makeKeyAndVisible()
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
			AppDelegate.shared.mapView.centerOn(location)
		}
	}

	func displayImportError(_ error: Error, filetype: String) {
		var message = String.localizedStringWithFormat(
			NSLocalizedString("Sorry, an error occurred while loading the %@ file",
			                  comment: "Argument is a file type like 'GPX' or 'GeoJSON'"),
			filetype)
		message += "\n\n"
		message += error.localizedDescription
		AppDelegate.shared.mapView.showAlert(NSLocalizedString("Open URL", comment: ""),
		                                     message: message)
	}

	func openUrl(_ url: URL) -> Bool {
		let localizedGPX = NSLocalizedString("GPX", comment: "The name of a GPX file")
		let mapView = AppDelegate.shared.mapView!

		if url.isFileURL {
			let data: Data
			do {
				data = try dataForScopedUrl(url)
			} catch {
				MainActor.runAfter(nanoseconds: 100_000000) {
					mapView.showAlert(NSLocalizedString("Invalid URL", comment: ""),
					                  message: error.localizedDescription)
				}
				return false
			}
			switch url.pathExtension.lowercased() {
			case "gpx":
				// Load GPX
				MainActor.runAfter(nanoseconds: 500_000000) {
					do {
						try mapView.gpxLayer.loadGPXData(data, name: url.lastPathComponent, center: true)
						mapView.updateMapMarkersFromServer(withDelay: 0.1, including: [.gpx])
					} catch {
						self.displayImportError(error, filetype: localizedGPX)
					}
				}
				return true
			case "jpg", "jpeg", "png", "heic":
				// image file: try to extract location of image from EXIF
				if let sourceRef: CGImageSource = CGImageSourceCreateWithData(data as CFData, nil),
				   let properties = CGImageSourceCopyPropertiesAtIndex(sourceRef, 0, nil) as? [AnyHashable: Any],
				   let exif = properties[kCGImagePropertyExifDictionary],
				   let dict = exif as? [String: Any]
				{
					// Unfortunately this doesn't include the Lat/Lon.
					print("\(dict)")
					return false
				}
				return false
			case "geojson":
				// Load GeoJSON into user custom data layer
				MainActor.runAfter(nanoseconds: 500_000000) {
					do {
						let geo = try GeoJSONFile(data: data)
						try geoJsonList.add(name: url.lastPathComponent, data: data)
						if let loc = geo.firstPoint() {
							mapView.centerOn(latLon: loc)
							mapView.displayDataOverlayLayers = true
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
			   let base64 = components.queryItems?.first(where: { $0.name == "gpxurl" })?.value,
			   let gpxUrlData = Data(base64Encoded: base64, options: []),
			   let gpxUrl = String(data: gpxUrlData, encoding: .utf8),
			   let gpxUrl = URL(string: gpxUrl)
			{
				Task {
					do {
						let data = try await URLSession.shared.data(with: gpxUrl)
						try await Task.sleep(nanoseconds: 100_000000)
						await MainActor.run {
							do {
								try mapView.gpxLayer.loadGPXData(data, name: "", center: true)
								mapView.updateMapMarkersFromServer(withDelay: 0.1, including: [.gpx])
							} catch {
								displayImportError(error, filetype: localizedGPX)
							}
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
					mapView.showAlert(NSLocalizedString("Invalid URL", comment: ""),
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

	func sceneDidEnterBackground(_ scene: UIScene) {
		// set app badge if edits are pending
		let mapView = AppDelegate.shared.mapView!
		let pendingEdits = mapView.editorLayer.mapData.modificationCount()
		if pendingEdits != 0 {
			UNUserNotificationCenter.current().requestAuthorization(options: .badge,
			                                                        completionHandler: { _, _ in
			                                                        })
		}
		UIApplication.shared.applicationIconBadgeNumber = pendingEdits

		// Save when we last used GPS
		mapView.gpsLastActive = Date()

		// while in background don't update our location so we don't download tiles/OSM data when moving
		mapView.locationManager.stopUpdatingHeading()

		// Save preferences in case user force-kills us while we're in background
		UserPrefs.shared.synchronize()

		if mapView.gpsState != .NONE,
		   mapView.gpsInBackground,
		   mapView.displayGpxLogs
		{
			// Show GPX activity widget
			if #available(iOS 16.2, *) {
#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
				GpxTrackWidgetManager.shared.startTrack(fromWidget: false)
#endif
			}
		} else {
			// turn off GPS tracking
			mapView.locationManager.stopUpdatingLocation()
		}
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
		let mapView = AppDelegate.shared.mapView!
		if mapView.gpsState != .NONE {
			if mapView.gpsInBackground,
			   mapView.displayGpxLogs
			{
				// GPS was running in the background
				mapView.locationManager.startUpdatingHeading()
			} else {
				// If the user recently closed the app with GPS running, then enable GPS again
				if Date().timeIntervalSince(mapView.gpsLastActive) < 30 * 60 {
					mapView.locationManager.startUpdatingLocation()
					mapView.locationManager.startUpdatingHeading()
				} else {
					// turn off GPS on resume when user hasn't used app recently
					mapView.mainViewController.setGpsState(GPS_STATE.NONE)
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
