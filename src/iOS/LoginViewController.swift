//
//  LoginViewController.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/19/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

import UIKit

class LoginViewController: UITableViewController {
	@IBOutlet var _saveButton: UIBarButtonItem!
	@IBOutlet var _username: UITextField!
	@IBOutlet var _password: UITextField!
	@IBOutlet var _activityIndicator: UIActivityIndicatorView!

	override func viewDidLoad() {
		super.viewDidLoad()
	}

	@IBAction func textFieldReturn(_ sender: UITextField) {
		sender.resignFirstResponder()
	}

	@IBAction func textFieldDidChange(_ sender: Any) {
		_saveButton.isEnabled = (_username.text?.count ?? 0) != 0 && (_password.text?.count ?? 0) != 0
	}

	@IBAction func registerAccount(_ sender: Any) {
		if let url = URL(string: "https://www.openstreetmap.org/user/new") {
			UIApplication.shared.open(
				url,
				options: [:],
				completionHandler: nil)
		}
	}

	@IBAction func verifyAccount(_ sender: Any) {
		if _activityIndicator.isAnimating {
			return
		}

		let appDelegate = AppDelegate.shared

		let username = _username.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
		let password = _password.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
		appDelegate.userName = username
		appDelegate.userPassword = password

		_activityIndicator.color = UIColor.darkGray
		_activityIndicator.startAnimating()

		appDelegate.mapView.editorLayer.mapData.verifyUserCredentials(withCompletion: { errorMessage in
			var errorMessage = errorMessage
			self._activityIndicator.stopAnimating()
			if errorMessage != nil {
				// warn that email addresses don't work
				if appDelegate.userName.contains("@") {
					errorMessage = NSLocalizedString("You must provide your OSM user name, not an email address.", comment: "")
				}
				let alert = UIAlertController(title: NSLocalizedString("Bad login", comment: ""), message: errorMessage, preferredStyle: .alert)
				alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel, handler: nil))
				self.present(alert, animated: true)
			} else {
				// verifying credentials may update the appDelegate values when we subsitute name for correct case:
				self._username.text = username
				self._password.text = password
				self._username.resignFirstResponder()
				self._password.resignFirstResponder()

				self.saveVerifiedCredentials(username: username, password: password)

				let alert = UIAlertController(title: NSLocalizedString("Login successful", comment: ""), message: nil, preferredStyle: .alert)
				alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel, handler: { _ in
					self.navigationController?.popToRootViewController(animated: true)
				}))
				self.present(alert, animated: true)
			}
		})
	}

	func saveVerifiedCredentials(username: String, password: String) {
		_ = KeyChain.setString(username, forIdentifier: "username")
		_ = KeyChain.setString(password, forIdentifier: "password")

		// Update the app delegate as well.
		let appDelegate = AppDelegate.shared
		appDelegate.userName = username
		appDelegate.userPassword = password
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)

		let appDelegate = AppDelegate.shared
		_username.text = appDelegate.userName
		_password.text = appDelegate.userPassword

		_saveButton.isEnabled = (_username.text?.count ?? 0) != 0 && (_password.text?.count ?? 0) != 0
	}
}
