//
//  QuestEditorController.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 9/21/21.
//  Copyright © 2021 Bryce. All rights reserved.
//

import UIKit

private enum Sections: Int, CaseIterable {
	case ValuePicker = 0
	case OpenEditor = 1
}

class QuestEditorController: UITableViewController {
	var quest: QuestProtocol!
	var object: OsmBaseObject!
	var presetFeature: PresetFeature?
	var presetKey: PresetKey?

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

	class func instantiate(quest: QuestProtocol, object: OsmBaseObject) -> UINavigationController {
		let sb = UIStoryboard(name: "QuestEditor", bundle: nil)
		guard let vc2 = sb.instantiateViewController(withIdentifier: "QuestEditor") as? UINavigationController,
		      let vc = vc2.viewControllers.first as? QuestEditorController
		else {
			fatalError()
		}
		vc.object = object
		vc.quest = quest
		vc.title = quest.title
		vc.presetFeature = PresetsDatabase.shared.matchObjectTagsToFeature(object.tags,
		                                                                   geometry: object.geometry(),
		                                                                   includeNSI: false)
		let presets = PresetsForFeature(
			withFeature: vc.presetFeature,
			objectTags: object.tags,
			geometry: object.geometry(),
			update: nil)
		top_loop: for section in presets.sectionList() {
			for g in section.presetKeys {
				let list = Self.presetsForGroup(g)
				for preset in list {
					if preset.tagKey == quest.tagKey {
						vc.presetKey = preset
						break top_loop
					}
				}
			}
		}
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
		if indexPath.section == 1 {
			dismiss(animated: false, completion: nil)
			AppDelegate.shared.mapView?.presentTagEditor(nil)
		}
		navigationItem.rightBarButtonItem?.isEnabled = true
	}

	override func numberOfSections(in tableView: UITableView) -> Int {
		return Sections.allCases.count
	}

	override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		switch Sections(rawValue: section)! {
		case .ValuePicker: return nil
		case .OpenEditor: return " "
		}
	}

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		switch Sections(rawValue: section)! {
		case .ValuePicker: return presetKey?.presetList?.count ?? 0
		case .OpenEditor: return 1
		}
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		switch Sections(rawValue: indexPath.section)! {
		case .ValuePicker:
			let cell = tableView.dequeueReusableCell(withIdentifier: "TagValue", for: indexPath)
			cell.textLabel?.text = presetKey?.presetList?[indexPath.row].name ?? ""
			return cell
		case .OpenEditor:
			let cell = tableView.dequeueReusableCell(withIdentifier: "OpenEditor", for: indexPath)
			return cell
		}
	}
}
