//  Converted to Swift 5.2 by Swiftify v5.2.23024 - https://swiftify.com/
//
//  LanguageTableViewController.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 11/12/15.
//  Copyright © 2015 Bryce Cogswell. All rights reserved.
//

import UIKit

class LanguageTableViewController: UITableViewController {
    var languages: PresetLanguages?

    override func viewDidLoad() {
        super.viewDidLoad()
        languages = PresetLanguages()

        tableView.estimatedRowHeight = 44
        tableView.rowHeight = UITableView.automaticDimension
    }

    // MARK: - Table view data source
    override func numberOfSections(in tableView: UITableView) -> Int {
        1
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == 0 {
            return NSLocalizedString("Language selection affects only Presets and only for those presets that are translated for iD. The main interface is still English.", comment: "")
        }
        return nil
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return (languages?.languageCodes().count ?? 0) + 1
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)

        var code: String? = nil

        if indexPath.row == 0 {

            // Default
            code = nil

            // name in native language
            cell.textLabel?.text = NSLocalizedString("Automatic", comment: "Automatic selection of presets languages")
            cell.detailTextLabel?.text = nil
        } else {

            code = languages?.languageCodes()[indexPath.row - 1]

            // name in native language
            cell.textLabel?.text = PresetLanguages.languageNameForCode(code ?? "") ?? ""

            // name in current language
            cell.detailTextLabel?.text = PresetLanguages.localLanguageNameForCode(code ?? "") ?? ""
        }

        // accessory checkmark
        if let isPreferredLanguageIsDefault = languages?.preferredLanguageIsDefault() {
            if isPreferredLanguageIsDefault {
                if !(indexPath.row == 0) {
                    if code == languages?.preferredLanguageCode() {
                        cell.accessoryType = .checkmark
                    } else {
                        cell.accessoryType = .none
                    }
                }
            }
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.row == 0 {
            languages?.setPreferredLanguageCode(nil)
        } else {
            
            let code = languages?.languageCodes()[indexPath.row - 1]
            languages?.setPreferredLanguageCode(code)
        }

        self.tableView.reloadData()

        PresetsDatabase.reload() // reset tags
        AppDelegate.shared.mapView.refreshPushpinText()
    }
}
