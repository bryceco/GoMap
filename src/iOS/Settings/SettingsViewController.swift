//
//  SettingsViewController.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/6/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

import MessageUI
import UIKit

class SettingsViewController: UITableViewController, MFMailComposeViewControllerDelegate {
	private enum SegueIdentifier {
		static let login = "LoginSegue"
		static let accountInfo = "AccountInfoSegue"
	}

	@IBOutlet var username: UILabel!
	@IBOutlet var language: UILabel!
	@IBOutlet var openStreetMapAccountCell: UITableViewCell!

	override func viewDidLoad() {
		super.viewDidLoad()

		tableView.estimatedRowHeight = 44.0
		tableView.rowHeight = UITableView.automaticDimension
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)

		navigationController?.isNavigationBarHidden = false

		let preferredLanguageCode = PresetLanguages.preferredPresetLanguageCode
		let preferredLanguage = PresetLanguages.localLanguageNameForCode(preferredLanguageCode())
		language.text = preferredLanguage

		// set username, but then validate it
		let appDelegate = AppDelegate.shared

		username.text = ""
		if let userName = appDelegate.userName {
			username.text = userName
		} else {
			OSM_SERVER.oAuth2?.getUserDetails(callback: { dict in
				if let dict = dict,
				   let name = dict["display_name"] as? String
				{
					self.username.text = name
					appDelegate.userName = name
				} else {
					self.username.text = NSLocalizedString("<unknown>", comment: "unknown user name")
				}

				self.tableView.reloadData()
			})
		}
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
	}

	func accessoryDidConnect(_ sender: Any?) {}

	@IBAction func onDone(_ sender: Any) {
		dismiss(animated: true)
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		self.tableView.deselectRow(at: indexPath, animated: true)

		if let cell = tableView.cellForRow(at: indexPath), cell == openStreetMapAccountCell {
			if OSM_SERVER.oAuth2?.isAuthorized() ?? false {
				performSegue(withIdentifier: SegueIdentifier.accountInfo, sender: self)
			} else {
				performSegue(withIdentifier: SegueIdentifier.login, sender: self)
			}
		}
	}
}
