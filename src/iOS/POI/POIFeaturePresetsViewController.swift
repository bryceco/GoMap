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
	var presetKey: PresetKeyOrGroup?
}

class POIFeaturePresetsViewController: UITableViewController, UITextFieldDelegate, POITypeViewControllerDelegate {
	@IBOutlet var saveButton: UIBarButtonItem!

	private var allPresets: PresetsForFeature?
	private var selectedFeature: PresetFeature? // the feature selected by the user, not derived from tags (e.g. Address)
	private var childPushed = false
	private var drillDownGroup: PresetGroup?
	private var textFieldIsEditing = false

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
			let feature = selectedFeature ?? PresetsDatabase.shared.matchObjectTagsToFeature(
				dict,
				geometry: geometry,
				includeNSI: true)
			if let feature = feature {
				POIFeaturePickerViewController.loadMostRecent(forGeometry: geometry)
				POIFeaturePickerViewController.updateMostRecentArray(withSelection: feature, geometry: geometry)
			}

			weak var weakself = self
			allPresets = PresetsForFeature(withFeature: feature, objectTags: dict, geometry: geometry, update: {
				// this may complete much later, even after we've been dismissed
				if let weakself = weakself,
				   !weakself.isEditing
				{
					weakself.allPresets = PresetsForFeature(
						withFeature: feature,
						objectTags: dict,
						geometry: geometry,
						update: nil)
					weakself.tableView.reloadData()
				}
			})
		}

		tableView.reloadData()
	}

	// MARK: display

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)

		if isMovingToParent {
		} else {
			updatePresets()
		}
	}

	override func viewWillDisappear(_ animated: Bool) {
		resignAll()
		super.viewWillDisappear(animated)
		selectedFeature = nil
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

			} else if !childPushed, (tabController.selection?.ident ?? 0) <= 0, tabController.keyValueDict.count == 0 {
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
		tabController.keyValueDict = newFeature.objectTagsUpdatedForFeature(tabController.keyValueDict,
		                                                                    geometry: geometry)
	}

	// MARK: - Table view data source

	override func numberOfSections(in tableView: UITableView) -> Int {
		return (drillDownGroup != nil) ? 1 : (allPresets?.sectionCount() ?? 0) + 1
	}

	override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		if drillDownGroup != nil {
			return drillDownGroup?.name
		}
		if section == (allPresets?.sectionCount() ?? 0) {
			return nil
		}
		if section > (allPresets?.sectionCount() ?? 0) {
			return nil
		}

		let group = allPresets?.sectionAtIndex(section)
		return group?.name
	}

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		if drillDownGroup != nil {
			return drillDownGroup?.presetKeys.count ?? 0
		}
		if section == (allPresets?.sectionCount() ?? 0) {
			return 1
		}
		if section > (allPresets?.sectionCount() ?? 0) {
			return 0
		}
		return allPresets?.tagsInSection(section) ?? 0
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		if drillDownGroup == nil {
			if indexPath.section == allPresets?.sectionCount() {
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
				// Type cell
				let text = allPresets?.featureName() ?? ""
				cell.valueField.text = text
				cell.valueField.isEnabled = false
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
					self.updateTag(withValue: newValue ?? "", forKey: presetKey.tagKey)
					cell.valueField.text = nil
					cell.valueField.resignFirstResponder()
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
							self.updateTag(withValue: v, forKey: presetKey.tagKey)
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
				dest.tag = presetKey.tagKey
				dest.valueDefinitions = presetKey.presetList
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
				textFieldIsEditing = true
			}
		}
	}

	@IBAction func textFieldChanged(_ textField: UITextField) {
		saveButton.isEnabled = true
		if #available(iOS 13.0, *) {
			tabBarController?.isModalInPresentation = saveButton.isEnabled
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
		textFieldIsEditing = false
		updateTag(withValue: tagValue, forKey: presetKey.tagKey)

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

	func updateTag(withValue value: String, forKey key: String) {
		guard let tabController = tabBarController as? POITabBarController else {
			// This shouldn't happen, but there are crashes here
			// originating from textFieldDidEndEditing(). Maybe
			// when closing the modal somehow?
			return
		}

		if value.count != 0 {
			tabController.keyValueDict[key] = value
		} else {
			tabController.keyValueDict.removeValue(forKey: key)
		}

		saveButton.isEnabled = tabController.isTagDictChanged()
		if #available(iOS 13.0, *) {
			tabController.isModalInPresentation = saveButton.isEnabled
		}
	}

	@objc func textField(_ textField: UITextField,
	                     shouldChangeCharactersIn remove: NSRange,
	                     replacementString insert: String) -> Bool
	{
		guard let origText = textField.text else { return false }
		return POIAllTagsViewController.shouldChangeTag(origText: origText,
		                                                charactersIn: remove,
		                                                replacementString: insert,
		                                                warningVC: self)
	}

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
				self.updateTag(withValue: newValue ?? "", forKey: key)
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
			self.updateTag(withValue: newValue, forKey: key)
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
				self.updateTag(withValue: newValue, forKey: key)
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
