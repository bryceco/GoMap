//
//  QuestSolverController.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 2/5/23.
//  Copyright © 2023 Bryce Cogswell. All rights reserved.
//

import UIKit

class QuestSolverTextEntryCell: UITableViewCell {
	@IBOutlet var textField: PresetValueTextField?
}

private let NUMBER_OF_HEADERS = 2 // feature name + quest name
private let NUMBER_OF_FOOTERS = 2 // ignore + open tag editor

class QuestSolverController: UITableViewController, PresetValueTextFieldOwner {
	var questMarker: QuestMarker!
	var object: OsmBaseObject!
	var presetFeature: PresetFeature?
	var presetKeys: [PresetKey?] = []
	var tagKeys: [String] = []
	var onClose: (() -> Void)?

	override func viewDidLoad() {
		super.viewDidLoad()
		tableView.allowsMultipleSelection = tagKeys.count > 1
		navigationItem.rightBarButtonItem?.isEnabled = false
		tableView.separatorStyle = .none
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		setFirstResponder()
	}

	func setFirstResponder() {
		if presetKeys.count == 1,
		   let presetKey = presetKeys[0]
		{
			if (presetKey.presetList?.count ?? 0) < 2 || isOpeningHours(presetKey.tagKey) {
				// set text cell to first responder
				if let cell = tableView.cellForRow(at: IndexPath(row: 0, section: 1)),
				   let cell2 = cell as? QuestSolverTextEntryCell
				{
					cell2.textField?.becomeFirstResponder()
				}
			}
		}
	}

	func refreshPresetKey() -> Bool {
		let presets = PresetsForFeature(
			withFeature: presetFeature,
			objectTags: object.tags,
			geometry: object.geometry(),
			update: { [weak self] in
				guard let self = self else { return }
				if self.refreshPresetKey() {
					self.tableView.reloadData()
					self.setFirstResponder()
				}
			})

		var didChange = false
		for preset in presets.allPresetKeys() {
			if let index = tagKeys.firstIndex(where: { $0 == preset.tagKey }) {
				if presetKeys[index] == preset {
					continue // no change
				} else {
					presetKeys[index] = preset
					didChange = true
				}
			}
		}
		return didChange
	}

	// MARK: Actions

	public class func instantiate(marker: QuestMarker, object: OsmBaseObject,
	                              onClose: @escaping () -> Void) -> UINavigationController
	{
		let sb = UIStoryboard(name: "QuestSolver", bundle: nil)
		let vc2 = sb.instantiateViewController(withIdentifier: "QuestSolver") as! UINavigationController
		let vc = vc2.viewControllers.first as! QuestSolverController

		vc.object = object
		vc.questMarker = marker
		vc.title = NSLocalizedString("Quest", comment: "The current Quest the user is answering")
		vc.onClose = onClose
		vc.tagKeys = marker.quest.tagKeys
		vc.presetKeys = vc.tagKeys.map { _ in nil }
		vc.presetFeature = PresetsDatabase.shared.presetFeatureMatching(
			tags: object.tags,
			// We don't use the object geometry here in case the object has tags that match against
			// multiple features and the isArea() function chooses the wrong one.
			geometry: nil, // object.geometry(),
			location: AppDelegate.shared.mapView.currentRegion,
			includeNSI: false,
			withPresetKey: vc.tagKeys.first)
		_ = vc.refreshPresetKey()
		return vc2
	}

	@IBAction func onCancel(_ sender: Any?) {
		dismiss(animated: true, completion: nil)
		if let mapView = AppDelegate.shared.mapView {
			mapView.editorLayer.selectedNode = nil
			mapView.editorLayer.selectedWay = nil
			mapView.editorLayer.selectedRelation = nil
			mapView.placePushpinForSelection()
		}
	}

	@IBAction func onSave(_ sender: Any?) {
		let editor = AppDelegate.shared.mapView.editorLayer
		guard var tags = editor.selectedPrimary?.tags else { return }
		for keyIndex in presetKeys.indices {
			let section = keyIndex + 1
			if let cell = tableView.cellForRow(at: IndexPath(row: tableView.numberOfRows(inSection: section) - 1,
			                                                 section: section))
				as? QuestSolverTextEntryCell,
				let text = cell.textField?.text,
				text.count > 0
			{
				// free-form text field
				tags[tagKeys[keyIndex]] = text
			} else if let index = tableView.indexPathsForSelectedRows?.first(where: { $0.section == section }),
			          let text = presetKeys[keyIndex]?.presetList?[index.row].tagValue
			{
				// user selected a preset
				tags[tagKeys[keyIndex]] = text
			} else {
				// No value set
			}
		}
		editor.setTagsForCurrentObject(tags)
		dismiss(animated: true, completion: nil)
	}

	@IBAction func ignoreAlways(_ sender: Any?) {
		questMarker.ignorable!.ignore(marker: questMarker, reason: .userRequest)
		onCancel(sender)
	}

	@IBAction func ignoreThisSession(_ sender: Any?) {
		let until = Date().addingTimeInterval(60 * 60)
		questMarker.ignorable!.ignore(marker: questMarker, reason: .userRequestUntil(until))
		onCancel(sender)
	}

	@IBAction func openTagEditor(_ sender: Any?) {
		if navigationItem.rightBarButtonItem?.isEnabled ?? false {
			let alertSheet = UIAlertController(title: NSLocalizedString("Save or discard your changes", comment: ""),
			                                   message: nil,
			                                   preferredStyle: .alert)
			alertSheet.addAction(UIAlertAction(title: NSLocalizedString("Save", comment: "Save changes"),
			                                   style: .default,
			                                   handler: { _ in
			                                   	self.onSave(sender)
			                                   	AppDelegate.shared.mapView?.presentTagEditor(nil)
			                                   }))
			alertSheet.addAction(UIAlertAction(title: NSLocalizedString("Discard", comment: "Discard changes"),
			                                   style: .default,
			                                   handler: { _ in
			                                   	self.dismiss(animated: true, completion: nil)
			                                   	AppDelegate.shared.mapView?.presentTagEditor(nil)
			                                   }))
			alertSheet.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""),
			                                   style: .cancel,
			                                   handler: nil))
			present(alertSheet, animated: true)
			return
		}
		dismiss(animated: false, completion: nil)
		AppDelegate.shared.mapView?.presentTagEditor(nil)
	}

	// MARK: TableView delegate

	override func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
		guard
			indexPath.section > 0, indexPath.section < 1 + tagKeys.count,
			!(tableView.cellForRow(at: indexPath) is QuestSolverTextEntryCell)
		else {
			return nil
		}
		// deselect other items in the same section
		for row in 0..<self.tableView(tableView, numberOfRowsInSection: indexPath.section) {
			self.tableView.deselectRow(at: IndexPath(row: row, section: indexPath.section),
			                           animated: false)
		}
		return indexPath
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		switch indexPath.section {
		case 0:
			// heaader
			break
		case 1 + tagKeys.count:
			// footer
			break
		default:
			navigationItem.rightBarButtonItem?.isEnabled = true
		}
	}

	override func numberOfSections(in tableView: UITableView) -> Int {
		return 1 + tagKeys.count + 1
	}

	override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		switch section {
		case 0:
			return nil
		case tagKeys.count + 1:
			return nil
		default:
			return tagKeys[section - 1]
		}
	}

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		switch section {
		case 0:
			return NUMBER_OF_HEADERS
		case 1 + tagKeys.count: // header section + tagKeys
			return NUMBER_OF_FOOTERS
		default:
			if let presetKey = presetKeys[section - 1],
			   let answerCount = presetKey.presetList?.count,
			   answerCount >= 2,
			   !presetKey.isYesNo(),
			   !isOpeningHours(key: presetKey)
			{
				return answerCount + 1
			} else {
				return 1
			}
		}
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		switch indexPath.section {
		case 0:
			// Headers
			switch indexPath.row {
			case 0:
				// The name of the object being edited
				let cell = tableView.dequeueReusableCell(withIdentifier: "QuestCellTitle", for: indexPath)
				cell.textLabel?.text = object.friendlyDescription()
				cell.textLabel?.textAlignment = .center
				cell.textLabel?.font = UIFont.preferredFont(forTextStyle: .title2)
				return cell
			case 1:
				// The name of the quest
				let cell = tableView.dequeueReusableCell(withIdentifier: "QuestCellTitle", for: indexPath)
				cell.textLabel?.text = questMarker.quest.title
				cell.textLabel?.textAlignment = .natural
				cell.textLabel?.font = UIFont.preferredFont(forTextStyle: .headline)
				return cell
			default:
				fatalError()
			}
		case tagKeys.count + 1:
			// Footers
			switch indexPath.row {
			case 0:
				// A button to open the regular tag editor
				let cell = tableView.dequeueReusableCell(withIdentifier: "QuestCellIgnore", for: indexPath)
				return cell
			case 1:
				// A button to open the regular tag editor
				let cell = tableView.dequeueReusableCell(withIdentifier: "QuestCellOpenEditor", for: indexPath)
				return cell
			default:
				fatalError()
			}
		default:
			// Preset cell
			if indexPath.row < tableView.numberOfRows(inSection: indexPath.section) - 1 {
				// A selection among a combo of possible values
				let presetKey = presetKeys[indexPath.section - 1]
				let presetValue = presetKey?.presetList?[indexPath.row]
				let cell = tableView.dequeueReusableCell(withIdentifier: "QuestCellTagValue", for: indexPath)
				cell.textLabel?.text = presetValue?.name ?? ""
				if let value = object.tags[tagKeys[indexPath.section - 1]],
				   value == presetValue?.tagValue
				{
					// The value is already set
					tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
				}
				return cell
			} else {
				// A text box to type something in
				let cell = tableView.dequeueReusableCell(withIdentifier: "QuestCellTextEntry",
				                                         for: indexPath) as! QuestSolverTextEntryCell
				cell.textField?.owner = self
				if let presetKey = presetKeys[indexPath.section - 1] {
					cell.textField?.presetKey = presetKey
				} else {
					cell.textField?.key = tagKeys[indexPath.section - 1]
				}
				if let value = object.tags[tagKeys[indexPath.section - 1]] {
					// The value is already set
					cell.textField?.text = value
				}
				return cell
			}
		}
	}

	// MARK: PresetValueTextFieldOwner

	var allPresetKeys: [PresetKey] { presetKeys.compactMap { $0 } }
	var childViewPresented = false
	var viewController: UIViewController { self }
	func valueChanged(for textField: PresetValueTextField, ended: Bool) {
		let okay = questMarker.quest.accepts(tagValue: textField.text ?? "")
		navigationItem.rightBarButtonItem?.isEnabled = okay
	}
}

// MARK: Special code for handling opening_hours using the camera

extension QuestSolverController {
	func isOpeningHours(_ key: String) -> Bool {
		return OsmTags.isKey(key, variantOf: "opening_hours")
	}

	func isOpeningHours(key: PresetKey) -> Bool {
#if !targetEnvironment(macCatalyst)
#if arch(arm64) || arch(x86_64) // old architectures don't support SwiftUI
		if #available(iOS 14.0, *) {
			return isOpeningHours(key.tagKey)
		}
#endif
#endif
		return false
	}

	@objc func recognizeOpeningHours(_ sender: Any?) {
#if !targetEnvironment(macCatalyst)
#if arch(arm64) || arch(x86_64) // old architectures don't support SwiftUI
		if #available(iOS 14.0, *) {
			guard
				let cell: UITableViewCell = (sender as? UIView)?.superviewOfType(),
				let cell = cell as? QuestSolverTextEntryCell
			else {
				return
			}
			let vc = OpeningHoursRecognizerController.with(
				onAccept: { newValue in
					cell.textField?.text = newValue
					self.navigationItem.rightBarButtonItem?.isEnabled = true
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
