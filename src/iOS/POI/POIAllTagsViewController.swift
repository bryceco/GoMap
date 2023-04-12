//
//  POICustomTagsViewController.h
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/13/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

import UIKit

private let EDIT_RELATIONS = false

class SectionHeaderCell: UITableViewCell {
	@IBOutlet var label: UILabel!
}

class POIAllTagsViewController: UITableViewController, POIFeaturePickerDelegate, KeyValueTableCellOwner {
	private var tags: [(k: String, v: String)] = []
	private var relations: [OsmRelation] = []
	private var members: [OsmMember] = []
	@IBOutlet var saveButton: UIBarButtonItem!
	internal var childViewPresented = false
	private var currentFeature: PresetFeature?
	internal var currentTextField: UITextField?
	internal var allPresetKeys: [PresetKey] = [] // updated whenever a value changes
	private var prevNextToolbar: UIToolbar!

	override func viewDidLoad() {
		super.viewDidLoad()

		editButtonItem.target = self
		editButtonItem.action = #selector(toggleTableRowEditing(_:))
		navigationItem.rightBarButtonItems = [navigationItem.rightBarButtonItem, editButtonItem].compactMap { $0 }

		tableView.estimatedRowHeight = 44.0
		tableView.rowHeight = UITableView.automaticDimension
		tableView.keyboardDismissMode = .none

		let tabController = tabBarController as! POITabBarController

		if tabController.selection is OsmNode {
			title = NSLocalizedString("Node Tags", comment: "")
		} else if tabController.selection is OsmWay {
			title = NSLocalizedString("Way Tags", comment: "")
		} else if tabController.selection is OsmRelation {
			if let type = tabController.keyValueDict["type"],
			   !type.isEmpty
			{
				var type = type.replacingOccurrences(of: "_", with: " ")
				type = type.capitalized
				title = "\(type) Tags"
			} else {
				title = NSLocalizedString("Relation Tags", comment: "")
			}
		} else {
			title = NSLocalizedString("All Tags", comment: "")
		}

		prevNextToolbar = UIToolbar(frame: CGRect(x: 0, y: 0, width: view.frame.size.width, height: 44))
		prevNextToolbar.items = [
			UIBarButtonItem(
				title: NSLocalizedString("Previous", comment: ""),
				style: .plain,
				target: self,
				action: #selector(tabPrevious(_:))),
			UIBarButtonItem(
				title: NSLocalizedString("Next", comment: ""),
				style: .plain,
				target: self,
				action: #selector(tabNext(_:)))
		]
	}

	// return nil if unchanged, else row to set focus
	func updateWithRecomendations(forFeature forceReload: Bool) -> Int? {
		let tabController = tabBarController as? POITabBarController
		let geometry = tabController?.selection?.geometry() ?? GEOMETRY.POINT
		let dict = keyValueDictionary()
		let newFeature = PresetsDatabase.shared.presetFeatureMatching(
			tags: dict,
			geometry: geometry,
			location: AppDelegate.shared.mapView.currentRegion,
			includeNSI: true)

		if !forceReload, newFeature?.featureID == currentFeature?.featureID {
			return nil
		}
		currentFeature = newFeature

		// remove all entries without key & value
		tags = tags.filter { $0.k != "" && $0.v != "" }

		let nextRow = tags.count

		// add new cell ready to be edited
		tags.append(("", ""))

		// add placeholder keys
		allPresetKeys = []
		if let newFeature = currentFeature {
			let presets = PresetsForFeature(withFeature: newFeature, objectTags: dict, geometry: geometry, update: nil)
			allPresetKeys = presets.allPresetKeys()
			var newKeys: [String] = allPresetKeys.map({ $0.tagKey }).filter({ $0 != "" })
			newKeys = newKeys.filter { key in
				tags.first(where: { $0.k == key }) == nil
			}
			newKeys.sort()
			for key in newKeys {
				tags.append((key, ""))
			}
		}

		tableView.reloadData()

		return nextRow
	}

	func loadState() {
		let tabController = tabBarController as! POITabBarController

		// fetch values from tab controller
		relations = tabController.relationList
		members = (tabController.selection as? OsmRelation)?.members ?? []

		tags = []
		for (key, value) in tabController.keyValueDict {
			tags.append((key, value))
		}

		tags.sort(by: { obj1, obj2 in
			let key1 = obj1.k
			let key2 = obj2.k
			let tiger1 = key1.hasPrefix("tiger:") || key1.hasPrefix("gnis:")
			let tiger2 = key2.hasPrefix("tiger:") || key2.hasPrefix("gnis:")
			if tiger1 == tiger2 {
				return key1 < key2
			} else {
				return (tiger1 ? 1 : 0) < (tiger2 ? 1 : 0)
			}
		})

		_ = updateWithRecomendations(forFeature: true)

		saveButton.isEnabled = tabController.isTagDictChanged()
		if #available(iOS 13.0, *) {
			tabBarController?.isModalInPresentation = saveButton.isEnabled
		}
	}

	func saveState() {
		let tabController = tabBarController as? POITabBarController
		tabController?.keyValueDict = keyValueDictionary()
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		if childViewPresented {
			childViewPresented = false
		} else {
			loadState()
		}
	}

	override func viewWillDisappear(_ animated: Bool) {
		saveState()
		super.viewWillDisappear(animated)
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		let tabController = tabBarController as! POITabBarController
		if tabController.selection == nil {
			if let cell = tableView.cellForRow(at: IndexPath(row: 0, section: 0)) as? TextPairTableCell,
			   cell.text1.text?.count == 0,
			   cell.text2.text?.count == 0
			{
				cell.text1.becomeFirstResponder()
			}
		}
	}

	override var preferredFocusEnvironments: [UIFocusEnvironment] {
		if #available(macCatalyst 13,*) {
			// On Mac Catalyst set the focus to something other than a text field (which brings up the keyboard)
			// The Cancel button would be ideal but it isn't clear how to implement that, so select the Add button instead
		}
		return []
	}

	// MARK: - Feature picker

	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		if let dest = segue.destination as? POIFeaturePickerViewController {
			dest.delegate = self
		}
	}

	func featurePicker(_ typeViewController: POIFeaturePickerViewController,
	                   didChangeFeatureTo newFeature: PresetFeature)
	{
		let tabController = tabBarController as! POITabBarController
		let geometry = tabController.selection?.geometry() ?? GEOMETRY.POINT
		let location = AppDelegate.shared.mapView.currentRegion
		tabController.keyValueDict = newFeature.objectTagsUpdatedForFeature(tabController.keyValueDict,
		                                                                    geometry: geometry,
		                                                                    location: location)
		_ = updateWithRecomendations(forFeature: true)
		saveButton.isEnabled = tabController.isTagDictChanged()
		if #available(iOS 13.0, *) {
			tabBarController?.isModalInPresentation = saveButton.isEnabled
		}
	}

	// MARK: - Table view data source

	override func numberOfSections(in tableView: UITableView) -> Int {
		let tabController = tabBarController as! POITabBarController
		if (tabController.selection?.isRelation()) != nil {
			return 3
		} else if relations.count > 0 {
			return 2
		} else {
			return 1
		}
	}

	override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		if section == 0 {
			return NSLocalizedString("Tags", comment: "")
		} else if section == 1 {
			return NSLocalizedString("Relations", comment: "")
		} else {
			return NSLocalizedString("Members", comment: "")
		}
	}

	override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
		if section == 2 {
			return NSLocalizedString(
				"You can navigate to a relation member only if it is already downloaded.\nThese members are marked with '>'.",
				comment: "")
		}
		return nil
	}

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		if section == 0 {
			// tags
			return tags.count
		} else if section == 1 {
			// relations
			return relations.count
		} else {
			if EDIT_RELATIONS {
				return members.count + 1
			} else {
				return members.count
			}
		}
	}

	override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
		return UITableView.automaticDimension
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		if indexPath.section == 0 {
			// Tags
			let cell = tableView.dequeueReusableCell(withIdentifier: "KeyValueCell",
			                                         for: indexPath) as! KeyValueTableCell
			cell.keyValueCellOwner = self
			// assign text contents of fields
			let kv = tags[indexPath.row]
			cell.text1.isEnabled = true
			cell.text2.isEnabled = true
			cell.text1.text = kv.k
			cell.text2.key = kv.k
			cell.text2.text = kv.v
			cell.text1.inputAccessoryView = prevNextToolbar
			cell.text1.autocorrectionType = .no
			cell.text1.autocapitalizationType = .none
			cell.text1.spellCheckingType = .no
			cell.text2.defaultInputAccessoryView = prevNextToolbar
			return cell
		} else if indexPath.section == 1 {
			// Relations
			if indexPath.row == relations.count {
				let cell = tableView.dequeueReusableCell(withIdentifier: "AddCell", for: indexPath)
				return cell
			}
			let cell = tableView.dequeueReusableCell(
				withIdentifier: "RelationCell",
				for: indexPath) as! TextPairTableCell
			cell.text1.isEnabled = false
			cell.text2.isEnabled = false
			let relation = relations[indexPath.row]
			cell.text1.text = "\(relation.ident)"
			cell.text2.text = relation.friendlyDescription()

			return cell
		} else {
			// Members
			let member = members[indexPath.row]
			let isResolved = member.obj != nil
			let cell = (isResolved
				? tableView.dequeueReusableCell(withIdentifier: "RelationCell", for: indexPath)
				: tableView.dequeueReusableCell(withIdentifier: "MemberCell", for: indexPath)) as! TextPairTableCell
			if EDIT_RELATIONS {
				cell.text1.isEnabled = true
				cell.text2.isEnabled = true
			} else {
				cell.text1.isEnabled = false
				cell.text2.isEnabled = false
			}
			let memberName: String
			if let obj = member.obj {
				memberName = obj.friendlyDescriptionWithDetails()
			} else {
				let type = member.type.string
				memberName = "\(type) \(member.ref)"
			}
			cell.text1.text = member.role
			cell.text2.text = memberName

			return cell
		}
	}

	func keyValueDictionary() -> [String: String] {
		var dict = [String: String]()
		for (k, v) in tags {
			// strip whitespace around text
			let key = k.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
			let val = v.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
			if key.count != 0, val.count != 0 {
				dict[key] = val
			}
		}
		return dict
	}

	// MARK: Tab key

	override var keyCommands: [UIKeyCommand]? {
		let forward = UIKeyCommand(input: "\t", modifierFlags: [], action: #selector(tabNext(_:)))
		let backward = UIKeyCommand(input: "\t", modifierFlags: .shift, action: #selector(tabPrevious(_:)))
		return [forward, backward]
	}

	// MARK: TextField delegate

	var keyValueDict: [String: String] {
		return keyValueDictionary()
	}

	func keyValueEditingChanged(for kvCell: KeyValueTableCell) {
		guard let indexPath = tableView.indexPath(for: kvCell) else { return }
		tags[indexPath.row] = (k: kvCell.key, v: kvCell.value)

		let tabController = tabBarController as! POITabBarController
		saveButton.isEnabled = tabController.isTagDictChanged(keyValueDictionary())
		if #available(iOS 13.0, *) {
			tabBarController?.isModalInPresentation = saveButton.isEnabled
		}
	}

	func keyValueEditingEnded(for kvCell: KeyValueTableCell) {
		guard let indexPath = tableView.indexPath(for: kvCell) else { return }
		let kv = (k: kvCell.key, v: kvCell.value)
		tags[indexPath.row] = kv

		if kvCell.key != "", kvCell.value != "" {
			// move the edited row up
			var index = (0..<indexPath.row).first(where: {
				tags[$0].k == "" || tags[$0].v == ""
			}) ?? indexPath.row
			if index < indexPath.row {
				tags.remove(at: indexPath.row)
				tags.insert(kv, at: index)
				tableView.moveRow(at: indexPath, to: IndexPath(row: index, section: indexPath.section))
			}

			// if we created a row that defines a key that duplicates a row with
			// the same key elsewhere then delete the other row
			while let i = tags.indices.first(where: { $0 != index && tags[$0].k == kv.k }) {
				tags.remove(at: i)
				tableView.deleteRows(at: [IndexPath(row: i, section: indexPath.section)], with: .none)
				if i < index {
					index -= 1
				}
			}

			// update recommended tags
			if let nextRow = updateWithRecomendations(forFeature: false) {
				// a new feature was defined
				let newPath = IndexPath(row: nextRow, section: indexPath.section)
				tableView.scrollToRow(at: newPath, at: .middle, animated: false)

				// move focus to next empty cell
				let nextCell = tableView.cellForRow(at: newPath) as! TextPairTableCell
				nextCell.text1.becomeFirstResponder()
			}

			tableView.scrollToRow(at: IndexPath(row: index, section: indexPath.section),
								  at: .middle,
								  animated: true)

		} else if kv.k.count != 0 || kv.v.count != 0 {
			// ensure there's a blank line either elsewhere, or create one below us
			let haveBlank = tags.first(where: { $0.k.count == 0 && $0.v.count == 0 }) != nil
			if !haveBlank {
				let newPath = IndexPath(row: indexPath.row + 1, section: indexPath.section)
				tags.insert(("", ""), at: newPath.row)
				tableView.insertRows(at: [newPath], with: .none)
			}
		}
		saveState()
	}

	func tab(toNext forward: Bool) {
		guard let pair: TextPairTableCell = currentTextField?.superviewOfType(),
		      var indexPath = tableView.indexPath(for: pair)
		else { return }

		var field: UITextField?
		if forward {
			if currentTextField == pair.text1 {
				field = pair.text2
			} else {
				let max = tableView(tableView, numberOfRowsInSection: indexPath.section)
				let row = (indexPath.row + 1) % max
				indexPath = IndexPath(row: row, section: indexPath.section)
				if let pair = tableView.cellForRow(at: indexPath) as? TextPairTableCell {
					field = pair.text1
				}
			}
		} else {
			if currentTextField == pair.text2 {
				field = pair.text1
			} else {
				let max = tableView(tableView, numberOfRowsInSection: indexPath.section)
				let row = (indexPath.row - 1 + max) % max
				indexPath = IndexPath(row: row, section: indexPath.section)
				if let pair = tableView.cellForRow(at: indexPath) as? TextPairTableCell {
					field = pair.text2
				}
			}
		}
		if let field = field {
			field.becomeFirstResponder()
			currentTextField = field
		}
	}

	@objc func tabPrevious(_ sender: Any?) {
		tab(toNext: false)
	}

	@objc func tabNext(_ sender: Any?) {
		tab(toNext: true)
	}

	// MARK: - Table view delegate

	override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
		if section == 0 {
			let ident = "SectionHeaderCell"
			let cell: SectionHeaderCell = tableView.dequeueReusableCell(withIdentifier: ident) as! SectionHeaderCell
			cell.label.text = currentFeature?.name ?? "TAGS"
			return cell
		} else {
			return nil
		}
	}

	override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
		return 50.0
	}

	@IBAction func toggleTableRowEditing(_ sender: Any) {
		let tabController = tabBarController as! POITabBarController

		let editing = !tableView.isEditing
		navigationItem.leftBarButtonItem?.isEnabled = !editing
		navigationItem.rightBarButtonItem?.isEnabled = !editing && tabController.isTagDictChanged()
		tableView.setEditing(editing, animated: true)
		let button = sender as? UIBarButtonItem
		button?.title = editing ? NSLocalizedString("Done", comment: "") : NSLocalizedString("Edit", comment: "")
		button?.style = editing ? .done : .plain
	}

	// Don't allow deleting the "Add Tag" row
	override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
		if indexPath.section == 0 {
			return indexPath.row < tags.count
		} else if indexPath.section == 1 {
			// don't allow editing relations here
			return false
		} else {
			if EDIT_RELATIONS {
				return indexPath.row < members.count
			} else {
				return false
			}
		}
	}

	override func tableView(_ tableView: UITableView,
	                        commit editingStyle: UITableViewCell.EditingStyle,
	                        forRowAt indexPath: IndexPath)
	{
		if editingStyle == .delete {
			// Delete the row from the data source
			let tabController = tabBarController as! POITabBarController
			if indexPath.section == 0 {
				let kv = tags[indexPath.row]
				tabController.removeValueFromKeyValueDict(key: kv.k)
				//			[tabController.keyValueDict removeObjectForKey:tag];
				tags.remove(at: indexPath.row)
			} else if indexPath.section == 1 {
				relations.remove(at: indexPath.row)
			} else {
				members.remove(at: indexPath.row)
			}
			tableView.deleteRows(at: [indexPath], with: .fade)

			saveButton.isEnabled = tabController.isTagDictChanged()
			if #available(iOS 13.0, *) {
				tabBarController?.isModalInPresentation = saveButton.isEnabled
			}
		} else if editingStyle == .insert {
			// Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
		}
	}

	@IBAction func cancel(_ sender: Any) {
		view.endEditing(true)
		dismiss(animated: true)
	}

	@IBAction func done(_ sender: Any) {
		dismiss(animated: true)
		saveState()

		let tabController = tabBarController as? POITabBarController
		tabController?.commitChanges()
	}

	override func shouldPerformSegue(withIdentifier identifier: String, sender: Any?) -> Bool {
		// don't allow switching to relation if current selection is modified
		if identifier == "POITypeSegue" {
			return true
		}
		let tabController = tabBarController as! POITabBarController
		let dict = keyValueDictionary()
		if tabController.isTagDictChanged(dict) {
			let alert = UIAlertController(
				title: NSLocalizedString("Object modified", comment: ""),
				message: NSLocalizedString(
					"You must save or discard changes to the current object before editing its associated relation",
					comment: ""),
				preferredStyle: .alert)
			alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel, handler: nil))
			present(alert, animated: true)
			return false
		}

		// switch to relation or relation member
		guard let cell = sender as? UITableViewCell else { return false }
		guard let indexPath = tableView.indexPath(for: cell) else { return false }

		let object: OsmBaseObject
		if indexPath.section == 1 {
			// change the selected object in the editor to the relation
			object = relations[indexPath.row]
		} else if indexPath.section == 2 {
			let member = members[indexPath.row]
			if let obj = member.obj {
				object = obj
			} else {
				return false
			}
		} else {
			return false
		}
		let mapView = AppDelegate.shared.mapView!
		mapView.editorLayer.selectedNode = object.isNode()
		mapView.editorLayer.selectedWay = object.isWay()
		mapView.editorLayer.selectedRelation = object.isRelation()

		var newPoint = mapView.pushPin!.arrowPoint
		let latLon1 = mapView.mapTransform.latLon(forScreenPoint: newPoint)
		let latLon = object.latLonOnObject(forLatLon: latLon1)

		newPoint = mapView.mapTransform.screenPoint(forLatLon: latLon, birdsEye: true)
		if !mapView.bounds.contains(newPoint) {
			// new object is far away
			mapView.placePushpinForSelection()
		} else {
			mapView.placePushpin(at: newPoint, object: object)
		}

		// dismiss ourself and switch to the relation
		let topController = mapView.mainViewController
		mapView.refreshPushpinText() // update pushpin description to the relation
		dismiss(animated: true) {
			topController.performSegue(withIdentifier: "poiSegue", sender: nil)
		}
		return false
	}
}
