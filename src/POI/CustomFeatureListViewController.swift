//
//  CustomFeatureListViewController.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 3/10/25.
//  Copyright © 2025 Bryce Cogswell. All rights reserved.
//

import UIKit

class CustomFeatureList: Codable {
	private(set) var list: [CustomFeature]

	init() {
		list = []
	}

	func addFeature(_ feature: CustomFeature, atIndex: Int) {
		list.insert(feature, at: atIndex)
	}

	func removeFeatureAtIndex(_ row: Int) {
		list.remove(at: row)
	}

	func save() {
		guard let data = try? JSONEncoder().encode(self)
		else {
			return
		}
		UserPrefs.shared.userDefinedFeatures.value = data
	}

	class func restore() -> CustomFeatureList? {
		guard
			let data = UserPrefs.shared.userDefinedFeatures.value
		else {
			return nil
		}
		return try? JSONDecoder().decode(Self.self, from: data)
	}
}

class CustomFeatureListViewController: UITableViewController {
	var customFeatures: CustomFeatureList!

	override func viewDidLoad() {
		super.viewDidLoad()

		navigationItem.rightBarButtonItem = editButtonItem

		customFeatures = CustomFeatureList.restore() ?? CustomFeatureList()
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)

		if isMovingFromParent {
			customFeatures.save()
			PresetsDatabase.shared.insertCustomFeatures(customFeatures.list)
		}
	}

	// MARK: - Table view data source

	override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		NSLocalizedString(
			"Define your own custom features with unique tag combinations to quickly add special types of objects. These can be searched for in Common Tags.",
			comment: "POI editor presets")
	}

	override func numberOfSections(in tableView: UITableView) -> Int {
		1
	}

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		if section != 0 {
			return 0
		}
		return customFeatures.list.count + 1
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		assert(indexPath.section == 0)
		if indexPath.row < customFeatures.list.count {
			let cell = tableView.dequeueReusableCell(withIdentifier: "backgroundCell", for: indexPath)
			let preset = customFeatures.list[indexPath.row]
			cell.textLabel?.text = preset.localizedName
			return cell
		} else {
			let cell = tableView.dequeueReusableCell(withIdentifier: "addNewCell", for: indexPath)
			return cell
		}
	}

	override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
		if indexPath.section == 0, indexPath.row < customFeatures.list.count {
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
			customFeatures.removeFeatureAtIndex(indexPath.row)
			tableView.deleteRows(at: [indexPath], with: .automatic)
		} else if editingStyle == .insert {
			// Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
		}
	}

	override func tableView(_ tableView: UITableView, moveRowAt fromIndexPath: IndexPath, to toIndexPath: IndexPath) {
		let feature = customFeatures.list[fromIndexPath.row]
		customFeatures.removeFeatureAtIndex(fromIndexPath.row)
		customFeatures.addFeature(feature, atIndex: toIndexPath.row)
	}

	override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
		if indexPath.section == 0, indexPath.row < customFeatures.list.count {
			return true
		}
		return false
	}

	// MARK: - Navigation

	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		guard
			let controller = segue.destination as? UITableViewController,
			let controller = controller as? CustomFeatureController,
			let cell = sender as? UITableViewCell,
			let row = tableView.indexPath(for: cell)?.row
		else {
			return
		}

		if row < customFeatures.list.count {
			// existing item is being edited
			controller.customFeature = customFeatures.list[row]
		}

		controller.completion = { preset in
			if row >= self.customFeatures.list.count {
				self.customFeatures.addFeature(preset, atIndex: self.customFeatures.list.count)
			} else {
				self.customFeatures.removeFeatureAtIndex(row)
				self.customFeatures.addFeature(preset, atIndex: row)
			}
			self.tableView.reloadData()
		}
	}
}
