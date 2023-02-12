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
	var didChange: ((String) -> Void)?

	required init?(coder: NSCoder) {
		super.init(coder: coder)
	}

	override func prepareForReuse() {
		textField!.addTarget(self, action: #selector(textFieldChanged(_:)), for: .editingChanged)
	}

	@objc func textFieldChanged(_ sender: Any?) {
		didChange?(textField?.text ?? "")
	}
}

private let NUMBER_OF_HEADERS = 2 // feature name + quest name
private let NUMBER_OF_FOOTERS = 1 // open tag editor

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
		setFirstResponder()
	}

	func setFirstResponder() {
		if presetKey?.presetList?.count == nil {
			// set text cell to first responder
			if let cell = tableView.cellForRow(at: IndexPath(row: NUMBER_OF_HEADERS, section: 0)),
			   let cell2 = cell as? QuestTextEntryCell
			{
				cell2.textField?.becomeFirstResponder()
			}
		}
	}

	func refreshPresetKey() -> Bool {
		let presets = PresetsForFeature(
			withFeature: presetFeature,
			objectTags: object.tags,
			geometry: object.geometry(),
			update: {
				if self.refreshPresetKey() {
					self.tableView.reloadData()
					self.setFirstResponder()
				}
			})

		for section in presets.sectionList {
			for g in section.presetKeys {
				let list = Self.presetsForGroup(g)
				for preset in list {
					if preset.tagKey == quest.presetKey {
						if presetKey == preset {
							return false // no change
						} else {
							presetKey = preset
							tableView.separatorColor = presetKey?.presetList?.count == nil ? .clear : nil
							return true
						}
					}
				}
			}
		}
		return false
	}

	public class func instantiate(quest: QuestProtocol, object: OsmBaseObject,
	                              onClose: @escaping () -> Void) -> UINavigationController
	{
		let sb = UIStoryboard(name: "QuestEditor", bundle: nil)
		let vc2 = sb.instantiateViewController(withIdentifier: "QuestEditor") as! UINavigationController
		let vc = vc2.viewControllers.first as! QuestEditorController

		vc.object = object
		vc.quest = quest
		vc.title = NSLocalizedString("Your Quest", comment: "The current Quest the user is answering")
		vc.onClose = onClose
		vc.presetFeature = PresetsDatabase.shared.presetFeatureMatching(
			tags: object.tags,
			geometry: object.geometry(),
			location: AppDelegate.shared.mapView.currentRegion,
			includeNSI: false)
		_ = vc.refreshPresetKey()
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
		guard var tags = editor.selectedPrimary?.tags else { return }
		if let index = tableView.indexPathForSelectedRow,
		   let text = presetKey?.presetList?[index.row - NUMBER_OF_HEADERS].tagValue
		{
			// user selected a preset
			tags[quest.presetKey] = text
			editor.setTagsForCurrentObject(tags)
		} else if let cell = tableView
			.cellForRow(at: IndexPath(row: NUMBER_OF_HEADERS, section: 0)) as? QuestTextEntryCell,
			let text = cell.textField?.text
		{
			tags[quest.presetKey] = text
			editor.setTagsForCurrentObject(tags)
		} else {
			return
		}
		dismiss(animated: true, completion: nil)
	}

	override func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
		guard
			indexPath.row >= 2
		else {
			return nil
		}
		return indexPath
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
		if let presetKey = presetKey,
		   let answerCount = presetKey.presetList?.count,
		   !isOpeningHours(key: presetKey)
		{
			// title + object + answer list + open editor
			return NUMBER_OF_HEADERS + answerCount + NUMBER_OF_FOOTERS
		} else {
			// title + object + text field + open editor
			return NUMBER_OF_HEADERS + 1 + NUMBER_OF_FOOTERS
		}
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		if indexPath.row == 0 {
			// The name of the object being edited
			let cell = tableView.dequeueReusableCell(withIdentifier: "QuestTitle", for: indexPath)
			cell.textLabel?.text = object.friendlyDescription()
			cell.textLabel?.textAlignment = .center
			cell.textLabel?.font = UIFont.preferredFont(forTextStyle: .title2)
			return cell
		} else if indexPath.row == 1 {
			// The name of the quest
			let cell = tableView.dequeueReusableCell(withIdentifier: "QuestTitle", for: indexPath)
			cell.textLabel?.text = quest.title
			cell.textLabel?.textAlignment = .natural
			cell.textLabel?.font = UIFont.preferredFont(forTextStyle: .body)
			return cell
		} else if indexPath.row == self.tableView(tableView, numberOfRowsInSection: 0) - 1 {
			// A button to open the regular tag editor
			let cell = tableView.dequeueReusableCell(withIdentifier: "QuestOpenEditor", for: indexPath)
			return cell
		} else if let presetKey = presetKey,
		          presetKey.presetList?.count != nil,
		          !isOpeningHours(key: presetKey)
		{
			// A selection among a combo of possible values
			let cell = tableView.dequeueReusableCell(withIdentifier: "QuestTagValue", for: indexPath)
			cell.textLabel?.text = presetKey.presetList?[indexPath.row - NUMBER_OF_HEADERS].name ?? ""
			return cell
		} else {
			// A text box to type something in
			let cell = tableView.dequeueReusableCell(withIdentifier: "QuestTextEntry",
			                                         for: indexPath) as! QuestTextEntryCell
			cell.textField?.autocorrectionType = (presetKey?.autocorrectType) ?? .no
			cell.textField?.autocapitalizationType = presetKey?.autocapitalizationType ?? .none

			if presetKey?.keyboardType == .phonePad,
			   let textField = cell.textField
			{
				textField.keyboardType = .phonePad
				textField.inputAccessoryView = TelephoneToolbar(forTextField: textField,
				                                                frame: view.frame)
			}

			cell.didChange = { text in
				let okay = self.quest.accepts(tagValue: text)
				self.navigationItem.rightBarButtonItem?.isEnabled = okay
			}
			if let presetKey = presetKey,
			   isOpeningHours(key: presetKey)
			{
				let button = UIButton(type: .custom)
				button.setTitle("📷", for: .normal)
				button.addTarget(self, action: #selector(recognizeOpeningHours), for: .touchUpInside)
				cell.textField?.rightView = button
				cell.textField?.rightViewMode = .always
			}

			return cell
		}
	}
}

extension QuestEditorController {
	func isOpeningHours(key: PresetKey) -> Bool {
#if !targetEnvironment(macCatalyst)
#if arch(arm64) || arch(x86_64) // old architectures don't support SwiftUI
		if #available(iOS 14.0, *) {
			return key.tagKey == "opening_hours" || key.tagKey.hasSuffix(":opening_hours")
		}
#endif
#endif
		return false
	}

	@objc func recognizeOpeningHours() {
#if !targetEnvironment(macCatalyst)
#if arch(arm64) || arch(x86_64) // old architectures don't support SwiftUI
		if #available(iOS 14.0, *) {
			let vc = OpeningHoursRecognizerController.with(
				onAccept: { newValue in
					if let cell = self.tableView.cellForRow(at: IndexPath(row: NUMBER_OF_HEADERS, section: 0)),
					   let cell = cell as? QuestTextEntryCell
					{
						cell.textField?.text = newValue
						self.navigationItem.rightBarButtonItem?.isEnabled = true
					}
					self.navigationController?.popViewController(animated: true)
				}, onCancel: {
					self.navigationController?.popViewController(animated: true)
				}, onRecognize: { _ in
				})
			self.navigationController?.pushViewController(vc, animated: true)
		}
#endif
#endif
	}
}
