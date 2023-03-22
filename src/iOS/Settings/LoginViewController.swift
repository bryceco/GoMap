//
//  LoginViewController.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/19/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

import UIKit

class LoginViewController: UITableViewController {
	@IBOutlet var saveButton: UIBarButtonItem!
	@IBOutlet var activityIndicator: UIActivityIndicatorView!

	override func viewDidLoad() {
		super.viewDidLoad()
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
		if activityIndicator.isAnimating {
			return
		}

		activityIndicator.color = UIColor.darkGray
		activityIndicator.startAnimating()

		AppDelegate.shared.oAuth2.getUserDetails(callback: { dict in
			self.activityIndicator.stopAnimating()

			if let dict = dict {
				if let name = dict["display_name"] as? String {
					AppDelegate.shared.userName = name
				}
				let alert = UIAlertController(
					title: NSLocalizedString("Login successful", comment: ""),
					message: nil,
					preferredStyle: .alert)
				alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""),
				                              style: .cancel,
				                              handler: { _ in
				                              	self.navigationController?.popToRootViewController(animated: true)
				                              }))
				self.present(alert, animated: true)
			} else {
				let alert = UIAlertController(
					title: NSLocalizedString("Bad login", comment: ""),
					message: NSLocalizedString("Not found", comment: "User credentials not found"),
					preferredStyle: .alert)
				alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""),
				                              style: .cancel,
				                              handler: nil))
				self.present(alert, animated: true)
			}
		})
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)

		saveButton.isEnabled = AppDelegate.shared.oAuth2.isAuthorized()
	}

	@IBAction func loginWithOAuth(_ sender: Any?) {
		AppDelegate.shared.oAuth2.requestAccessFromUser(withVC: self, onComplete: { result in
			switch result {
			case .success:
				let alert = UIAlertController(
					title: NSLocalizedString("Login successful", comment: ""),
					message: nil,
					preferredStyle: .alert)
				alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""),
				                              style: .cancel,
				                              handler: { _ in
				                              	self.navigationController?.popToRootViewController(animated: true)
				                              }))
				self.present(alert, animated: true)
			case let .failure(error):
				let alert = UIAlertController(
					title: NSLocalizedString("Bad login", comment: ""),
					message: error.localizedDescription,
					preferredStyle: .alert)
				alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""),
				                              style: .cancel,
				                              handler: nil))
				self.present(alert, animated: true)
			}
		})
	}
}
