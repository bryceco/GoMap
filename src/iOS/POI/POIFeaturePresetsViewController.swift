//
//  POIFeaturePresetsViewController.swift
//  Go Map!!
//
//  Copyright © 2021 Bryce Cogswell. All rights reserved.
//

import UIKit

class FeaturePresetCell: UITableViewCell {
	@IBOutlet var nameLabel: UILabel!
	@IBOutlet var valueField: AutocompleteTextField!
	@IBOutlet var isSet: UIView!
	var presetKey: PresetKeyOrGroup?
}

class FeaturePresetAreaCell: UITableViewCell {
	@IBOutlet var nameLabel: UILabel!
	@IBOutlet var valueField: UITextView!
	@IBOutlet var isSet: UIView!
	var presetKey: PresetKey!

	static let placeholderText = NSLocalizedString("Unknown", comment: "")
	static let placeholderColor: UIColor = {
		if #available(iOS 13.0, *) {
			return UIColor.placeholderText
		} else {
			return UIColor.lightText
		}
	}()

	static let regularColor: UIColor = {
		if #available(iOS 13.0, *) {
			return UIColor.label
		} else {
			return UIColor.black
		}
	}()

	static func addPlaceholderText(_ textView: UITextView) {
		if textView.text == "" {
			textView.textColor = Self.placeholderColor
			textView.text = Self.placeholderText
		}
	}

	static func removePlaceholderText(_ textView: UITextView) {
		if textView.text == Self.placeholderText, textView.textColor == Self.placeholderColor {
			textView.textColor = Self.regularColor
			textView.text = ""
		}
	}
}

class POIFeaturePresetsViewController: UITableViewController, UITextFieldDelegate, UITextViewDelegate,
	POIFeaturePickerViewControllerDelegate, KeyValueTableCellOwner
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
	private var extraTags: [(k: String, v: String)] = [] // array of key/values not covered by presets

	static let isSetHighlight = UIColor.systemBlue

	// These are needed to satisfy requirements as KeyValueTableCell owner
	var allPresetKeys: [PresetKey] { allPresets?.allPresetKeys() ?? [] }
	var childViewPresented = false
	var currentTextField: UITextField?
	func keyValueChanged(for kv: KeyValueTableCell) {
		updateTagDict(withValue: kv.value, forKey: kv.key)
		if kv.key != "", kv.value != "" {
			selectedFeature = nil
			updatePresets()
		} else {
			kv.isSet.backgroundColor = nil
		}
	}

	override func viewDidLoad() {
		// have to update presets before call super because super asks for the number of sections
		updatePresets()

		super.viewDidLoad()

		tableView.estimatedRowHeight = 44.0 // or could use UITableViewAutomaticDimension;
		tableView.rowHeight = UITableView.automaticDimension

		if drillDownGroup != nil {
			navigationItem.leftItemsSupplementBackButton = true
			navigationItem.leftBarButtonItem = nil
			navigationItem.title = drillDownGroup?.name ?? ""
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

	func updateTagDict(withValue value: String, forKey key: String) {
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
		#if false
		if let indexPath = indexPathForKey(key) {
			tableView.reloadRows(at: [indexPath], with: .none)
		}
		#endif
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
			let geometry = object?.geometry() ?? GEOMETRY.NODE

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
			presetKeys += feature.addTags().keys
		}
		let dict = (tabBarController as! POITabBarController).keyValueDict
		var extraKeys = Array(dict.keys)
		for key in presetKeys {
			extraKeys.removeAll(where: { $0 == key })
		}
		extraTags = extraKeys.sorted().map { ($0, dict[$0]!) }
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
					DispatchQueue.main.async(execute: {
						let index = IndexPath(row: 1, section: 0)
						if let cell = self.tableView.cellForRow(at: index) as? FeaturePresetCell,
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

	func typeViewController(_ typeViewController: POIFeaturePickerViewController,
	                        didChangeFeatureTo newFeature: PresetFeature)
	{
		selectedFeature = newFeature
		let tabController = tabBarController as! POITabBarController
		let geometry = tabController.selection?.geometry() ?? GEOMETRY.NODE
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
		if section == (allPresets?.sectionCount() ?? 0) {
			return nil // extra tags
		}
		if section > (allPresets?.sectionCount() ?? 0) {
			return nil // customize button
		}

		let group = allPresets?.sectionAtIndex(section)
		return group?.name
	}

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		if drillDownGroup != nil {
			return drillDownGroup?.presetKeys.count ?? 0
		}
		if section == (allPresets?.sectionCount() ?? 0) {
			return extraTags.count + 1 // tags plus an empty slot
		}
		if section > (allPresets?.sectionCount() ?? 0) {
			return 1 // customize button
		}
		return allPresets?.tagsInSection(section) ?? 0
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		if drillDownGroup == nil {
			// special case the key/value cells and the customize button
			if indexPath.section == allPresets?.sectionCount() {
				// extra tags
				let cell = tableView.dequeueReusableCell(
					withIdentifier: "KeyValueCell",
					for: indexPath) as! KeyValueTableCell
				cell.owner = self
				if indexPath.row < extraTags.count {
					cell.text1?.text = extraTags[indexPath.row].k
					cell.text2?.text = extraTags[indexPath.row].v
				} else {
					cell.text1?.text = ""
					cell.text2?.text = ""
				}
				cell.isSet.backgroundColor = cell.value == "" ? nil : Self.isSetHighlight
				cell.updateAssociatedContent()
				return cell
			}
			if indexPath.section > (allPresets?.sectionCount() ?? 0) {
				// customize button
				let cell = tableView.dequeueReusableCell(withIdentifier: "CustomizePresets", for: indexPath)
				return cell
			}
		}

		let tabController = tabBarController as! POITabBarController
		let keyValueDict = tabController.keyValueDict

		let rowObject = (drillDownGroup != nil) ? drillDownGroup!.presetKeys[indexPath.row]
			: allPresets!.presetAtIndexPath(indexPath)

		switch rowObject {
		case let PresetKeyOrGroup.key(presetKey):
			let key = presetKey.tagKey

			if presetKey.type == "textarea" {
				// special case for keys that contain large amounts of text
				let cell = tableView.dequeueReusableCell(
					withIdentifier: "CommonTagArea",
					for: indexPath) as! FeaturePresetAreaCell
				cell.valueField.delegate = self
				let value = keyValueDict[presetKey.tagKey] ?? ""
				cell.isSet.backgroundColor = value == "" ? nil : Self.isSetHighlight
				cell.valueField.text = value
				cell.valueField.returnKeyType = .done
				cell.accessoryType = .none
				cell.nameLabel.text = presetKey.name
				cell.presetKey = presetKey
				if value != "" {
					// This shouldn't be necessary but the cell height isn't correct
					// when the cell first appears.
					DispatchQueue.main.asyncAfter(deadline: .now() + 0.01, execute: {
						self.updateTextViewSize(cell.valueField)
					})
				} else {
					FeaturePresetAreaCell.addPlaceholderText(cell.valueField)
				}
				return cell
			}

			let cellName = key == "" ? "CommonTagType"
				: key == "name" ? "CommonTagName"
				: "CommonTagSingle"

			let cell = tableView.dequeueReusableCell(withIdentifier: cellName, for: indexPath) as! FeaturePresetCell
			if key != "" {
				cell.nameLabel.text = presetKey.name
				cell.valueField.placeholder = presetKey.placeholder
			}
			cell.valueField.delegate = self
			cell.presetKey = .key(presetKey)

			cell.valueField.keyboardType = presetKey.keyboardType
			cell.valueField.autocapitalizationType = presetKey.autocapitalizationType

			cell.valueField.removeTarget(self, action: nil, for: .allEvents)
			cell.valueField.addTarget(self, action: #selector(textFieldReturn(_:)), for: .editingDidEndOnExit)
			cell.valueField.addTarget(self, action: #selector(textFieldChanged(_:)), for: .editingChanged)
			cell.valueField.addTarget(self, action: #selector(textFieldEditingDidBegin(_:)), for: .editingDidBegin)
			cell.valueField.addTarget(
				self,
				action: #selector(UITextFieldDelegate.textFieldDidEndEditing(_:)),
				for: .editingDidEnd)

			cell.isSet.backgroundColor = keyValueDict[presetKey.tagKey] == nil ? nil : Self.isSetHighlight

			cell.valueField.rightView = nil

			if presetKey.isYesNo() {
				cell.accessoryType = UITableViewCell.AccessoryType.none
			} else if (presetKey.presetList?.count ?? 0) > 0 || key.count == 0 {
				// The user can select from a list of presets.
				cell.accessoryType = UITableViewCell.AccessoryType.disclosureIndicator
			} else if canMeasureDirection(for: presetKey) {
				cell.accessoryType = UITableViewCell.AccessoryType.disclosureIndicator
			} else if canMeasureHeight(for: presetKey) {
				cell.accessoryType = UITableViewCell.AccessoryType.disclosureIndicator
			} else {
				cell.accessoryType = UITableViewCell.AccessoryType.none
			}

			if drillDownGroup == nil, indexPath.section == 0, indexPath.row == 0 {
				// Feature type cell
				let text = allPresets?.featureName() ?? ""
				cell.valueField.text = text
				cell.valueField.isEnabled = false
				cell.isSet.backgroundColor = (selectedFeature?.addTags().count ?? 0) > 0 ? Self.isSetHighlight : nil
			} else if presetKey.isYesNo() {
				// special case for yes/no tristate
				let button = TristateYesNoButton()
				var value = keyValueDict[presetKey.tagKey] ?? ""
				if presetKey.tagKey == "tunnel", keyValueDict["waterway"] != nil, value == "culvert" {
					// Special hack for tunnel=culvert when used with waterways:
					value = "yes"
				}
				button.setSelection(forString: value)
				if button.stringForSelection() == nil {
					// display the string iff we don't recognize it (or it's nil)
					cell.valueField.text = presetKey.prettyNameForTagValue(value)
				} else {
					cell.valueField.text = nil
				}
				cell.valueField.isEnabled = true
				cell.valueField.rightView = button
				cell.valueField.rightViewMode = .always
				cell.valueField.placeholder = nil
				button.onSelect = { newValue in
					var newValue = newValue
					if presetKey.tagKey == "tunnel", keyValueDict["waterway"] != nil {
						// Special hack for tunnel=culvert when used with waterways:
						// See https://github.com/openstreetmap/iD/blob/1ee45ee1f03f0fe4d452012c65ac6ff7649e229f/modules/ui/fields/radio.js#L307
						if newValue == "yes" {
							newValue = "culvert"
						} else {
							newValue = nil // "no" isn't allowed
						}
					}
					self.updateTagDict(withValue: newValue ?? "", forKey: presetKey.tagKey)
					cell.valueField.text = nil
					cell.valueField.resignFirstResponder()
					cell.isSet.backgroundColor = newValue == nil ? nil : Self.isSetHighlight
				}
			} else {
				// Regular cell
				let value = presetKey.prettyNameForTagValue(keyValueDict[presetKey.tagKey] ?? "")
				cell.valueField.text = value
				cell.valueField.isEnabled = true

				if presetKey.type == "roadspeed" {
					let button = KmhMphToggle()
					cell.valueField.rightView = button
					cell.valueField.rightViewMode = .always
					button.onSelect = { newValue in
						// update units on existing value
						if let number = cell.valueField.text?.prefix(while: { $0.isNumber || $0 == "." }),
						   number != ""
						{
							let v = newValue == nil ? String(number) : number + " " + newValue!
							self.updateTagDict(withValue: v, forKey: presetKey.tagKey)
							cell.valueField.text = v
						} else {
							button.setSelection(forString: "")
						}
					}
					button.setSelection(forString: value)
				}
			}
			return cell

		case let PresetKeyOrGroup.group(drillDownGroup):

			// drill down cell
			let cell = tableView.dequeueReusableCell(
				withIdentifier: "CommonTagSingle",
				for: indexPath) as! FeaturePresetCell
			cell.nameLabel.text = drillDownGroup.name
			cell.valueField.text = drillDownGroup.multiComboSummary(ofDict: keyValueDict, isPlaceholder: false)
			cell.valueField.placeholder = drillDownGroup.multiComboSummary(ofDict: nil, isPlaceholder: true)
			cell.valueField.isEnabled = false
			cell.valueField.rightView = nil
			cell.presetKey = .group(drillDownGroup)
			cell.accessoryType = UITableViewCell.AccessoryType.disclosureIndicator
			cell.isSet.backgroundColor = cell.valueField.text == "" ? nil : Self.isSetHighlight

			return cell
		}
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		guard let cell = tableView.cellForRow(at: indexPath) as? FeaturePresetCell,
		      cell.accessoryType != .none
		else { return }

		if drillDownGroup == nil, indexPath.section == 0, indexPath.row == 0 {
			performSegue(withIdentifier: "POITypeSegue", sender: cell)
		} else if case let .group(group) = cell.presetKey {
			// special case for drill down
			let sub = storyboard?
				.instantiateViewController(
					withIdentifier: "PoiCommonTagsViewController") as! POIFeaturePresetsViewController
			sub.drillDownGroup = group
			navigationController?.pushViewController(sub, animated: true)
		} else if case let .key(presetKey) = cell.presetKey,
		          canMeasureDirection(for: presetKey)
		{
			self.measureDirection(forKey: presetKey.tagKey,
			                      value: cell.valueField.text ?? "")
		} else if case let .key(presetKey) = cell.presetKey,
		          canMeasureHeight(for: presetKey)
		{
			measureHeight(forKey: presetKey.tagKey)
		} else if case let .key(presetKey) = cell.presetKey,
		          canRecognizeOpeningHours(for: presetKey)
		{
			recognizeOpeningHours(forKey: presetKey.tagKey)
		} else {
			performSegue(withIdentifier: "POIPresetSegue", sender: cell)
		}
	}

	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		let cell = sender as? FeaturePresetCell
		if let dest = segue.destination as? POIPresetValuePickerController {
			if case let .key(presetKey) = cell?.presetKey {
				dest.key = presetKey.tagKey
				dest.valueDefinitions = presetKey.presetList ?? []
				dest.onSetValue = {
					self.updateTagDict(withValue: $0, forKey: presetKey.tagKey)
				}
				dest.navigationItem.title = presetKey.name
			}
		} else if let dest = segue.destination as? POIFeaturePickerViewController {
			dest.delegate = self
		}
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
				if indexPath.row < extraTags.count {
					let kv = extraTags[indexPath.row]
					extraTags.remove(at: indexPath.row)
					updateTagDict(withValue: "", forKey: kv.k)
					tableView.deleteRows(at: [indexPath], with: .fade)
				} else {
					// it's the last row, which is the empty row, so fake it
					if let kv = tableView.cellForRow(at: indexPath) as? KeyValueTableCell {
						kv.text1.text = ""
						kv.text2.text = ""
					}
				}
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

	@objc func setCallingCodeText(_ sender: Any?) {
		if let text = firstResponderTextField?.text,
		   !text.hasPrefix("+")
		{
			let code = AppDelegate.shared.mapView.currentRegion.callingCode() ?? ""
			firstResponderTextField?.text = "+" + code + " " + text
		}
	}

	@objc func insertSpace(_ sender: Any?) {
		firstResponderTextField?.insertText(" ")
	}

	@objc func insertDash(_ sender: Any?) {
		firstResponderTextField?.insertText("-")
	}

	@objc func phonePadDone(_ sender: Any?) {
		firstResponderTextField?.resignFirstResponder()
	}

	func addTelephoneToolbarToKeyboard(for textField: UITextField) {
		let toolbar = UIToolbar(frame: CGRect(x: 0, y: 0, width: view.frame.size.width, height: 44))
		toolbar.items = [
			UIBarButtonItem(
				title: "+1",
				style: .plain,
				target: self,
				action: #selector(setCallingCodeText(_:))),
			UIBarButtonItem(
				title: NSLocalizedString("Space", comment: "Space key on the keyboard"),
				style: .plain,
				target: self,
				action: #selector(insertSpace(_:))),
			UIBarButtonItem(
				title: "-",
				style: .plain,
				target: self,
				action: #selector(insertDash(_:))),
			UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: self, action: nil),
			UIBarButtonItem(barButtonSystemItem: .done,
			                target: self,
			                action: #selector(phonePadDone(_:)))
		]
		textField.inputAccessoryView = toolbar
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
				if presetKey.keyboardType == .phonePad {
					addTelephoneToolbarToKeyboard(for: textField)
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
		if let cell: FeaturePresetCell = textField.superviewOfType() {
			cell.isSet.backgroundColor = cell.valueField.text == "" ? nil : Self.isSetHighlight
		}
	}

	@IBAction func textFieldDidEndEditing(_ textField: UITextField) {
		guard let cell: FeaturePresetCell = textField.superviewOfType(),
		      case let .key(presetKey) = cell.presetKey
		else { return }

		let prettyValue = textField.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
		textField.text = prettyValue

		// convert to raw value if necessary
		let tagValue = presetKey.tagValueForPrettyName(prettyValue)
		firstResponderTextField = nil
		updateTagDict(withValue: tagValue, forKey: presetKey.tagKey)

		// do automatic value updates for special keys
		if tagValue.count > 0,
		   let newValue = OsmTags.convertWikiUrlToReference(withKey: presetKey.tagKey, value: tagValue)
		   ?? OsmTags.convertWebsiteValueToHttps(withKey: presetKey.tagKey, value: tagValue)
		{
			textField.text = newValue
		}

		if let tri = cell.valueField.rightView as? TristateYesNoButton {
			tri.setSelection(forString: textField.text ?? "")
		}
		if let tri = cell.valueField.rightView as? KmhMphToggle {
			tri.setSelection(forString: textField.text ?? "")
		}
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
		FeaturePresetAreaCell.removePlaceholderText(textView)
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
		FeaturePresetAreaCell.addPlaceholderText(textView)
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

	// MARK: utility functions

	/**
	 Determines whether the `DirectionViewController` can be used to measure the value for the tag with the given key.

	 @param key The key of the tag that should be measured.
	 @return YES if the key can be measured using the `DirectionViewController`, NO if not.
	 */
	func canMeasureDirection(for key: PresetKey) -> Bool {
		if (key.presetList?.count ?? 0) > 0 {
			return false
		}
		let keys = ["direction", "camera:direction"]
		if keys.contains(key.tagKey) {
			return true
		}
		return false
	}

	func measureDirection(forKey key: String, value: String) {
		let directionViewController = DirectionViewController(
			key: key,
			value: value,
			setValue: { newValue in
				self.updateTagDict(withValue: newValue, forKey: key)
			})
		navigationController?.pushViewController(directionViewController, animated: true)
	}

	func canMeasureHeight(for key: PresetKey) -> Bool {
		return key.presetList?.count == 0 && (key.tagKey == "height")
	}

	func measureHeight(forKey key: String) {
		if HeightViewController.unableToInstantiate(withUserWarning: self) {
			return
		}
		let vc = HeightViewController.instantiate()
		vc.callback = { newValue in
			self.updateTagDict(withValue: newValue, forKey: key)
		}
		navigationController?.pushViewController(vc, animated: true)
	}

	func canRecognizeOpeningHours(for key: PresetKey) -> Bool {
#if !targetEnvironment(macCatalyst)
#if arch(arm64) || arch(x86_64) // old architectures don't support SwiftUI
		if #available(iOS 14.0, *) {
			return key.tagKey == "opening_hours" || key.tagKey.hasSuffix(":opening_hours")
		}
#endif
#endif
		return false
	}

	func recognizeOpeningHours(forKey key: String) {
#if !targetEnvironment(macCatalyst)
#if arch(arm64) || arch(x86_64) // old architectures don't support SwiftUI
		if #available(iOS 14.0, *) {
			let feedback = UINotificationFeedbackGenerator()
			feedback.prepare()
			let vc = OpeningHoursRecognizerController.with(onAccept: { newValue in
				self.updateTagDict(withValue: newValue, forKey: key)
				self.navigationController?.popViewController(animated: true)
			}, onCancel: {
				self.navigationController?.popViewController(animated: true)
			}, onRecognize: { _ in
				feedback.notificationOccurred(.success)
				feedback.prepare()
			})
			self.navigationController?.pushViewController(vc, animated: true)
		}
#endif
#endif
	}
}
