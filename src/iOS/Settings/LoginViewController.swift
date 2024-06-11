//
//  LoginViewController.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/19/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

import UIKit

final class LoginViewController: UITableViewController {
	@IBOutlet var activityIndicator: UIActivityIndicatorView!

	@IBAction func registerAccount(_ sender: Any) {
		if let url = URL(string: "\(OSM_SERVER.queryURL)user/new") {
			UIApplication.shared.open(
				url,
				options: [:],
				completionHandler: nil)
		}
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
