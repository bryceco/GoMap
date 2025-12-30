//
//  AppDelegate.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/6/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

import UIKit
import UserNotifications

func showInternalError(_ error: Error, context: String?) {
	Task { @MainActor in
		let message = """
		\(String(describing: error))
		\(context ?? "")

		Please send a screen shot of this message to the developer
		"""
		AppDelegate.shared.mapView.showAlert("Internal error",
		                                     message: message)
	}
}

@objcMembers
class AppDelegate: UIResponder, UIApplicationDelegate {
	class var shared: AppDelegate {
		return UIApplication.shared.delegate as! AppDelegate
	}

	weak var mapView: MapView!
	private(set) var isAppUpgrade = false

	var userName: String? {
		get { UserPrefs.shared.userName.value }
		set { UserPrefs.shared.userName.value = newValue }
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

	func application(_ application: UIApplication,
	                 configurationForConnecting connectingSceneSession: UISceneSession,
	                 options: UIScene.ConnectionOptions) -> UISceneConfiguration
	{
		return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
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

		// save the app version so we can detect upgrades
		let prevVersion = UserPrefs.shared.appVersion.value
		if prevVersion != Self.appVersion {
			print("Upgrade!")
			isAppUpgrade = true
			UserPrefs.shared.appVersion.value = Self.appVersion
			UserPrefs.shared.uploadCountPerVersion.value = 0
		}

		// Sync preferences in iCloud
		UserPrefs.shared.synchronize()
		if isAppUpgrade {
			// This only does any work if the iCloud store is empty,
			// otherwise it just returns
			UserPrefs.shared.copyUserDefaultsToUbiquitousStore()
		}

		// access the current OSM server to force capabilities download
		_ = OSM_SERVER
		return true
	}

	static let appName: String = Bundle.main.infoDictionary?["CFBundleDisplayName"] as! String

	static let appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as! String

	static let appBuildNumber: String = Bundle.main.infoDictionary?["CFBundleVersion"] as! String

	static let bundleName: String = String(Bundle.main.bundleIdentifier!.split(separator: ".").last!)

	func applicationWillTerminate(_ application: UIApplication) {
		// Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground.

		// Turn off GPS so we gracefully end GPX trace.
		AppDelegate.shared.mapView?.mainViewController.setGpsState(.NONE)

#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
		// Remove any live activities
		if #available(iOS 16.2, *) {
			GpxTrackWidgetManager.endAllActivitiesSynchronously()
		}
#endif
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
