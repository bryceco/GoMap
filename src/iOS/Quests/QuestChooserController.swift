//
//  QuestChooserController.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 2/5/23.
//  Copyright © 2023 Bryce Cogswell. All rights reserved.
//

import SwiftUI
import UIKit

class QuestChooserTableCell: UITableViewCell {
	@IBOutlet var title: UILabel?
	@IBOutlet var uiSwitch: UISwitch?
	var quest: QuestProtocol?

	@IBAction func didSwitch(_ sender: Any) {
		guard let quest = quest else { return }
		let enabled = (sender as! UISwitch).isOn

		// update quest list database
		QuestList.shared.setEnabled(quest, enabled)

		// also update markers database
		if !enabled {
			AppDelegate.shared.mapView.mapMarkerDatabase.removeMarkers(where: {
				($0 as? QuestMarker)?.quest.ident == quest.ident
			})
		}
	}
}

class BuildYourOwnQuestTableCell: UITableViewCell {
	@IBOutlet var label: UILabel?
}

class QuestChooserController: UITableViewController {
	override func viewDidLoad() {
		super.viewDidLoad()
		navigationItem.rightBarButtonItem?.isEnabled = false
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		// Need to reload here in case the user created a new quest type
		tableView.reloadData()
	}

	override func viewWillDisappear(_ animated: Bool) {
		// Update markers for newly added quests
		AppDelegate.shared.mapView.updateMapMarkersFromServer(withDelay: 0.0, including: .quest)
	}

	// MARK: Table view delegate

	override func numberOfSections(in tableView: UITableView) -> Int {
		return 1
	}

	override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		return nil
	}

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		if #available(iOS 15.0.0, *) {
			return QuestList.shared.list.count + 2 + 1	// 2 builders + import/export
		} else {
			return QuestList.shared.list.count + 1	// import/export
		}
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		if indexPath.row < QuestList.shared.list.count {
			let cell = tableView.dequeueReusableCell(withIdentifier: "QuestChooserTableCell", for: indexPath)
			as! QuestChooserTableCell
			let quest = QuestList.shared.list[indexPath.row]
			cell.quest = quest
			cell.title?.text = quest.title
			cell.uiSwitch?.isOn = QuestList.shared.isEnabled(quest)
			if #available(iOS 15, *) {
				cell.accessoryType = QuestList.shared.isUserQuest(quest) ? .disclosureIndicator : .none
			} else {
				cell.accessoryType = .none
			}
			return cell
		} else if indexPath.row == self.tableView(tableView, numberOfRowsInSection: 0)-1 {
			let cell = tableView.dequeueReusableCell(withIdentifier: "ImportExportCell", for: indexPath)
			return cell
		} else if #available(iOS 15.0, *) {
			let cell = tableView.dequeueReusableCell(
				withIdentifier: "BuildYourOwnQuestTableCell",
				for: indexPath) as! BuildYourOwnQuestTableCell
			cell.accessoryType = .disclosureIndicator
			if indexPath.row == QuestList.shared.list.count {
				cell.label?.text = NSLocalizedString("Build a New Quest", comment: "")
			} else {
				cell.label?.text = NSLocalizedString("Advanced Quest Builder", comment: "")
			}
			return cell
		} else {
			fatalError()
		}
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		guard let cell = tableView.cellForRow(at: indexPath),
		      cell.accessoryType == .disclosureIndicator
		else { return }

		if #available(iOS 15, *) {
			// transition to quest builder for item
			if let cell = cell as? QuestChooserTableCell,
			   let title = cell.title?.text,
			   let quest = QuestList.shared.userQuests.list.first(where: { $0.title == title })
			{
				// existing quest
				if let quest = quest as? QuestDefinitionWithFeatures {
					openSimpleQuestBuilder(quest: quest)
					return
				}
				if let quest = quest as? QuestDefinitionWithFilters {
					openAdvancedQuestBuilder(quest: quest)
					return
				}
			}
			// build a new quest
			if indexPath.row == QuestList.shared.list.count {
				openSimpleQuestBuilder(quest: nil)
			} else {
				openAdvancedQuestBuilder(quest: nil)
			}
		} else {
			QuestBuilderController.presentVersionAlert(self)
		}
	}

	override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
		guard
			indexPath.row != QuestList.shared.list.count,
			let cell = tableView.cellForRow(at: indexPath)
		else { return false }
		// Only user-defined cells have an accessoryType
		return cell.accessoryType == .disclosureIndicator
	}

	override func tableView(_ tableView: UITableView,
	                        commit editingStyle: UITableViewCell.EditingStyle,
	                        forRowAt indexPath: IndexPath)
	{
		if editingStyle == .delete {
			// Get the quest being deleted
			let quest = QuestList.shared.list[indexPath.row]

			// Delete the row from the data source
			QuestList.shared.remove(at: indexPath.row)
			tableView.deleteRows(at: [indexPath], with: .fade)

			// Remove associated markers
			AppDelegate.shared.mapView.mapMarkerDatabase.removeMarkers(where: {
				($0 as? QuestMarker)?.quest.ident == quest.ident
			})
		}
	}

	// MARK: Open quest builders

	@available(iOS 15, *)
	func openSimpleQuestBuilder(quest: QuestDefinitionWithFeatures?) {
		let vc = QuestBuilderController.instantiateWith(quest: quest)
		navigationController?.pushViewController(vc, animated: true)
	}

	@available(iOS 15.0.0, *)
	func openAdvancedQuestBuilder(quest: QuestDefinitionWithFilters?) {
		let quest = quest ??
			QuestDefinitionWithFilters(title: "Add Cuisine",
			                           label: "🍽️",
			                           tagKey: "cuisine",
			                           filters: [
			                           	QuestDefinitionFilter(
			                           		tagKey: "amenity",
			                           		tagValue: "restaurant",
			                           		relation: .equal,
			                           		included: .include),
			                           	QuestDefinitionFilter(
			                           		tagKey: "cuisine",
			                           		tagValue: "",
			                           		relation: .equal,
			                           		included: .include)
			                           ])
		var view = AdvancedQuestBuilder(quest: quest)
		view.onSave = { [weak self] newQuest in
			do {
				try QuestList.shared.addUserQuest(newQuest, replacing: quest)
				self?.tableView.reloadData()
				return true
			} catch {
				print("\(error)")
				let alertView = UIAlertController(title: NSLocalizedString("Quest Definition Error", comment: ""),
				                                  message: error.localizedDescription,
				                                  preferredStyle: .actionSheet)
				alertView.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""),
				                                  style: .cancel))
				self?.present(alertView, animated: true)
				return false
			}
		}
		let vc = UIHostingController(rootView: view)
		navigationController?.pushViewController(vc, animated: true)
	}

	// MARK: Import/Export

	func doImport(fromText text: String) {
		do {
			try QuestList.shared.importQuests(fromText: text)

			let alert = UIAlertController(
				title: NSLocalizedString("Success", comment: ""),
				message: NSLocalizedString("Quests were imported successfully.",
										   comment: ""),
				preferredStyle: .alert)
			alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""),
										  style: .default, handler: nil))
			present(alert, animated: true)
		} catch {
			let format = NSLocalizedString("An error occured while importing: %@",
										   comment: "Show an error message")
			let message = String(format: format, error.localizedDescription)
			let alert = UIAlertController(
				title: NSLocalizedString("Import Error", comment: ""),
				message: message,
				preferredStyle: .alert)
			alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""),
										  style: .default, handler: nil))
			present(alert, animated: true)
		}
	}

	@IBAction func importQuests(_ sender: Any?) {
		let alert = UIAlertController(
			title: NSLocalizedString("Import Quests", comment: ""),
			message: NSLocalizedString("Paste the JSON for your quests into the field below", comment: ""),
			preferredStyle: .alert)
		alert.addTextField(configurationHandler: { _ in })
		alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""),
									  style: .default, handler: nil))
		alert.addAction(UIAlertAction(title: NSLocalizedString("Import", comment: ""),
									  style: .default, handler: { [weak self] _ in
										self?.doImport(fromText: alert.textFields?.first?.text ?? "")
									  }))
		present(alert, animated: true)
	}

	@IBAction func exportQuests(_ sender: Any?) {
		do {
			let text = try QuestList.shared.exportQuests()
			UIPasteboard.general.string = text
			let alert = UIAlertController(
				title: NSLocalizedString("Copied", comment: "text was copied to the system clipboard"),
				message: NSLocalizedString(
					"A copy of all user-defined quests has been copied to the clipboard in JSON format. You can paste it somewhere to keep a copy or send it to someone else.",
					comment: ""),
				preferredStyle: .alert)
			alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""),
										  style: .default, handler: nil))
			present(alert, animated: true)
		} catch {
			let format = NSLocalizedString("An error occured while exporting: %@",
										   comment: "Show an error message")
			let message = String(format: format, error.localizedDescription)
			let alert = UIAlertController(
				title: NSLocalizedString("Error", comment: ""),
				message: message,
				preferredStyle: .alert)
			alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""),
										  style: .default, handler: nil))
			present(alert, animated: true)
		}
	}}
