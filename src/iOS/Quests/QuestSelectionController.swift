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

class BuildYourOwnQuestTableCell: UITableViewCell {
	var vc: UIViewController?
	@IBAction func didPress(_ sender: Any) {
		let vc2 = QuestBuilder.instantiate()
		vc?.present(vc2, animated: true)
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
		if #available(iOS 15.0, *) {
			return QuestList.shared.list.count + 1
		} else {
			return QuestList.shared.list.count
		}
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		if indexPath.row < QuestList.shared.list.count {
			let cell = tableView.dequeueReusableCell(withIdentifier: "QuestSelectionTableCell", for: indexPath)
				as! QuestSelectionTableCell
			let quest = QuestList.shared.list[indexPath.row]
			cell.quest = quest
			cell.title?.text = quest.title
			cell.uiSwitch?.isOn = QuestList.shared.isEnabled(quest)
			return cell
		} else if #available(iOS 15.0, *) {
			let cell = tableView.dequeueReusableCell(withIdentifier: "BuildYourOwnQuestTableCell", for: indexPath)
			let cell2 = cell as! BuildYourOwnQuestTableCell
			cell2.vc = self
			return cell2
		} else {
			fatalError()
		}
	}
}
