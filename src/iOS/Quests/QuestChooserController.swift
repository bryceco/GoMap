//
//  QuestChooserController.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 2/5/23.
//  Copyright © 2023 Bryce Cogswell. All rights reserved.
//

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

	var vc: UIViewController?
	@IBAction func didPress(_ sender: Any) {
		if #available(iOS 15, *) {
			let vc2 = QuestBuilderController.instantiateNew()
			vc?.present(vc2, animated: true)
		} else {
			QuestBuilderController.presentVersionAlert(vc!)
		}
	}

	override func numberOfSections(in tableView: UITableView) -> Int {
		return 1
	}

	override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		return nil
	}

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		if #available(iOS 15.0, *) {
			return QuestList.shared.list.count + 1
		} else {
			return QuestList.shared.list.count
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
		} else if #available(iOS 15.0, *) {
			let cell = tableView.dequeueReusableCell(withIdentifier: "BuildYourOwnQuestTableCell", for: indexPath)
			return cell
		} else {
			fatalError()
		}
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		guard let cell = tableView.cellForRow(at: indexPath),
		      cell.accessoryType == .disclosureIndicator
		else { return }

		// transition to quest builder for item
		if let cell = cell as? QuestChooserTableCell,
		   let title = cell.title?.text,
		   let quest = QuestList.shared.userQuests.first(where: { $0.title == title })
		{
			if #available(iOS 15, *) {
				let vc = QuestBuilderController.instantiateWith(quest: quest)
				navigationController?.pushViewController(vc, animated: true)
			} else {
				QuestBuilderController.presentVersionAlert(self)
			}
		}
	}

	override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
		guard let cell = tableView.cellForRow(at: indexPath)
		else { return false }
		// Only user-defined cells have an accessoryType
		return cell.accessoryType == .disclosureIndicator
	}

	override func tableView(_ tableView: UITableView,
	                        commit editingStyle: UITableViewCell.EditingStyle,
	                        forRowAt indexPath: IndexPath)
	{
		if editingStyle == .delete {
			// Delete the row from the data source
			QuestList.shared.remove(at: indexPath.row)
			tableView.deleteRows(at: [indexPath], with: .fade)
		}
	}
}
