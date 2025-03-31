//
//  POIFeaturePresetsViewController.swift
//  Go Map!!
//
//  Copyright © 2021 Bryce Cogswell. All rights reserved.
//

import UIKit

class FeaturePresetCell: UITableViewCell {
	@IBOutlet var nameLabel: UILabel!
	@IBOutlet var valueField: PresetValueTextField!
	@IBOutlet var isSet: UIView!
	var presetKey: PresetKeyOrGroup?
}

class FeatureTypeCell: UITableViewCell {
	@IBOutlet var nameLabel: UILabel!
	@IBOutlet var valueField: UITextField!
	@IBOutlet var isSet: UIView!
	var presetKey: PresetKeyOrGroup?
}

class FeaturePresetAreaCell: UITableViewCell {
	@IBOutlet var nameLabel: UILabel!
	@IBOutlet var valueField: UITextView!
	@IBOutlet var isSet: UIView!
	var presetKey: PresetKey!

	private static let placeholderColor: UIColor = {
		if #available(iOS 13.0, *) {
			return UIColor.placeholderText
		} else {
			return UIColor.lightText
		}
	}()

	private static let regularColor: UIColor = {
		if #available(iOS 13.0, *) {
			return UIColor.label
		} else {
			return UIColor.black
		}
	}()

	func placeholderText() -> String {
		return presetKey.placeholder
	}

	func addPlaceholderText() {
		if valueField.text == "" {
			valueField.textColor = Self.placeholderColor
			valueField.text = placeholderText()
		}
	}

	func removePlaceholderText() {
		if valueField.text == placeholderText(), valueField.textColor == Self.placeholderColor {
			valueField.textColor = Self.regularColor
			valueField.text = ""
		}
	}
}

class POICommonTagsViewController: UITableViewController, UITextFieldDelegate, UITextViewDelegate,
	POIFeaturePickerDelegate, KeyValueTableCellOwner, PresetValueTextFieldOwner
{
	@IBOutlet var saveButton: UIBarButtonItem!
	private var allPresets: PresetsForFeature? {
		didSet { computeExtraTags() }
	}

	private var selectedFeature: PresetFeature? // the feature selected by the user, not derived from tags (e.g. Address)
	private var currentFeature: PresetFeature? // the feature that was most recently inferred from the tags
	private var childPushed = false
	private var drillDownGroup: PresetGroup?
	private var firstResponderTextField: UITextField?
	private var extraTags: KeyValueTableSection! // array of key/values not covered by presets

	static let isSetHighlight = UIColor.systemBlue

	override func viewDidLoad() {
		// have to update presets before call super because super asks for the number of sections
		extraTags = KeyValueTableSection(tableView: tableView)
		updatePresets()

		super.viewDidLoad()

		tableView.estimatedRowHeight = 44.0 // or could use UITableViewAutomaticDimension;
		tableView.rowHeight = UITableView.automaticDimension
		tableView.keyboardDismissMode = .none

		if let drillDownGroup = drillDownGroup {
			navigationItem.leftItemsSupplementBackButton = true
			navigationItem.leftBarButtonItem = nil
			navigationItem.title = drillDownGroup.name
		}
	}

	func cellForKey(_ key: String) -> UITableViewCell? {
		for cell in tableView.visibleCells {
			if let presetList = (cell as? FeaturePresetCell)?.presetKey?.flattenedPresets(),
			   presetList.contains(where: { $0.tagKey == key })
			{
				return cell
			} else if (cell as? FeaturePresetAreaCell)?.presetKey.tagKey == key {
				return cell
			} else if (cell as? KeyValueTableCell)?.key == key {
				return cell
			}
		}
		return nil
	}

	func indexPathForKey(_ key: String) -> IndexPath? {
		if let cell = cellForKey(key) {
			return tableView.indexPath(for: cell)
		}
		return nil
	}

	func updateTagDictLow(withValue value: String, forKey key: String) {
		guard let tabController = tabBarController as? POITabBarController else {
			// This shouldn't happen, but there are crashes here
			// originating from textFieldDidEndEditing(). Maybe
			// when closing the modal somehow?
			return
		}

		if key == "" {
			// do nothing
		} else if value != "" {
			tabController.keyValueDict[key] = value
		} else {
			tabController.keyValueDict.removeValue(forKey: key)
		}

		saveButton.isEnabled = tabController.isTagDictChanged()
		if #available(iOS 13.0, *) {
			tabController.isModalInPresentation = saveButton.isEnabled
		}
	}

	func updateTagDict(withValue value: String, forKey key: String) {
		if let indexPath = indexPathFor(key: key),
		   setBothValuesFor(indexPath: indexPath, value: value)
		{
			return
		}
		updateTagDictLow(withValue: value, forKey: key)
	}

	func updatePresets() {
		let tabController = tabBarController as! POITabBarController

		saveButton.isEnabled = tabController.isTagDictChanged()
		if #available(iOS 13.0, *) {
			tabController.isModalInPresentation = saveButton.isEnabled
		}

		if drillDownGroup == nil {
			let dict = tabController.keyValueDict
			let object = tabController.selection
			let geometry = object?.geometry() ?? GEOMETRY.POINT

			// update most recent feature
			selectedFeature = selectedFeature ?? PresetsDatabase.shared.presetFeatureMatching(
				tags: dict,
				geometry: geometry,
				location: AppDelegate.shared.mapView.currentRegion,
				includeNSI: true)
			if currentFeature === selectedFeature {
//				computeExtraTags()
//				return
			}
			currentFeature = selectedFeature

			if let feature = selectedFeature {
				POIFeaturePickerViewController.loadMostRecent(forGeometry: geometry)
				POIFeaturePickerViewController.updateMostRecentArray(withSelection: feature, geometry: geometry)
			}

			weak var weakself = self
			allPresets = PresetsForFeature(withFeature: selectedFeature, objectTags: dict, geometry: geometry, update: {
				// This closure is called whenever results from TagInfo return, which
				// may be much later, even after we've been dismissed. We need to rebuild
				// the preset list in response.
				if let weakself = weakself,
				   !weakself.isEditing
				{
					weakself.allPresets = PresetsForFeature(
						withFeature: weakself.currentFeature,
						objectTags: tabController.keyValueDict,
						geometry: geometry,
						update: nil)
					weakself.tableView.reloadData()
				}
			})
		}

		tableView.reloadData()
	}

	func computeExtraTags() {
		var presetKeys = (allPresets?.allPresetKeys() ?? []).map { $0.tagKey }
		// The first entry is the Feature Type, so we need to special case it
		if let feature = selectedFeature,
		   presetKeys.first == ""
		{
			presetKeys.remove(at: 0)
			presetKeys += feature.addTags.keys
		}
		let dict = (tabBarController as! POITabBarController).keyValueDict
		var extraKeys = Array(dict.keys)
		for key in presetKeys {
			extraKeys.removeAll(where: { $0 == key })
		}
		extraTags.set(extraKeys.map { ($0, dict[$0]!) })
	}

	// MARK: display

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)

		if isMovingToParent {
		} else {
			// When coming from All Tags or other views we need to recompute everything
			updatePresets()
		}
	}

	override func viewWillDisappear(_ animated: Bool) {
		resignAll()
		super.viewWillDisappear(animated)
		selectedFeature = nil
		currentFeature = nil
		childPushed = true
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)

		if !isMovingToParent {
			// special case: if this is a new object and the user just selected the feature to be shop/amenity,
			// then automatically select the Name field as the first responder
			let tabController = tabBarController as! POITabBarController
			if tabController.isTagDictChanged() {
				let dict = tabController.keyValueDict
				if dict.count == 1,
				   dict["shop"] != nil || dict["amenity"] != nil,
				   dict["name"] == nil
				{
					// find name field and make it first responder
					DispatchQueue.main.async(execute: { [weak self] in
						let index = IndexPath(row: 1, section: 0)
						if let cell = self?.tableView.cellForRow(at: index) as? FeaturePresetCell,
						   case let .key(presetKey) = cell.presetKey,
						   presetKey.tagKey == "name"
						{
							cell.valueField.becomeFirstResponder()
						}
					})
				}

			} else if !childPushed,
			          (tabController.selection?.ident ?? 0) <= 0,
			          tabController.keyValueDict.count == 0
			{
				// if we're being displayed for a newly created node then go straight to the Type picker
				performSegue(withIdentifier: "POITypeSegue", sender: nil)
			}
		}
	}

	func featurePicker(_ typeViewController: POIFeaturePickerViewController,
	                   didChangeFeatureTo newFeature: PresetFeature)
	{
		selectedFeature = newFeature
		let tabController = tabBarController as! POITabBarController
		let geometry = tabController.selection?.geometry() ?? GEOMETRY.POINT
		let location = AppDelegate.shared.mapView.currentRegion
		tabController.keyValueDict = newFeature.objectTagsUpdatedForFeature(tabController.keyValueDict,
		                                                                    geometry: geometry,
		                                                                    location: location)
	}

	// MARK: - Table view data source

	override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
		return UITableView.automaticDimension
	}

	override func numberOfSections(in tableView: UITableView) -> Int {
		return (drillDownGroup != nil) ? 1 : (allPresets?.sectionCount() ?? 0) + 2
	}

	override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		if drillDownGroup != nil {
			return drillDownGroup?.name
		}
		guard let allPresets = allPresets else {
			return nil
		}
		if section == allPresets.sectionCount() {
			return nil // extra tags
		}
		if section > allPresets.sectionCount() {
			return nil // customize button
		}

		let group = allPresets.sectionList[section]
		return group.name
	}

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		if let drillDownGroup {
			return drillDownGroup.presetKeys.count
		}
		if section == (allPresets?.sectionCount() ?? 0) {
			return extraTags.count // tags plus an empty slot
		}
		if section > (allPresets?.sectionCount() ?? 0) {
			return 2 // customization buttons
		}
		return allPresets?.tagsInSection(section) ?? 0
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		guard let tabController = tabBarController as? POITabBarController else {
			return UITableViewCell()
		}

		if drillDownGroup == nil {
			// special case the key/value cells and the customize button
			if indexPath.section == allPresets?.sectionCount() {
				// extra tags
				let cell = tableView.dequeueReusableCell(withIdentifier: "KeyValueCell",
				                                         for: indexPath) as! KeyValueTableCell
				cell.keyValueCellOwner = self
				cell.text1?.text = extraTags[indexPath.row].k
				cell.text2?.text = extraTags[indexPath.row].v
				cell.text2.key = cell.text1?.text ?? ""
				cell.isSet.backgroundColor = cell.value == "" ? nil : Self.isSetHighlight
				return cell
			}
			if indexPath.section > (allPresets?.sectionCount() ?? 0) {
				// customization buttons
				switch indexPath.row {
				case 0:
					let cell = tableView.dequeueReusableCell(withIdentifier: "CustomFeatures", for: indexPath)
					return cell
				case 1:
					let cell = tableView.dequeueReusableCell(withIdentifier: "CustomFields", for: indexPath)
					return cell
				default:
					fatalError("unexpected customize button row \(indexPath.row)")
				}
			}
		}

		let keyValueDict = tabController.keyValueDict

		let rowObject = (drillDownGroup != nil) ? drillDownGroup!.presetKeys[indexPath.row]
			: allPresets!.presetAtIndexPath(indexPath)

		switch rowObject {
		case let PresetKeyOrGroup.key(presetKey):
			let key = presetKey.tagKey

			if presetKey.type == "textarea" {
				// special case for keys that contain large amounts of text
				let cell = tableView.dequeueReusableCell(withIdentifier: "CommonTagArea",
				                                         for: indexPath) as! FeaturePresetAreaCell
				cell.valueField.delegate = self
				let value = keyValueDict[presetKey.tagKey] ?? ""
				cell.isSet.backgroundColor = value == "" ? nil : Self.isSetHighlight
				cell.valueField.text = value
				cell.valueField.returnKeyType = .done
				cell.accessoryType = .none
				cell.nameLabel.text = presetKey.name
				cell.presetKey = presetKey
				if #available(iOS 13.0, *) {
					cell.valueField.backgroundColor = UIColor.secondarySystemGroupedBackground
				}
				if value != "" {
					// This shouldn't be necessary but the cell height isn't correct
					// when the cell first appears.
					DispatchQueue.main.asyncAfter(deadline: .now() + 0.01, execute: { [weak self] in
						self?.updateTextViewSize(cell.valueField)
					})
				} else {
					cell.addPlaceholderText()
				}
				return cell
			}

			switch key {
			case "":
				// Feature type cell
				let cell = tableView.dequeueReusableCell(withIdentifier: "CommonTagType",
				                                         for: indexPath) as! FeatureTypeCell
				let text = allPresets?.featureName ?? ""
				cell.valueField.text = text
				cell.valueField.isEnabled = false
				cell.isSet.backgroundColor = (selectedFeature?.addTags.count ?? 0) > 0 ? Self.isSetHighlight : nil

				let setupIcon: (UIImage) -> Void = { icon in
					let view = UIImageView(image: icon)
					view.contentMode = .scaleAspectFit
					view.widthAnchor.constraint(equalToConstant: 40).isActive = true
					view.heightAnchor.constraint(equalToConstant: 40).isActive = true
					cell.valueField.rightView = view
					cell.valueField.rightViewMode = .always
				}

				if let icon = currentFeature?.nsiLogo(callback: setupIcon) {
					setupIcon(icon)
				} else {
					cell.valueField.rightView = nil
					cell.valueField.rightViewMode = .never
				}
				return cell

			default:
				let cellName = key == "name" ? "CommonTagName" : "CommonTagSingle"
				let cell = tableView.dequeueReusableCell(withIdentifier: cellName,
				                                         for: indexPath) as! FeaturePresetCell
				cell.accessoryType = .none
				cell.nameLabel.text = presetKey.name
				cell.valueField.owner = self
				cell.valueField.placeholder = presetKey.placeholder
				cell.valueField.delegate = self
				cell.valueField.presetKey = presetKey
				cell.presetKey = .key(presetKey)
				cell.valueField.keyboardType = presetKey.keyboardType
				cell.valueField.autocapitalizationType = presetKey.autocapitalizationType

				cell.valueField.removeTarget(self, action: nil, for: .allEvents)
				cell.valueField.addTarget(self, action: #selector(textFieldReturn(_:)), for: .editingDidEndOnExit)
				cell.valueField.addTarget(self, action: #selector(textFieldChanged(_:)), for: .editingChanged)
				cell.valueField.addTarget(self, action: #selector(textFieldEditingDidBegin(_:)), for: .editingDidBegin)
				cell.valueField.addTarget(self, action: #selector(textFieldDidEndEditing(_:)), for: .editingDidEnd)

				cell.isSet.backgroundColor = keyValueDict[presetKey.tagKey] == nil ? nil : Self.isSetHighlight

				if !presetKey.isYesNo(),
				   let presets = presetKey.presetList,
				   presets.count > 0
				{
					// The user can select from a list of presets.
					cell.accessoryType = .disclosureIndicator
				}

				var value = keyValueDict[presetKey.tagKey]

				// Special case for groups that use ":both"
				// We display the ":both" value if the designated value is empty
				if value == nil,
				   let presetGroup = allPresets?.sectionList[indexPath.section],
				   presetGroup.usesBoth,
				   let bothKey = bothKeyFor(preset: presetKey),
				   let bothValue = keyValueDict[bothKey]
				{
					value = bothValue
				}

				let prettyValue = presetKey.prettyNameForTagValue(value ?? "")
				cell.valueField.text = prettyValue
				cell.valueField.isEnabled = true
				return cell
			}

		case let PresetKeyOrGroup.group(drillDownGroup):

			// drill down cell
			let cell = tableView.dequeueReusableCell(withIdentifier: "CommonTagSingle",
			                                         for: indexPath) as! FeaturePresetCell
			cell.nameLabel.text = drillDownGroup.name
			cell.valueField.owner = self
			cell.valueField.text = drillDownGroup.multiComboSummary(ofDict: keyValueDict, isPlaceholder: false)
			cell.valueField.placeholder = drillDownGroup.multiComboSummary(ofDict: nil, isPlaceholder: true)
			cell.valueField.isEnabled = false
			cell.valueField.rightView = nil
			cell.presetKey = .group(drillDownGroup)
			cell.accessoryType = .disclosureIndicator
			cell.isSet.backgroundColor = cell.valueField.text == "" ? nil : Self.isSetHighlight

			return cell
		}
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		guard let cell = tableView.cellForRow(at: indexPath),
		      cell.accessoryType != .none
		else { return }

		if drillDownGroup == nil, indexPath.section == 0, indexPath.row == 0 {
			performSegue(withIdentifier: "POITypeSegue", sender: cell)
		} else if let cell = cell as? FeaturePresetCell,
		          case let .group(group) = cell.presetKey
		{
			// special case for drill down
			let sub = storyboard?.instantiateViewController(
				withIdentifier: "PoiCommonTagsViewController") as! POICommonTagsViewController
			sub.drillDownGroup = group
			navigationController?.pushViewController(sub, animated: true)
		} else {
			performSegue(withIdentifier: "POIPresetSegue", sender: cell)
		}
	}

	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		if let dest = segue.destination as? POIPresetValuePickerController,
		   let cell = sender as? FeaturePresetCell,
		   case .key(let presetKey) = cell.presetKey
		{
			dest.key = presetKey.tagKey
			dest.presetValueList = presetKey.presetList ?? []
			dest.onSetValue = { [weak self] value in
				self?.updateTagDict(withValue: value, forKey: presetKey.tagKey)
			}
			var name = presetKey.name
			if let indexPath = tableView.indexPath(for: cell),
			   let groupName = tableView(tableView, titleForHeaderInSection: indexPath.section),
			   groupName != ""
			{
				name = groupName + " - " + name
			}
			dest.navigationItem.title = name
		} else if let dest = segue.destination as? POIFeaturePickerViewController {
			dest.delegate = self
		}
	}

	func indexPathFor(key: String) -> IndexPath? {
		guard let allPresets = allPresets else { return nil }
		for (sectionIndex, presetGroup) in allPresets.sectionList.enumerated() {
			for (rowIndex, keyOrGroup) in presetGroup.presetKeys.enumerated() {
				guard case let .key(presetKey) = keyOrGroup else { continue }
				if presetKey.tagKey == key {
					return IndexPath(row: rowIndex, section: sectionIndex)
				}
			}
		}
		return nil
	}

	func bothKeyFor(preset: PresetKey) -> String? {
		if let index = preset.tagKey.lastIndex(of: ":") {
			return String(preset.tagKey[..<index]) + ":both"
		}
		return nil
	}

	// Update all values associated with a group that supports :both
	func setBothValuesFor(indexPath: IndexPath, value: String) -> Bool {
		guard let group = allPresets?.sectionList[indexPath.section],
		      group.usesBoth,
		      case let .key(presetKey) = group.presetKeys[indexPath.row],
		      let bothKey = bothKeyFor(preset: presetKey),
		      let tabController = tabBarController as? POITabBarController
		else {
			return false
		}

		// need to check if all cells will have the same value, and set :both if so
		let tagDict = tabController.keyValueDict
		let allSameValue = group.presetKeys.allSatisfy({
			if case let .key(key) = $0,
			   key === presetKey || tagDict[key.tagKey] == value
			{
				return true
			}
			return false
		})
		if allSameValue {
			// all values are equal, so remove all of them and set 'both' instead
			for case let .key(presetKey) in group.presetKeys {
				updateTagDictLow(withValue: "", forKey: presetKey.tagKey)
			}
			updateTagDictLow(withValue: value, forKey: bothKey)
		} else {
			// remove both: key
			updateTagDictLow(withValue: "", forKey: bothKey)
			// change other keys to :both value, if present
			if let bothValue = tagDict[bothKey] {
				for case let .key(presetKey) in group.presetKeys {
					updateTagDictLow(withValue: bothValue, forKey: presetKey.tagKey)
				}
			}
			// update user-selected key
			updateTagDictLow(withValue: value, forKey: presetKey.tagKey)
		}
		return true
	}

	@IBAction func cancel(_ sender: Any) {
		dismiss(animated: true)
	}

	@IBAction func done(_ sender: Any) {
		resignAll()
		dismiss(animated: true)

		let tabController = tabBarController as? POITabBarController
		tabController?.commitChanges()
	}

	// MARK: - Table view delegate

	override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
		if indexPath.section == 0, indexPath.row == 0 {
			// Feature type
			return false
		}
		if indexPath.section > (allPresets?.sectionCount() ?? 0) {
			// Customize button
			return false
		}
		return true
	}

	override func tableView(_ tableView: UITableView,
	                        commit editingStyle: UITableViewCell.EditingStyle,
	                        forRowAt indexPath: IndexPath)
	{
		if editingStyle == .delete {
			// user swiped to delete a cell
			if indexPath.section == allPresets?.sectionCount() {
				// Extra tags section
				updateTagDict(withValue: "", forKey: extraTags[indexPath.row].k)
				extraTags.remove(at: indexPath)
			} else {
				// for regular cells just set the value to ""
				let cell = tableView.cellForRow(at: indexPath)
				if let cell = cell as? FeaturePresetCell {
					cell.valueField.text = ""
					cell.isSet.backgroundColor = nil
					for preset in cell.presetKey?.flattenedPresets() ?? [] {
						updateTagDict(withValue: "", forKey: preset.tagKey)
					}
				} else if let cell = cell as? FeaturePresetAreaCell {
					cell.valueField.text = ""
					cell.isSet.backgroundColor = nil
					updateTagDict(withValue: "", forKey: cell.presetKey.tagKey)
				}
			}
		}
	}

	// MARK: - Text field functions

	func resignAll() {
		if tableView.window == nil {
			return
		}

		for cell in tableView.visibleCells {
			if let featureCell = cell as? FeaturePresetCell {
				featureCell.valueField?.resignFirstResponder()
			}
		}
	}

	@IBAction func textFieldReturn(_ sender: UITextField) {
		sender.resignFirstResponder()
	}

	@IBAction func textFieldEditingDidBegin(_ textField: AutocompleteTextField?) {
		if let textField = textField {
			// get list of values for current key
			let cell: FeaturePresetCell = textField.superviewOfType()!
			if case let .key(presetKey) = cell.presetKey {
				let key = presetKey.tagKey
				if PresetsDatabase.shared.eligibleForAutocomplete(key) {
					var values = AppDelegate.shared.mapView.editorLayer.mapData.tagValues(forKey: key)
					let values2 = presetKey.presetList?.map({ $0.tagValue }) ?? []
					values = values.union(values2)
					let list = [String](values)
					textField.autocompleteStrings = list
				}
				firstResponderTextField = textField
			}
		}
	}

	@IBAction func textFieldChanged(_ textField: UITextField) {
		saveButton.isEnabled = true
		if #available(iOS 13.0, *) {
			tabBarController?.isModalInPresentation = saveButton.isEnabled
		}
		if let cell: UITableViewCell = textField.superviewOfType() {
			switch cell {
			case let cell as FeaturePresetCell:
				cell.isSet.backgroundColor = cell.valueField.text == "" ? nil : Self.isSetHighlight
			case let cell as FeatureTypeCell:
				cell.isSet.backgroundColor = cell.valueField.text == "" ? nil : Self.isSetHighlight
			case let cell as FeaturePresetAreaCell:
				cell.isSet.backgroundColor = cell.valueField.text == "" ? nil : Self.isSetHighlight
			case let cell as TextPairTableCell:
				cell.isSet.backgroundColor = cell.text1.text == "" || cell.text2.text == ""
					? nil : Self.isSetHighlight
			default:
				break
			}
		}
	}

	@IBAction func textFieldDidEndEditing(_ textField: UITextField) {
		guard let cell: FeaturePresetCell = textField.superviewOfType(),
		      case let .key(presetKey) = cell.presetKey
		else { return }

		// convert to raw value if necessary
		let tagValue = presetKey.tagValueForPrettyName(textField.text ?? "")
		firstResponderTextField = nil
		updateTagDict(withValue: tagValue, forKey: presetKey.tagKey)
	}

	@objc func textField(_ textField: UITextField,
	                     shouldChangeCharactersIn remove: NSRange,
	                     replacementString insert: String) -> Bool
	{
		guard let origText = textField.text else { return false }
		return KeyValueTableCell.shouldChangeTag(origText: origText,
		                                         charactersIn: remove,
		                                         replacementString: insert,
		                                         warningVC: self)
	}

	// MARK: UITextView delegate

	func updateTextViewSize(_ textView: UITextView) {
		// This resizes the cell to be appropriate for the content
		UIView.setAnimationsEnabled(false)
		textView.sizeToFit()
		tableView.beginUpdates()
		tableView.endUpdates()
		UIView.setAnimationsEnabled(true)
	}

	func textViewDidBeginEditing(_ textView: UITextView) {
		if let cell: FeaturePresetAreaCell = textView.superviewOfType() {
			cell.removePlaceholderText()
		}
	}

	func textViewDidChange(_ textView: UITextView) {
		saveButton.isEnabled = true
		if #available(iOS 13.0, *) {
			tabBarController?.isModalInPresentation = saveButton.isEnabled
		}

		// This resizes the cell to be appropriate for the content
		updateTextViewSize(textView)
	}

	func textViewDidEndEditing(_ textView: UITextView) {
		guard let cell: FeaturePresetAreaCell = textView.superviewOfType()
		else { return }

		let value = textView.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
		textView.text = value
		textViewDidChange(textView)
		updateTagDict(withValue: value, forKey: cell.presetKey.tagKey)

		// fake placeholder text
		cell.addPlaceholderText()
	}

	func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
		if text == "\n" {
			textView.resignFirstResponder()
			return false
		}
		// use our update function that guarantees that values are less than 255 chars
		guard let origText = textView.text else { return false }
		return KeyValueTableCell.shouldChangeTag(origText: origText,
		                                         charactersIn: range,
		                                         replacementString: text,
		                                         warningVC: self)
	}

	// MARK: PresetValueTextFieldOwner

	var viewController: UIViewController? { self }

	func valueChanged(for textField: PresetValueTextField, ended: Bool) {
		guard ended else { return }
		guard let cell: FeaturePresetCell = textField.superviewOfType()
		else {
			return
		}
		let value = cell.valueField.text ?? ""

		if case let .key(presetKey) = cell.presetKey {
			// For PresetValueTextField cells this should always be true
			updateTagDict(withValue: value, forKey: presetKey.tagKey)
		}

		if value != "" {
			cell.isSet.backgroundColor = Self.isSetHighlight
		} else {
			cell.isSet.backgroundColor = nil
		}
	}

	// MARK: KeyValueTableCellOwner fields

	// These are needed to satisfy requirements as KeyValueTableCell owner
	var allPresetKeys: [PresetKey] { allPresets?.allPresetKeys() ?? [] }
	var childViewPresented = false
	var currentTextField: UITextField?

	func keyValueEditingChanged(for kv: KeyValueTableCell) {
		// doesn't matter whether key or value changed here:
		textFieldChanged(kv.text2)
	}

	func keyValueEditingEnded(for pair: KeyValueTableCell) {
		if let kv = extraTags.keyValueEditingEnded(for: pair) {
			if kv.k != pair.priorKeyValue {
				// delete value associated with previous key
				updateTagDict(withValue: "", forKey: pair.priorKeyValue)
			}
			updateTagDict(withValue: kv.v, forKey: kv.k)
		}
	}

	var keyValueDict: [String: String] {
		return (tabBarController as! POITabBarController).keyValueDict
	}
}
