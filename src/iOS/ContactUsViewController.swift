//
//  ContactUsViewController.swift
//  Go Map!!
//
//  Created by Bryce on 4/11/20.
//  Copyright © 2020 Bryce Cogswell. All rights reserved.
//

import MessageUI
import SafariServices
import UIKit

class ContactUsViewController: UITableViewController, MFMailComposeViewControllerDelegate {
	@IBOutlet var _sendMailCell: UITableViewCell!
	@IBOutlet var _testFlightCell: UITableViewCell!
	@IBOutlet var _githubCell: UITableViewCell!
	@IBOutlet var _weblateCell: UITableViewCell!

	override func viewDidLoad() {
		super.viewDidLoad()

		tableView.estimatedRowHeight = 44.0
		tableView.rowHeight = UITableView.automaticDimension
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
	}

	func accessoryDidConnect(_ sender: Any?) {}

	func deviceModel() -> String {
		var systemInfo = utsname()
		uname(&systemInfo)
		let machineMirror = Mirror(reflecting: systemInfo.machine)
		let model = machineMirror.children.reduce("") { identifier, element in
			guard let value = element.value as? Int8, value != 0 else { return identifier }
			return identifier + String(UnicodeScalar(UInt8(value)))
		}

		// https://everymac.com/ultimate-mac-lookup
		let dict = [
			// iPhone
			"iPhone1,1": "iPhone 2G",
			"iPhone1,2": "iPhone 3G",
			"iPhone2,1": "iPhone 3GS",
			"iPhone3,1": "iPhone 4 (GSM)",
			"iPhone3,2": "iPhone 4 (GSM, Revision A)",
			"iPhone3,3": "iPhone 4 (CDMA/Verizon/Sprint)",
			"iPhone4,1": "iPhone 4S",
			"iPhone5,1": "iPhone 5 (GSM/LTE 4, 17/North America)",
			"iPhone5,2": "iPhone 5 (CDMA/LTE)",
			"iPhone5,3": "iPhone 5c (GSM)",
			"iPhone5,4": "iPhone 5c (GSM+CDMA)",
			"iPhone6,1": "iPhone 5s (GSM)",
			"iPhone6,2": "iPhone 5s (GSM+CDMA)",
			"iPhone7,1": "iPhone 6 Plus",
			"iPhone7,2": "iPhone 6",
			"iPhone8,2": "iPhone 6s Plus",
			"iPhone8,1": "iPhone 6s",
			"iPhone8,4": "iPhone SE",
			"iPhone9,1": "iPhone 7 (Verizon/Sprint/China)",
			"iPhone9,3": "iPhone 7 (Global)",
			"iPhone9,2": "iPhone 7 Plus (Verizon/Sprint/China)",
			"iPhone9,4": "iPhone 7 Plus (Global)",
			"iPhone10,1": "iPhone 8 (Verizon/Sprint/China)",
			"iPhone10,4": "iPhone 8 (Global)",
			"iPhone10,2": "iPhone 8 Plus (Verizon/Sprint/China)",
			"iPhone10,5": "iPhone 8 Plus (Global)",
			"iPhone10,3": "iPhone X (Verizon/Sprint/China)",
			"iPhone10,6": "iPhone X",
			"iPhone11,2": "iPhone XS",
			"iPhone11,6": "iPhone XS Max",
			"iPhone11,8": "iPhone XR",
			// iPod
			"iPod1,1": "iPod Touch (1 Gen)",
			"iPod2,1": "iPod Touch (2 Gen)",
			"iPod3,1": "iPod Touch (3 Gen)",
			"iPod4,1": "iPod Touch (4 Gen)",
			"iPod5,1": "iPod Touch (5 Gen)",
			"iPod7,1": "iPod Touch (6 Gen)",
			// iPad
			"iPad1,1": "iPad",
			"iPad1,2": "iPad 3G",
			"iPad2,1": "iPad 2 (WiFi)",
			"iPad2,2": "iPad 2 (GSM)",
			"iPad2,3": "iPad 2 (CDMA)",
			"iPad2,4": "iPad 2 (WiFi)",
			"iPad2,5": "iPad Mini (WiFi)",
			"iPad2,6": "iPad Mini (GSM)",
			"iPad2,7": "iPad Mini (GSM+CDMA)",
			"iPad3,1": "iPad 3 (WiFi)",
			"iPad3,2": "iPad 3 (GSM+CDMA)",
			"iPad3,3": "iPad 3 (GSM)",
			"iPad3,4": "iPad 4 (WiFi)",
			"iPad3,5": "iPad 4 (GSM)",
			"iPad3,6": "iPad 4 (GSM+CDMA)",
			"iPad4,1": "iPad Air (WiFi)",
			"iPad4,2": "iPad Air (Cellular)",
			"iPad4,4": "iPad Mini 2 (WiFi)",
			"iPad4,5": "iPad Mini 2 (Cellular)",
			"iPad4,6": "iPad Mini 2 (China)",
			"iPad4,7": "iPad Mini 3 (WiFi)",
			"iPad4,8": "iPad Mini 3 (Cellular)",
			"iPad4,9": "iPad Mini 3 (China)",
			"iPad5,1": "iPad Mini 4 (WiFi)",
			"iPad5,2": "iPad Mini 4 (LTE)",
			"iPad5,3": "iPad Air 2 (WiFi)",
			"iPad5,4": "iPad Air 2 (Cellular)",
			"iPad6,3": "iPad Pro 9.7 (WiFi)",
			"iPad6,4": "iPad Pro 9.7 (Cellular)",
			"iPad6,7": "iPad Pro 12.9 (WiFi)",
			"iPad6,8": "iPad Pro 12.9 (Cellular)",
			"iPad6,11": "iPad (5th Gen, WiFi)",
			"iPad6,12": "iPad (5th Gen, Cellular)",
			"iPad7,1": "iPad Pro 12.9 (2nd Gen, WiFi)",
			"iPad7,2": "iPad Pro 12.9 (2nd Gen, Cellular)",
			"iPad7,3": "iPad Pro 10.5 (WiFi)",
			"iPad7,4": "iPad Pro 10.5 (Cellular)",
			// other
			"AppleTV2,1": "Apple TV 2G",
			"AppleTV3,1": "Apple TV 3",
			"AppleTV3,2": "Apple TV 3 (2013)",
			"i386": "Simulator",
			"x86_64": "Simulator"
		]

		let friendlyModel = dict[model]
		return (friendlyModel ?? model)
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		let cell = tableView.cellForRow(at: indexPath)

		if cell == _sendMailCell {
			if MFMailComposeViewController.canSendMail() {
				let appDelegate = AppDelegate.shared
				let mail = MFMailComposeViewController()
				mail.mailComposeDelegate = self
				mail.setSubject("\(appDelegate.appName()) \(appDelegate.appVersion()) feedback")
				mail.setToRecipients(["bryceco@yahoo.com"])
				var body = "Device: \(deviceModel())\n"
				body += "iOS version: \(UIDevice.current.systemVersion)\n"
				if appDelegate.userName.count > 0 {
					body += "OSM ID: \(appDelegate.userName)\n\n"
				}
				mail.setMessageBody(body, isHTML: false)
				navigationController?.present(mail, animated: true)
			} else {
				let alert = UIAlertController(
					title: NSLocalizedString("Cannot compose message", comment: "e-mail message"),
					message: NSLocalizedString("Mail delivery is not available on this device", comment: ""),
					preferredStyle: .alert)
				alert
					.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel, handler: nil))
				present(alert, animated: true)
			}
		} else if cell == _githubCell {
			let url = URL(string: "https://github.com/bryceco/GoMap/issues")
			var viewController: UIViewController?
			if let url = url {
				viewController = SFSafariViewController(url: url)
			}
			if let viewController = viewController {
				present(viewController, animated: true)
			}
		} else if cell == _weblateCell {
			let url = URL(string: "https://hosted.weblate.org/projects/go-map/app/")
			var viewController: UIViewController?
			if let url = url {
				viewController = SFSafariViewController(url: url)
			}
			if let viewController = viewController {
				present(viewController, animated: true)
			}
		} else if cell == _testFlightCell {
			openTestFlightURL()
		}

		self.tableView.deselectRow(at: indexPath, animated: true)
	}

	override open func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
		let isLastSection = tableView.numberOfSections == section + 1
		if isLastSection {
			return createVersionDetailsString()
		}

		return nil
	}

	// MARK: Private methods

	private func createVersionDetailsString() -> String {
		let appDelegate = AppDelegate.shared
		let appName = appDelegate.appName()
		let appVersion = appDelegate.appVersion()
		let appBuildNumber = appDelegate.appBuildNumber()
		return "\(appName) \(appVersion) (\(appBuildNumber))"
	}

	func openTestFlightURL() {
		guard let url = URL(string: "https://testflight.apple.com/join/T96F9wYq") else { return }

		UIApplication.shared.open(url, options: [:], completionHandler: nil)
	}

	func mailComposeController(
		_ controller: MFMailComposeViewController,
		didFinishWith result: MFMailComposeResult,
		error: Error?)
	{
		dismiss(animated: true)
	}
}
