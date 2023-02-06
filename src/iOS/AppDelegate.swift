//
//  AppDelegate.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/6/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

import UIKit
import UserNotifications

@objcMembers
class AppDelegate: UIResponder, UIApplicationDelegate {
	class var shared: AppDelegate {
		return UIApplication.shared.delegate as! AppDelegate
	}

	var window: UIWindow?
	weak var mapView: MapView!
	private(set) var isAppUpgrade = false

	let oAuth2 = OAuth2()

	var userName: String? {
		get { UserDefaults.standard.string(forKey: "userName") }
		set { UserDefaults.standard.set(newValue, forKey: "userName") }
	}

	override init() {
		super.init()

		// do translations from old Obj-C names to Swift names
		NSKeyedUnarchiver.setClass(QuadMap.classForKeyedArchiver(), forClassName: "QuadMap")
		NSKeyedUnarchiver.setClass(QuadBox.classForKeyedArchiver(), forClassName: "QuadBox")
		NSKeyedUnarchiver.setClass(QuadBox.classForKeyedArchiver(), forClassName: "QuadBoxC")

		NSKeyedUnarchiver.setClass(MyUndoManager.classForKeyedArchiver(), forClassName: "UndoManager")

		NSKeyedUnarchiver.setClass(OsmNode.classForKeyedArchiver(), forClassName: "OsmNode")
		NSKeyedUnarchiver.setClass(OsmWay.classForKeyedArchiver(), forClassName: "OsmWay")
		NSKeyedUnarchiver.setClass(OsmRelation.classForKeyedArchiver(), forClassName: "OsmRelation")
		NSKeyedUnarchiver.setClass(OsmMember.classForKeyedArchiver(), forClassName: "OsmMember")

		NSKeyedUnarchiver.setClass(OsmMapData.classForKeyedArchiver(), forClassName: "OsmMapData")

		NSKeyedUnarchiver.setClass(PresetKeyUserDefined.classForKeyedArchiver(), forClassName: "CustomPreset")
		NSKeyedUnarchiver.setClass(PresetValue.classForKeyedArchiver(), forClassName: "PresetValue")
		NSKeyedUnarchiver.setClass(PresetKey.classForKeyedArchiver(), forClassName: "CommonTagKey")
		NSKeyedUnarchiver.setClass(PresetValue.classForKeyedArchiver(), forClassName: "CommonTagValue")

		NSKeyedUnarchiver.setClass(GpxTrack.classForKeyedArchiver(), forClassName: "GpxTrack")
		NSKeyedUnarchiver.setClass(GpxPoint.classForKeyedArchiver(), forClassName: "GpxPoint")
	}

	func application(
		_ application: UIApplication,
		willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool
	{
		// return true to ensure URL opening code will always be invoked
		return true
	}

	func application(
		_ application: UIApplication,
		didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool
	{
#if false
		// This code sets the screen size as mandated for Mac App Store screen shots
		let setScreenSizeForAppStoreScreenShots = false
		if setScreenSizeForAppStoreScreenShots {
			let size = CGSize(
				640 * (1440.0 / 752) * (1440.0 / 1337) * (1440.0 / 1431),
				640 * (900.0 / 752) * (900.0 / 877) * (900.0 / 898) + 1)
			for scene in UIApplication.sharedApplication.connectedScenes {
				scene.sizeRestrictions.minimumSize = size
				scene.sizeRestrictions.maximumSize = size
			}
		}
#endif

		let defaults = UserDefaults.standard

		// save the app version so we can detect upgrades
		let prevVersion = defaults.object(forKey: "appVersion") as? String
		if prevVersion != appVersion() {
			print("Upgrade!")
			isAppUpgrade = true
		}
		defaults.set(appVersion(), forKey: "appVersion")

		return true
	}

	func application(
		_ application: UIApplication,
		continue userActivity: NSUserActivity,
		restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool
	{
		if userActivity.activityType == NSUserActivityTypeBrowsingWeb {
			let url = userActivity.webpageURL
			if let url = url {
				return self.application(application, open: url, options: [:])
			}
		}
		return false
	}

	func setMapLocation(_ location: MapLocation) {
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: { [self] in
			mapView.setMapLocation(location)
		})
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

	func displayGpxError(_ error: Error) {
		var message = NSLocalizedString("Sorry, an error occurred while loading the GPX file",
		                                comment: "")
		message += "\n\n"
		message += error.localizedDescription
		mapView.showAlert(NSLocalizedString("Open URL", comment: ""),
		                  message: message)
	}

	func application(_ application: UIApplication,
	                 open url: URL,
	                 options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool
	{
		if url.isFileURL {
			let data: Data
			do {
				data = try dataForScopedUrl(url)
			} catch {
				DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: { [self] in
					self.mapView.showAlert(NSLocalizedString("Invalid URL", comment: ""),
					                       message: error.localizedDescription)
				})
				return false
			}
			switch url.pathExtension.lowercased() {
			case "gpx":
				// Load GPX
				DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: { [self] in
					do {
						try mapView.gpxLayer.loadGPXData(data, center: true)
						mapView.updateMapMarkersFromServer(withDelay: 0.1, including: [.gpx])
					} catch {
						displayGpxError(error)
					}
				})
				return true
			case "jpg", "jpeg", "png", "heic":
				// image file: try to extract location of image from EXIF
				if let sourceRef: CGImageSource = CGImageSourceCreateWithData(data as CFData, nil),
				   let properties = CGImageSourceCopyPropertiesAtIndex(sourceRef, 0, nil) as? [AnyHashable: Any],
				   let exif = properties[kCGImagePropertyExifDictionary],
				   let dict = exif as? [String: Any]
				{
					// Unfortunately this doesn't include the Lat/Lon.
					// One option is to use a library like https://code.google.com/archive/p/iphone-exif/
					print("\(dict)")
					return false
				}
				return false
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
				oAuth2.redirectHandler(url: url, options: options)
				return true
			}

			if components.scheme == "gomaposm",
			   let base64 = components.queryItems?.first(where: { $0.name == "gpxurl" })?.value,
			   let gpxUrlData = Data(base64Encoded: base64, options: []),
			   let gpxUrl = String(data: gpxUrlData, encoding: .utf8),
			   let gpxUrl = URL(string: gpxUrl)
			{
				URLSession.shared.data(with: gpxUrl) { result in
					DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: { [self] in
						switch result {
						case let .success(data):
							do {
								try mapView.gpxLayer.loadGPXData(data, center: true)
								mapView.updateMapMarkersFromServer(withDelay: 0.1, including: [.gpx])
							} catch {
								displayGpxError(error)
							}
						case let .failure(error):
							displayGpxError(error)
						}
					})
				}
				return true
			}

			// geo: gomaposm: and arbitrary URLs containing lat/lon coordinates
			if let parserResult = LocationParser.mapLocationFrom(url: url) {
				DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: { [self] in
					setMapLocation(parserResult)
				})
				return true
			} else {
				DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: { [self] in
					self.mapView.showAlert(NSLocalizedString("Invalid URL", comment: ""),
					                       message: url.absoluteString)
				})
				return false
			}
		}
	}

	func appName() -> String {
		return Bundle.main.infoDictionary?["CFBundleDisplayName"] as! String
	}

	func appVersion() -> String {
		return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as! String
	}

	func appBuildNumber() -> String {
		return Bundle.main.infoDictionary?["CFBundleVersion"] as! String
	}

	func applicationWillResignActive(_ application: UIApplication) {
		// Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
		// Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
	}

	func applicationDidEnterBackground(_ application: UIApplication) {
		// set app badge if edits are pending
		let pendingEdits = mapView?.editorLayer.mapData.modificationCount() ?? 0
		if pendingEdits != 0 {
			UNUserNotificationCenter.current().requestAuthorization(options: .badge, completionHandler: { _, _ in
			})
		}
		UIApplication.shared.applicationIconBadgeNumber = pendingEdits

		// while in background don't update our location so we don't download tiles/OSM data when moving
		mapView.userOverrodeLocationPosition = true
		mapView?.locationManager.stopUpdatingHeading()
	}

	// Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
	func applicationWillEnterForeground(_ application: UIApplication) {
		// allow gps to update our location
		mapView.userOverrodeLocationPosition = false
		if mapView?.gpsState != GPS_STATE.NONE {
			mapView?.locationManager.startUpdatingHeading()
		}

		// remove badge now, so it disappears promptly on exit
		UIApplication.shared.applicationIconBadgeNumber = 0
	}

	func applicationDidBecomeActive(_ application: UIApplication) {
		// Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
	}

	func applicationWillTerminate(_ application: UIApplication) {
		// Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
	}

	class func askUser(toAllowLocationAccess parentVC: UIViewController) {
		let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
		let title = String.localizedStringWithFormat(
			NSLocalizedString("Turn On Location Services to Allow %@ to Determine Your Location", comment: ""),
			appName ?? "")

		AppDelegate.askUserToOpenSettings(withAlertTitle: title, message: nil, parentVC: parentVC)
	}

	class func askUserToOpenSettings(withAlertTitle title: String, message: String?, parentVC: UIViewController) {
		let alertController = UIAlertController(
			title: title,
			message: message,
			preferredStyle: .alert)
		let okayAction = UIAlertAction(
			title: NSLocalizedString("OK", comment: ""),
			style: .cancel,
			handler: nil)
		let openSettings = UIAlertAction(
			title: NSLocalizedString("Open Settings", comment: "Open the iOS Settings app"),
			style: .default,
			handler: { _ in
				AppDelegate.openAppSettings()
			})

		alertController.addAction(openSettings)
		alertController.addAction(okayAction)

		parentVC.present(alertController, animated: true)
	}

	class func openAppSettings() {
		let openSettingsURL = URL(string: UIApplication.openSettingsURLString)
		if let openSettingsURL = openSettingsURL {
			UIApplication.shared.open(openSettingsURL, options: [:], completionHandler: nil)
		}
	}
}
