//
//  CustomFeatureListViewController.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 3/10/25.
//  Copyright © 2025 Bryce Cogswell. All rights reserved.
//

import UIKit

class CustomFeatureListViewController: UITableViewController {
	var customFeatures: PresetKeyUserDefinedList?

	override func viewDidLoad() {
		customFeatures = PresetKeyUserDefinedList.shared

		super.viewDidLoad()

		navigationItem.rightBarButtonItem = editButtonItem
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)

		if isMovingFromParent {
			customFeatures?.save()
		}
	}

	// MARK: - Table view data source

	override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		NSLocalizedString(
			"You can define custom fields for presets. A field is a single key/value pair associated with a feature.",
			comment: "POI editor presets")
	}

	override func numberOfSections(in tableView: UITableView) -> Int {
		1
	}

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		if section != 0 {
			return 0
		}
		return (customFeatures?.list.count ?? 0) + 1
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		assert(indexPath.section == 0)
		if indexPath.row < (customFeatures?.list.count ?? 0) {
			let cell = tableView.dequeueReusableCell(withIdentifier: "backgroundCell", for: indexPath)
			let preset = customFeatures?.list[indexPath.row]
			cell.textLabel?.text = preset?.name ?? ""
			return cell
		} else {
			let cell = tableView.dequeueReusableCell(withIdentifier: "addNewCell", for: indexPath)
			return cell
		}
	}

	override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
		if indexPath.section == 0, indexPath.row < (customFeatures?.list.count ?? 0) {
			return true
		}
		return false
	}

	override func tableView(
		_ tableView: UITableView,
		commit editingStyle: UITableViewCell.EditingStyle,
		forRowAt indexPath: IndexPath)
	{
		if editingStyle == .delete {
			// Delete the row from the data source
			customFeatures?.removePresetAtIndex(indexPath.row)
			tableView.deleteRows(at: [indexPath], with: .automatic)
		} else if editingStyle == .insert {
			// Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
		}
	}

	override func tableView(_ tableView: UITableView, moveRowAt fromIndexPath: IndexPath, to toIndexPath: IndexPath) {
		if let preset = customFeatures?.list[fromIndexPath.row] {
			customFeatures?.removePresetAtIndex(fromIndexPath.row)
			customFeatures?.addPreset(preset, atIndex: toIndexPath.row)
		}
	}

	override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
		if indexPath.section == 0, indexPath.row < (customFeatures?.list.count ?? 0) {
			return true
		}
		return false
	}

	// MARK: - Navigation

	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		let controller = segue.destination as? UITableViewController
		let c = controller as? CustomFieldController
		let cell = sender as? UITableViewCell
		var indexPath: IndexPath?
		if let cell = cell {
			indexPath = tableView.indexPath(for: cell)
		}
		let row = indexPath?.row ?? 0
		if row < (customFeatures?.list.count ?? 0) {
			// existing item is being edited
			c?.customField = customFeatures?.list[row]
		}

		c?.completion = { preset in
			if let preset = preset {
				if row >= (self.customFeatures?.list.count ?? 0) {
					self.customFeatures?.addPreset(preset, atIndex: self.customFeatures?.list.count ?? 0)
				} else {
					self.customFeatures?.removePresetAtIndex(row)
					self.customFeatures?.addPreset(preset, atIndex: row)
				}
				self.tableView.reloadData()
			}
		}
	}
}
