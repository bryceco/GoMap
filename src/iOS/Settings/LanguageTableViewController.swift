//
//  LanguageTableViewController.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 11/12/15.
//  Copyright © 2015 Bryce Cogswell. All rights reserved.
//

import UIKit

class LanguageTableViewController: UITableViewController {
	override func viewDidLoad() {
		super.viewDidLoad()

		tableView.estimatedRowHeight = 44
		tableView.rowHeight = UITableView.automaticDimension
	}

	// MARK: - Table view data source

	override func numberOfSections(in tableView: UITableView) -> Int {
		return 1
	}

	override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		if section == 0 {
			let line = NSLocalizedString(
				"Select the language used for Presets. Other app content will use your default language.",
				comment: "")
			return line
		}
		return nil
	}

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return PresetLanguages.languageCodeList.count + 1
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)

		var code: String?

		if indexPath.row == 0 {
			// Default
			code = nil

			// name in native language
			cell.textLabel?.text = NSLocalizedString("Automatic", comment: "Automatic selection of presets languages")
			cell.detailTextLabel?.text = nil
		} else {
			code = PresetLanguages.languageCodeList[indexPath.row - 1]

			// name in native language
			cell.textLabel?.text = PresetLanguages.languageNameForCode(code ?? "") ?? ""

			// name in current language
			cell.detailTextLabel?.text = PresetLanguages.localLanguageNameForCode(code ?? "") ?? ""
		}

		// accessory checkmark
		if (PresetLanguages.preferredLanguageIsDefault() && indexPath.row == 0)
			|| code == PresetLanguages.preferredPresetLanguageCode()
		{
			cell.accessoryType = .checkmark
		} else {
			cell.accessoryType = .none
		}
		return cell
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		if indexPath.row == 0 {
			PresetLanguages.setPreferredLanguageCode(nil)
		} else {
			let code = PresetLanguages.languageCodeList[indexPath.row - 1]
			PresetLanguages.setPreferredLanguageCode(code)
		}

		self.tableView.reloadData()

		try? PresetsDatabase.reload(withLanguageCode: PresetLanguages.preferredPresetLanguageCode()) // reset tags
		AppDelegate.shared.mapView.refreshPushpinText()
	}
}
