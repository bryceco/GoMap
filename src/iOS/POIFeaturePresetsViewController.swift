//
//  POIFeaturePresetsViewController.swift
//  Go Map!!
//
//  Created by Ibrahim Hassan on 17/03/21.
//  Copyright © 2021 Bryce. All rights reserved.
//

class FeaturePresetCell: UITableViewCell {
    @IBOutlet var nameLabel: UILabel!
    @IBOutlet var valueField: AutocompleteTextField!
    var presetKey: AnyObject?
}

class POIFeaturePresetsViewController: UITableViewController, UITextFieldDelegate, POITypeViewControllerDelegate {
    var allPresets: PresetsForFeature?
    @IBOutlet var _saveButton: UIBarButtonItem!
    var selectedFeature: PresetFeature? // the feature selected by the user, not derived from tags (e.g. Address)
    var childPushed = false

    var drillDownGroup: PresetGroup?
    
    override func viewDidLoad() {
        // have to update presets before call super because super asks for the number of sections
        updatePresets()
    
        super.viewDidLoad()
    
        tableView.estimatedRowHeight = 44.0 // or could use UITableViewAutomaticDimension;
        tableView.rowHeight = UITableView.automaticDimension
    
        if (drillDownGroup != nil) {
            navigationItem.leftItemsSupplementBackButton = true
            navigationItem.leftBarButtonItem = nil
            navigationItem.title = drillDownGroup?.name ?? ""
        }
    }
    
    func updatePresets() {
        let tabController = tabBarController as? POITabBarController
    
        _saveButton.isEnabled = ((tabController?.isTagDictChanged()) != nil)
        if #available(iOS 13.0, *) {
            tabBarController?.isModalInPresentation = _saveButton.isEnabled
        }
    
        if drillDownGroup == nil {
    
            let dict = tabController?.keyValueDict ?? [:]
            let object = tabController?.selection
            let geometry: String = object?.geometryName() ?? GEOMETRY_NODE
//            let geometry: String = (object != nil) ? object?.geometryName() : GEOMETRY_NODE
    
            // update most recent feature
            let feature = selectedFeature ?? PresetsDatabase.shared.matchObjectTagsToFeature(dict, geometry: geometry, includeNSI: true)
            if let feature = feature {
                POIFeaturePickerViewController.loadMostRecent(forGeometry: geometry)
                POIFeaturePickerViewController.updateMostRecentArray(withSelection: feature, geometry: geometry)
            }
        
            allPresets = PresetsForFeature(withFeature: feature, objectTags: dict, geometry: geometry, update: { [weak self] in
                // this may complete much later, even after we've been dismissed
                if self != nil && self?.isEditing == nil {
                    self?.allPresets = PresetsForFeature(withFeature: feature, objectTags: dict, geometry: geometry, update: nil)
                    self?.tableView.reloadData()
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
                if dict.count == 1 && (dict["shop"] != nil || dict["amenity"] != nil) && dict["name"] == nil {
					// find name field and make it first responder
                    DispatchQueue.main.async(execute: {
                        let index = IndexPath(row: 1, section: 0)
                        let cell = self.tableView.cellForRow(at: index) as? FeaturePresetCell
                        if cell != nil && (cell?.presetKey?.tagKey == "name") {
                            cell?.valueField.becomeFirstResponder()
                        }
                    })
                }
			} else if !childPushed && (tabController.selection?.ident ?? 0) <= 0 && tabController.keyValueDict.count == 0 {
				// if we're being displayed for a newly created node then go straight to the Type picker
				performSegue(withIdentifier: "POITypeSegue", sender: nil)
			}
        }
    }
    
    @objc func typeViewController(_ typeViewController: POIFeaturePickerViewController?, didChangeFeatureTo newFeature: PresetFeature?) {
        selectedFeature = newFeature
        let tabController = tabBarController as! POITabBarController
        let geometry = tabController.selection != nil ? tabController.selection?.geometryName() : GEOMETRY_NODE
        
        let oldFeature = PresetsDatabase.shared.matchObjectTagsToFeature(tabController.keyValueDict, geometry: geometry!, includeNSI: true)
    
        // remove previous feature tags
        var removeTags = oldFeature?.removeTags()
        if let addTags = newFeature?.addTags() {
            for key in addTags.keys {
                removeTags?.removeValue(forKey: key)
            }
        }
        for (key, value) in removeTags ?? [:] {
            tabController.setFeatureKey(key, value: value)
        }
        
        // add new feature tags
        for (key, value) in newFeature?.addTags() ?? [:] {
            if value == "*" {
                if !tabController.keyValueDict.keys.contains(key) {
                    tabController.setFeatureKey(key, value: "yes")
                } else {
                    // already has a value
                }
            } else {
                tabController.setFeatureKey(key, value: value)
            }
        }
        
    
        // add default values of new feature fields
        let defaults = newFeature?.defaultValuesForGeometry(geometry!) ?? [:]
        for (key, value) in defaults {
            if !tabController.keyValueDict.keys.contains(key) {
                tabController.setFeatureKey(key, value: value)
            }
        }
    }
    
    // MARK: - Table view data source
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return (drillDownGroup != nil) ? 1 : allPresets?.sectionCount() ?? 0 + 1
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if (drillDownGroup != nil) {
            return drillDownGroup?.name
        }
        if section == (allPresets?.sectionCount() ?? 0) {
            return nil
        }
        if section > (allPresets?.sectionCount() ?? 0) {
            return nil
        }
        
        let group = allPresets?.groupAtIndex(section)
        return group?.name
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if (drillDownGroup != nil) {
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
        if self.drillDownGroup == nil {
            if indexPath.section == allPresets?.sectionCount() {
                let cell = tableView.dequeueReusableCell(withIdentifier: "CustomizePresets", for: indexPath)
                return cell
            }
        }
    
        let tabController = tabBarController as? POITabBarController
        let keyValueDict = tabController?.keyValueDict
        
        let rowObject = (self.drillDownGroup != nil) ? self.drillDownGroup?.presetKeys[indexPath.row] : allPresets?.presetAtIndexPath(indexPath)
        
        if rowObject is PresetKey {
            let presetKey = rowObject as? PresetKey
            let key = presetKey?.tagKey ?? ""
            let cellName = key.count == 0
                ? "CommonTagType"
                : (key == "name")
                    ? "CommonTagName"
                    : "CommonTagSingle"
    
            let cell = tableView.dequeueReusableCell(withIdentifier: cellName, for: indexPath) as? FeaturePresetCell
            cell?.nameLabel.text = presetKey?.name
            cell?.valueField.placeholder = presetKey?.placeholder
            cell?.valueField.delegate = self
            cell?.presetKey = presetKey
    
            if let keyboardType = presetKey?.keyboardType {
                cell?.valueField.keyboardType = keyboardType
            }
            if let autocapitalizationType = presetKey?.autocapitalizationType {
                cell?.valueField.autocapitalizationType = autocapitalizationType
            }
    
            cell?.valueField.removeTarget(self, action: nil, for: .allEvents)
            cell?.valueField.addTarget(self, action: #selector(textFieldReturn(_:)), for: .editingDidEndOnExit)
            cell?.valueField.addTarget(self, action: #selector(textFieldChanged(_:)), for: .editingChanged)
            cell?.valueField.addTarget(self, action: #selector(textFieldEditingDidBegin(_:)), for: .editingDidBegin)
            cell?.valueField.addTarget(self, action: #selector(UITextFieldDelegate.textFieldDidEndEditing(_:)), for: .editingDidEnd)
    
            cell?.valueField.rightView = nil
    
            if presetKey?.isYesNo != nil {
                cell?.accessoryType = UITableViewCell.AccessoryType.none
            } else if (presetKey?.presetList?.count ?? 0) > 0 || key.count == 0 {
                // The user can select from a list of presets.
                cell?.accessoryType = UITableViewCell.AccessoryType.disclosureIndicator
            } else if canMeasureDirection(for: presetKey) {
                cell?.accessoryType = UITableViewCell.AccessoryType.disclosureIndicator
            } else if canMeasureHeight(for: presetKey) {
                cell?.accessoryType = UITableViewCell.AccessoryType.disclosureIndicator
            } else {
                cell?.accessoryType = UITableViewCell.AccessoryType.none
            }
    
            if self.drillDownGroup == nil && indexPath.section == 0 && indexPath.row == 0 {
                // Type cell
                let text = allPresets?.featureName() ?? ""
                cell?.valueField.text = text
                cell?.valueField.isEnabled = false
            } else if presetKey?.isYesNo != nil {
                // special case for yes/no tristate
                let button = TristateButton()
                var value: String? = nil
                if let tagKey = presetKey?.tagKey {
                    value = keyValueDict?[tagKey]
                }
                button.setSelection(forString: value ?? "")
                if button.stringForSelection() == nil {
                    // display the string iff we don't recognize it (or it's nil)
                    cell?.valueField.text = presetKey?.prettyNameForTagValue(value ?? "")
                } else {
                    cell?.valueField.text = nil
                }
                cell?.valueField.isEnabled = true
                cell?.valueField.rightView = button
                cell?.valueField.rightViewMode = .always
                cell?.valueField.placeholder = nil
                button.onSelect = { newValue in
                    self.updateTag(withValue: newValue ?? "", forKey: cell?.presetKey?.tagKey ?? "")
                    cell?.valueField.text = nil
                    cell?.valueField.resignFirstResponder()
                }
            } else {
                // Regular cell
                var value: String? = nil
                if let tagKey = presetKey?.tagKey {
                    value = keyValueDict?[tagKey]
                }
                value = presetKey?.prettyNameForTagValue(value ?? "")
                cell?.valueField.text = value
                cell?.valueField.isEnabled = true
            }
    
            return cell!
        } else {
    
            // drill down cell
            let drillDownGroup = rowObject as? PresetGroup
            let cell = tableView.dequeueReusableCell(withIdentifier: "CommonTagSingle", for: indexPath) as? FeaturePresetCell
            cell?.nameLabel.text = drillDownGroup?.name
            cell?.valueField.text = drillDownGroup?.multiComboSummary(ofDict: keyValueDict, isPlaceholder: false)
            cell?.valueField.placeholder = drillDownGroup?.multiComboSummary(ofDict: nil, isPlaceholder: true)
            cell?.valueField.isEnabled = false
            cell?.valueField.rightView = nil
            cell?.presetKey = drillDownGroup
            cell?.accessoryType = UITableViewCell.AccessoryType.disclosureIndicator
    
            return cell!
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let cell = tableView.cellForRow(at: indexPath) as? FeaturePresetCell
        if cell?.accessoryType == UITableViewCell.AccessoryType.none {
            return
        }
    
        // This workaround is necessary because `tableView:cellForRowAtIndexPath:`
        // currently sets `cell.commonPreset` to an instance of `CommonPresetGroup` by casting it to `id`.
        var presetKey: PresetKey? = nil
        if let cell_presetKey = cell?.presetKey as? PresetKey {
            presetKey = cell_presetKey
        }
    
        if drillDownGroup == nil && indexPath.section == 0 && indexPath.row == 0 {
            performSegue(withIdentifier: "POITypeSegue", sender: cell)
        } else if cell?.presetKey is PresetGroup {
            // special case for drill down
            let group = cell?.presetKey as? PresetGroup
            let sub = storyboard?.instantiateViewController(withIdentifier: "PoiCommonTagsViewController") as? POIFeaturePresetsViewController
            sub?.drillDownGroup = group
            if let sub = sub {
                navigationController?.pushViewController(sub, animated: true)
            }
        } else if canMeasureDirection(for: presetKey) {
            self.measureDirection(forKey: cell?.presetKey?.tagKey ?? "",
                                  value: cell?.valueField.text ?? "")
        } else if canMeasureHeight(for: presetKey) {
            measureHeight(forKey: cell?.presetKey?.tagKey)
        } else {
            performSegue(withIdentifier: "POIPresetSegue", sender: cell)
        }
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        let cell = sender as? FeaturePresetCell
        if segue.destination is POIPresetValuePickerController {
            let preset = segue.destination as? POIPresetValuePickerController
            preset?.tag = cell?.presetKey?.tagKey ?? ""
            preset?.valueDefinitions = cell?.presetKey?.presetList
            preset?.navigationItem.title = cell?.presetKey?.name
        } else if segue.destination is POIFeaturePickerViewController {
            let dest = segue.destination as? POIFeaturePickerViewController
            dest?.delegate = self
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
        if self.tableView.window == nil {
            return
        }
        
        for cell in self.tableView.visibleCells {
            if let featureCell = cell as? FeaturePresetCell {
                featureCell.valueField.resignFirstResponder()
            }
        }
    }
    
    @IBAction func textFieldReturn(_ sender: UITextField) {
        sender.resignFirstResponder()
    }
    
    func cell(for textField: UITextField) -> FeaturePresetCell? {
        var cell: UIView? = textField
        while (cell != nil) && !(cell is FeaturePresetCell) {
            cell = cell?.superview
        }
        return cell as? FeaturePresetCell
    }
    
    @IBAction func textFieldEditingDidBegin(_ textField: AutocompleteTextField?) {
        if let textField = textField {
            // get list of values for current key
            let cell = self.cell(for: textField)
            if let key = cell?.presetKey?.tagKey {
                if PresetsDatabase.shared.eligibleForAutocomplete(key) {
                    let set = PresetsDatabase.shared.allTagValuesForKey(key)
                    let appDelegate = AppDelegate.shared
                    let values = appDelegate?.mapView?.editorLayer.mapData.tagValues(forKey: key)
                    values?.addObjects(from: Array.init(arrayLiteral: set))
                    let list = values?.allObjects as? [String]
                    textField.autocompleteStrings = list
                }
                isEditing = true
            }
        }
    }
    
    @IBAction func textFieldChanged(_ textField: UITextField?) {
        _saveButton.isEnabled = true
        if #available(iOS 13.0, *) {
            tabBarController?.isModalInPresentation = _saveButton.isEnabled
        }
    }
    
    @IBAction func textFieldDidEndEditing(_ textField: UITextField) {
        let cell = self.cell(for: textField)
        let key = cell?.presetKey?.tagKey ?? ""
        if key == "" {
            return // should never happen
        }
    
        var prettyValue = textField.text
        prettyValue = prettyValue?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        textField.text = prettyValue
    
        // convert to raw value if necessary
        let tagValue = cell?.presetKey?.tagValueForPrettyName(prettyValue ?? "") ?? ""
        isEditing = false
        updateTag(withValue: tagValue, forKey: key)
        
        if (cell?.presetKey?.isYesNo() ?? false) {
            let tri = cell?.valueField.rightView as? TristateButton
            tri?.setSelection(forString: textField.text ?? "")
        }
    }
    
    func updateTag(withValue value: String, forKey key: String) {
        let tabController = tabBarController as? POITabBarController
    
        if (value.count) != 0 {
            tabController?.keyValueDict[key] = value
        } else {
            tabController?.keyValueDict.removeValue(forKey: key)
        }
    
        _saveButton.isEnabled = (tabController?.isTagDictChanged() ?? false)
        if #available(iOS 13.0, *) {
            tabBarController?.isModalInPresentation = _saveButton.isEnabled
        }
    }
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        let MAX_LENGTH = 255
        let oldLength = textField.text?.count ?? 0
        let replacementLength = string.count
        let rangeLength = range.length
        let newLength = oldLength - rangeLength + replacementLength
        let returnKey = (string as NSString).range(of: "\n").location != NSNotFound
        return newLength <= MAX_LENGTH || returnKey
    }
    
    /**
     Determines whether the `DirectionViewController` can be used to measure the value for the tag with the given key.
     
     @param key The key of the tag that should be measured.
     @return YES if the key can be measured using the `DirectionViewController`, NO if not.
     */
    func canMeasureDirection(for key: PresetKey?) -> Bool {
        if (key?.presetList?.count ?? 0) > 0 {
            return false
        }
        let keys = ["direction", "camera:direction"]
        if keys.contains(key?.tagKey ?? "") {
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
    
    func canMeasureHeight(for key: PresetKey?) -> Bool {
        return key?.presetList?.count == 0 && (key?.tagKey == "height")
    }
    
    func measureHeight(forKey key: String?) {
        if HeightViewController.unableToInstantiate(withUserWarning: self) {
            return
        }
        let vc = HeightViewController.instantiate()
        vc.callback = { newValue in
            self.updateTag(withValue: newValue ?? "", forKey: key ?? "")
        }
        navigationController?.pushViewController(vc, animated: true)
    }
}
