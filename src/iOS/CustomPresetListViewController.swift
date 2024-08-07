//
//  CustomPresetListViewController.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 8/20/14.
//  Copyright (c) 2014 Bryce Cogswell. All rights reserved.
//

import UIKit

class CustomPresetListViewController: UITableViewController {
	var customPresets: PresetKeyUserDefinedList?

	override func viewDidLoad() {
		customPresets = PresetKeyUserDefinedList.shared

		super.viewDidLoad()

		navigationItem.rightBarButtonItem = editButtonItem
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)

		if isMovingFromParent {
			customPresets?.save()
		}
	}

	// MARK: - Table view data source

	override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		NSLocalizedString("You can define your own custom presets here", comment: "POI editor presets")
	}

	override func numberOfSections(in tableView: UITableView) -> Int {
		1
	}

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		if section != 0 {
			return 0
		}
		return (customPresets?.list.count ?? 0) + 1
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		assert(indexPath.section == 0)
		if indexPath.row < (customPresets?.list.count ?? 0) {
			let cell = tableView.dequeueReusableCell(withIdentifier: "backgroundCell", for: indexPath)
			let preset = customPresets?.list[indexPath.row]
			cell.textLabel?.text = preset?.name ?? ""
			return cell
		} else {
			let cell = tableView.dequeueReusableCell(withIdentifier: "addNewCell", for: indexPath)
			return cell
		}
	}

	override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
		if indexPath.section == 0, indexPath.row < (customPresets?.list.count ?? 0) {
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
			customPresets?.removePresetAtIndex(indexPath.row)
			tableView.deleteRows(at: [indexPath], with: .automatic)
		} else if editingStyle == .insert {
			// Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
		}
	}

	override func tableView(_ tableView: UITableView, moveRowAt fromIndexPath: IndexPath, to toIndexPath: IndexPath) {
		if let preset = customPresets?.list[fromIndexPath.row] {
			customPresets?.removePresetAtIndex(fromIndexPath.row)
			customPresets?.addPreset(preset, atIndex: toIndexPath.row)
		}
	}

	override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
		if indexPath.section == 0, indexPath.row < (customPresets?.list.count ?? 0) {
			return true
		}
		return false
	}

	// MARK: - Navigation

	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		let controller = segue.destination as? UITableViewController
		let c = controller as? CustomPresetController
		let cell = sender as? UITableViewCell
		var indexPath: IndexPath?
		if let cell = cell {
			indexPath = tableView.indexPath(for: cell)
		}
		let row = indexPath?.row ?? 0
		if row < (customPresets?.list.count ?? 0) {
			// existing item is being edited
			c?.customPreset = customPresets?.list[row]
		}

		c?.completion = { preset in
			if let preset = preset {
				if row >= (self.customPresets?.list.count ?? 0) {
					self.customPresets?.addPreset(preset, atIndex: self.customPresets?.list.count ?? 0)
				} else {
					self.customPresets?.removePresetAtIndex(row)
					self.customPresets?.addPreset(preset, atIndex: row)
				}
				self.tableView.reloadData()
			}
		}
	}
}
