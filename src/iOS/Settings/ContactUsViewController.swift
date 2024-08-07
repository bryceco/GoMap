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
	@IBOutlet var sendMailCell: UITableViewCell!
	@IBOutlet var testFlightCell: UITableViewCell!
	@IBOutlet var githubCell: UITableViewCell!
	@IBOutlet var weblateCell: UITableViewCell!
	@IBOutlet var slackCell: UITableViewCell!

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
		return model
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		let cell = tableView.cellForRow(at: indexPath)

		switch cell {
		case sendMailCell:
			if MFMailComposeViewController.canSendMail() {
				let appDelegate = AppDelegate.shared
				let mail = MFMailComposeViewController()
				mail.mailComposeDelegate = self
				mail.setSubject("\(appDelegate.appName()) \(appDelegate.appVersion()) feedback")
				mail.setToRecipients(["bryceco@yahoo.com"])
				var body = "Device: \(deviceModel())\n"
				body += "iOS version: \(UIDevice.current.systemVersion)\n"
				if let name = appDelegate.userName {
					body += "OSM ID: \(name)\n\n"
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

		case githubCell:
			let url = URL(string: "https://github.com/bryceco/GoMap/issues")
			var viewController: UIViewController?
			if let url = url {
				viewController = SFSafariViewController(url: url)
			}
			if let viewController = viewController {
				present(viewController, animated: true)
			}

		case slackCell:
			let slackApp = URL(string: "slack://channel?id=CU6GTRQ79&team=T029HV94T&tab=home")!
			if UIApplication.shared.canOpenURL(slackApp) {
				UIApplication.shared.open(slackApp, options: [:], completionHandler: nil)
			} else {
				let url = URL(string: "https://osmus.slack.com/app_redirect?channel=CU6GTRQ79")!
				UIApplication.shared.open(url, options: [:], completionHandler: nil)
			}

		case weblateCell:
			let url = URL(string: "https://hosted.weblate.org/projects/go-map/app/")
			var viewController: UIViewController?
			if let url = url {
				viewController = SFSafariViewController(url: url)
			}
			if let viewController = viewController {
				present(viewController, animated: true)
			}

		case testFlightCell:
			openTestFlightURL()

		default:
			break
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
