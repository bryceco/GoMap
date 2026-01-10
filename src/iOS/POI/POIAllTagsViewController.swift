//
//  POICustomTagsViewController.h
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/13/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

import UIKit

private let EDIT_RELATIONS = false

private class SectionHeaderCell: UITableViewHeaderFooterView {
	static let reuseIdentifier = "SectionHeaderCell"

	let label = UILabel()
	let button = UIButton()

	override init(reuseIdentifier: String?) {
		super.init(reuseIdentifier: reuseIdentifier)
		configureContents()
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	func configureContents() {
		label.translatesAutoresizingMaskIntoConstraints = false
		button.translatesAutoresizingMaskIntoConstraints = false

		if #available(iOS 13.0, *) {
			label.textColor = UIColor.secondaryLabel
		} else {
			label.textColor = UIColor.darkGray
		}
		button.setTitle(">", for: .normal)
		button.setTitleColor(UIColor.systemBlue, for: .normal)
		button.addTarget(self, action: #selector(pickFeature(_:)), for: .touchUpInside)

		contentView.addSubview(label)
		contentView.addSubview(button)

		NSLayoutConstraint.activate([
			label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
			label.leadingAnchor.constraint(equalToSystemSpacingAfter: contentView.leadingAnchor, multiplier: 1.0),
			label.trailingAnchor.constraint(greaterThanOrEqualTo: button.leadingAnchor, constant: 10.0),

			button.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
			button.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor, constant: 10.0),
			button.widthAnchor.constraint(equalToConstant: 44.0)
		])
	}

	@objc func pickFeature(_ sender: Any?) {
		var r: UIResponder = self
		while true {
			if let vc = r as? POIAllTagsViewController {
				let storyboard = UIStoryboard(name: "POI", bundle: nil)
				let myVC = storyboard.instantiateViewController(withIdentifier: "PoiTypeViewController")
					as! POIFeaturePickerViewController
				myVC.delegate = vc
				vc.navigationController?.pushViewController(myVC, animated: true)
				return
			}
			guard let next = r.next else { return }
			r = next
		}
	}
}

class POIAllTagsViewController: UITableViewController, POIFeaturePickerDelegate, KeyValueTableCellOwner {
	var allPresetKeys: [PresetDisplayKey] = []
	private var tags: KeyValueTableSection!
	private var relations: [OsmRelation] = []
	private var members: [OsmMember] = []
	@IBOutlet var saveButton: UIBarButtonItem!
	private var currentFeature: PresetFeature?
	var currentTextField: UITextField?
	private var prevNextToolbar: UIToolbar!

	override func viewDidLoad() {
		tags = KeyValueTableSection(tableView: tableView)
		tableView.register(SectionHeaderCell.self,
		                   forHeaderFooterViewReuseIdentifier: SectionHeaderCell.reuseIdentifier)

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
		let tabController = tabBarController as! POITabBarController
		let geometry = tabController.selection?.geometry() ?? GEOMETRY.POINT
		let dict = tags.keyValueDictionary()
		let newFeature = PresetsDatabase.shared.presetFeatureMatching(
			tags: dict,
			geometry: geometry,
			location: AppDelegate.shared.mapView.currentRegion,
			includeNSI: true)

		if !forceReload, newFeature?.featureID == currentFeature?.featureID {
			return nil
		}
		currentFeature = newFeature

		// Keep entries with key & value
		var list = tags.allTags
		list.removeAll(where: { $0.k == "" || $0.v == "" })

		let nextRow = tags.count

		list.append(("", ""))

		// add placeholder keys
		if let newFeature = currentFeature {
			let presets = PresetDisplayForFeature(withFeature: newFeature,
			                                      objectTags: dict,
			                                      geometry: geometry,
			                                      update: nil)
			allPresetKeys = presets.allPresetKeys()
			let newKeys: Set<String> = Set(allPresetKeys.map({ $0.tagKey }).filter({ $0 != "" }))
				.subtracting(tags.allTags.map { $0.k })

			for key in Array(newKeys).sorted() {
				list.append((key, ""))
			}
		}
		tags.setWithoutSorting(list)
		tableView.reloadData()

		saveButton.isEnabled = tabController.isTagDictChanged()
		if #available(iOS 13.0, *) {
			tabBarController?.isModalInPresentation = saveButton.isEnabled
		}

		return nextRow
	}

	func loadState() {
		// Loading the state reloads the tableview, and we don't want to
		// have an editingDidEnd() call modify the table while we're
		// reloading it. So end all editing up front.
		view.endEditing(true)

		let tabController = tabBarController as! POITabBarController

		// fetch values from tab controller
		relations = tabController.relationList
		members = (tabController.selection as? OsmRelation)?.members ?? []

		tags.set(tabController.keyValueDict.map { ($0.key, $0.value) })

		_ = updateWithRecomendations(forFeature: true)
	}

	func saveState() {
		let tabController = tabBarController as? POITabBarController
		tabController?.keyValueDict = tags.keyValueDictionary()
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		loadState()
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
			return nil // NSLocalizedString("Tags", comment: "")
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

			cell.isSet.backgroundColor = kv.k == "" || kv.v == "" ? nil : UIColor.systemBlue
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

	// MARK: Tab key

	override var keyCommands: [UIKeyCommand]? {
		let forward = UIKeyCommand(input: "\t", modifierFlags: [], action: #selector(tabNext(_:)))
		let backward = UIKeyCommand(input: "\t", modifierFlags: .shift, action: #selector(tabPrevious(_:)))
		return [forward, backward]
	}

	// MARK: TextField delegate

	var keyValueDict: [String: String] {
		return tags.keyValueDictionary()
	}

	func keyValueEditingChanged(for kvCell: KeyValueTableCell) {
		guard let indexPath = tableView.indexPath(for: kvCell) else { return }
		let kv = (k: kvCell.key, v: kvCell.value)
		tags[indexPath.row] = kv
		kvCell.isSet.backgroundColor = kv.k == "" || kv.v == "" ? nil : UIColor.systemBlue

		let tabController = tabBarController as! POITabBarController
		saveButton.isEnabled = tabController.isTagDictChanged(tags.keyValueDictionary())
		if #available(iOS 13.0, *) {
			tabBarController?.isModalInPresentation = saveButton.isEnabled
		}
	}

	func keyValueEditingEnded(for kvCell: KeyValueTableCell) {
		_ = tags.keyValueEditingEnded(for: kvCell)
		saveState()
	}

	// Called when user pastes a set of tags
	func pasteTags(_ tags: [String: String]) {
		for visibleCell in tableView.visibleCells {
			_ = (visibleCell as? KeyValueTableCell)?.resignFirstResponder()
		}

		var dict = self.tags.keyValueDictionary()
		for (k, v) in tags {
			dict[k] = v
		}
		self.tags.set(dict.map { (k: $0.key, v: $0.value) })

		saveState()
		_ = updateWithRecomendations(forFeature: true)
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
			let cell: SectionHeaderCell = tableView
				.dequeueReusableHeaderFooterView(withIdentifier: SectionHeaderCell
					.reuseIdentifier) as! SectionHeaderCell
			cell.label.text = currentFeature?.localizedName.uppercased() ?? "TAGS"
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
				tags.remove(at: indexPath)
			} else if indexPath.section == 1 {
				relations.remove(at: indexPath.row)
				tableView.deleteRows(at: [indexPath], with: .fade)
			} else {
				members.remove(at: indexPath.row)
				tableView.deleteRows(at: [indexPath], with: .fade)
			}

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
		let dict = tags.keyValueDictionary()
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
		mapView.refreshPushpinText() // update pushpin description to the relation
		dismiss(animated: true) {
			AppDelegate.shared.mainView.performSegue(withIdentifier: "poiSegue", sender: nil)
		}
		return false
	}
}
