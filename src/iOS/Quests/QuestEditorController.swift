//
//  QuestEditorController.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 2/5/23.
//  Copyright © 2023 Bryce. All rights reserved.
//

import UIKit

class QuestTextEntryCell: UITableViewCell {
	@IBOutlet var textField: UITextField?
}

class QuestEditorController: UITableViewController {
	var quest: QuestProtocol!
	var object: OsmBaseObject!
	var presetFeature: PresetFeature?
	var presetKey: PresetKey?
	var onClose: (() -> Void)?

	class func presetsForGroup(_ group: PresetKeyOrGroup) -> [PresetKey] {
		var list: [PresetKey] = []
		switch group {
		case let .group(subgroup):
			for g in subgroup.presetKeys {
				list += Self.presetsForGroup(g)
			}
		case let .key(key):
			list.append(key)
		}
		return list
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		navigationItem.rightBarButtonItem?.isEnabled = false
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		if presetKey?.presetList?.count == nil {
			// set text cell to first responder
			if let cell = tableView.cellForRow(at: IndexPath(row: 1, section: 0)),
			   let cell2 = cell as? QuestTextEntryCell
			{
				cell2.textField?.becomeFirstResponder()
			}
		}
	}

	func refreshPresetKey() {
		let presets = PresetsForFeature(
			withFeature: presetFeature,
			objectTags: object.tags,
			geometry: object.geometry(),
			update: {
				self.refreshPresetKey()
				self.tableView.reloadData()
			})
		top_loop:
			for section in presets.sectionList {
			for g in section.presetKeys {
				let list = Self.presetsForGroup(g)
				for preset in list {
					if preset.tagKey == quest.tagKey {
						presetKey = preset
						break top_loop
					}
				}
			}
		}
	}

	public class func instantiate(quest: QuestProtocol, object: OsmBaseObject,
	                              onClose: @escaping () -> Void) -> UINavigationController
	{
		let sb = UIStoryboard(name: "QuestEditor", bundle: nil)
		let vc2 = sb.instantiateViewController(withIdentifier: "QuestEditor") as! UINavigationController
		let vc = vc2.viewControllers.first as! QuestEditorController

		vc.object = object
		vc.quest = quest
		vc.title = quest.title
		vc.onClose = onClose
		vc.presetFeature = PresetsDatabase.shared.presetFeatureMatching(
			tags: object.tags,
			geometry: object.geometry(),
			location: AppDelegate.shared.mapView.currentRegion,
			includeNSI: false)
		vc.refreshPresetKey()
		return vc2
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
		let editor = AppDelegate.shared.mapView.editorLayer
		if var tags = editor.selectedPrimary?.tags,
		   let index = tableView.indexPathForSelectedRow
		{
			let row = index.row
			tags[quest.tagKey] = presetKey?.presetList?[row].tagValue ?? ""
			editor.setTagsForCurrentObject(tags)
		}
		dismiss(animated: true, completion: nil)
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		if indexPath.row == self.tableView(tableView, numberOfRowsInSection: 0) - 1 {
			dismiss(animated: false, completion: nil)
			AppDelegate.shared.mapView?.presentTagEditor(nil)
		}
		navigationItem.rightBarButtonItem?.isEnabled = true
	}

	override func numberOfSections(in tableView: UITableView) -> Int {
		return 1
	}

	override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		return nil
	}

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		if let answerCount = presetKey?.presetList?.count {
			// title + open editor + answer list
			return 2 + answerCount
		} else {
			// title + open editor + text field
			return 3
		}
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		if indexPath.row == 0 {
			let cell = tableView.dequeueReusableCell(withIdentifier: "QuestTitle", for: indexPath)
			cell.textLabel?.text = quest.title
			return cell
		} else if indexPath.row == self.tableView(tableView, numberOfRowsInSection: 0) - 1 {
			let cell = tableView.dequeueReusableCell(withIdentifier: "QuestOpenEditor", for: indexPath)
			return cell
		} else if let _ = presetKey?.presetList?.count {
			let cell = tableView.dequeueReusableCell(withIdentifier: "QuestTagValue", for: indexPath)
			cell.textLabel?.text = presetKey?.presetList?[indexPath.row - 1].name ?? ""
			return cell
		} else {
			let cell = tableView.dequeueReusableCell(withIdentifier: "QuestTextEntry", for: indexPath)
			return cell
		}
	}
}