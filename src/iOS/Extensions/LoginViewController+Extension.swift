//
//  LoginViewController.swift
//  Go Map!!
//
//  Created by Wolfgang Timme on 4/15/19.
//  Copyright © 2019 Bryce. All rights reserved.
//

import UIKit

extension LoginViewController {
    @objc func saveVerifiedCredentials(username: String, password: String) {
        _=KeyChain.setString(username, forIdentifier: "username")
		_=KeyChain.setString(password, forIdentifier: "password")

        // Update the app delegate as well.
		let appDelegate = AppDelegate.shared
		appDelegate.userName = username
		appDelegate.userPassword = password
    }
}
