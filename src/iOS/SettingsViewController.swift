//  Converted to Swift 5.4 by Swiftify v5.4.27034 - https://swiftify.com/
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
    @IBOutlet var _username: UILabel!
    @IBOutlet var _language: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.estimatedRowHeight = 44.0
        tableView.rowHeight = UITableView.automaticDimension
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        navigationController?.isNavigationBarHidden = false

        let presetLanguages = PresetLanguages()
        let preferredLanguageCode = presetLanguages.preferredLanguageCode
        let preferredLanguage = PresetLanguages.localLanguageNameForCode(preferredLanguageCode())
        _language.text = preferredLanguage

        // set username, but then validate it
        let appDelegate = AppDelegate.shared

        _username.text = ""
        if (appDelegate.userName?.count ?? 0) > 0 {
            appDelegate.mapView.editorLayer.mapData.verifyUserCredentials(completion: { [self] errorMessage in
                if errorMessage != nil {
                    _username.text = NSLocalizedString("<unknown>", comment: "unknown user name")
                } else {
                    _username.text = appDelegate.userName
                }

                tableView.reloadData()
            })
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
    }

    func accessoryDidConnect(_ sender: Any?) {
    }

    @IBAction func onDone(_ sender: Any) {
        dismiss(animated: true)
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        self.tableView.deselectRow(at: indexPath, animated: true)
    }
}
