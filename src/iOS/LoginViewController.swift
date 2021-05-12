//  Converted to Swift 5.2 by Swiftify v5.2.23024 - https://swiftify.com/
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

        let _username = self._username.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let _password = self._password.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

        let appDelegate = UIApplication.shared.delegate as? AppDelegate
        appDelegate?.userName = _username
        appDelegate?.userPassword = _password

        _activityIndicator.color = UIColor.darkGray
        _activityIndicator.startAnimating()

        appDelegate?.mapView?.editorLayer.mapData.verifyUserCredentials(completion: { errorMessage in
            var errorMessage = errorMessage
            self._activityIndicator.stopAnimating()
            if errorMessage != nil {

                // warn that email addresses don't work
                if appDelegate?.userName?.contains("@") ?? false {
                    errorMessage = NSLocalizedString("You must provide your OSM user name, not an email address.", comment: "")
                }
                let alert = UIAlertController(title: NSLocalizedString("Bad login", comment: ""), message: errorMessage, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel, handler: nil))
                self.present(alert, animated: true)
            } else {
                // verifying credentials may update the appDelegate values when we subsitute name for correct case:
                self._username.text = _username
                self._password.text = _password
                self._username.resignFirstResponder()
                self._password.resignFirstResponder()

                self.saveVerifiedCredentials(username: _username ?? "", password: _password ?? "")

                let alert = UIAlertController(title: NSLocalizedString("Login successful", comment: ""), message: nil, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel, handler: { action in
                    self.navigationController?.popToRootViewController(animated: true)
                }))
                self.present(alert, animated: true)
            }
        })
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        let appDelegate = UIApplication.shared.delegate as? AppDelegate
        _username.text = appDelegate?.userName
        _password.text = appDelegate?.userPassword

        _saveButton.isEnabled = (_username.text?.count ?? 0) != 0 && (_password.text?.count ?? 0) != 0
    }
}
