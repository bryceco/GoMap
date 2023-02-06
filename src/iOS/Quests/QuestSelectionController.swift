//
//  QuestSelectionController.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 2/5/23.
//  Copyright © 2023 Bryce. All rights reserved.
//

import UIKit

class QuestSelectionTableCell: UITableViewCell {
	@IBOutlet var title: UILabel?
	@IBOutlet var uiSwitch: UISwitch?
	var quest: QuestProtocol?

	@IBAction func didSwitch(_ sender: Any) {
		guard let quest = quest else { return }
		QuestList.shared.setEnabled(quest, (sender as! UISwitch).isOn)
	}
}

class QuestSelectionController: UITableViewController {
	override func viewDidLoad() {
		super.viewDidLoad()
		navigationItem.rightBarButtonItem?.isEnabled = false
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
	}

	@IBAction func Cancel(with sender: Any) {
		dismiss(animated: true, completion: nil)
		if let mapView = AppDelegate.shared.mapView {
			mapView.editorLayer.selectedNode = nil
			mapView.editorLayer.selectedWay = nil
			mapView.editorLayer.selectedRelation = nil
			mapView.placePushpinForSelection()
		}
	}

	@IBAction func Accept(with sender: Any) {
		dismiss(animated: true, completion: nil)
	}

	override func numberOfSections(in tableView: UITableView) -> Int {
		return 1
	}

	override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		return nil
	}

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return QuestList.shared.list.count
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: "QuestSelectionTableCell", for: indexPath)
			as! QuestSelectionTableCell
		let quest = QuestList.shared.list[indexPath.row]
		cell.quest = quest
		cell.title?.text = quest.title
		cell.uiSwitch?.isOn = QuestList.shared.isEnabled(quest)
		return cell
	}
}
