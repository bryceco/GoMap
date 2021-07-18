//
//  POICustomTagsViewController.h
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/13/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

import SafariServices
import UIKit

private let EDIT_RELATIONS = false

class TextPairTableCell: UITableViewCell {
	@IBOutlet var text1: AutocompleteTextField!
	@IBOutlet var text2: AutocompleteTextField!
	@IBOutlet var infoButton: UIButton!

	override func willTransition(to state: UITableViewCell.StateMask) {
		super.willTransition(to: state)

		// don't allow editing text while deleting
		if state.rawValue != 0,
		   (UITableViewCell.StateMask.showingEditControl.rawValue != 0) ||
		   (UITableViewCell.StateMask.showingDeleteConfirmation.rawValue != 0)
		{
			text1.resignFirstResponder()
			text2.resignFirstResponder()
		}
	}
}

class POIAllTagsViewController: UITableViewController {
	private var tags: [(k: String, v: String)] = []
	private var relations: [OsmRelation] = []
	private var members: [OsmMember] = []
	@IBOutlet var saveButton: UIBarButtonItem!
	private var childViewPresented = false
	private var featureID: String?
	private var currentTextField: UITextField?

	override func viewDidLoad() {
		super.viewDidLoad()

		let editButton = editButtonItem
		editButton.target = self
		editButton.action = #selector(toggleTableRowEditing(_:))
		navigationItem.rightBarButtonItems = [navigationItem.rightBarButtonItem, editButton].compactMap { $0 }

		let tabController = tabBarController as! POITabBarController

		if tabController.selection?.isNode() != nil {
			title = NSLocalizedString("Node Tags", comment: "")
		} else if tabController.selection?.isWay() != nil {
			title = NSLocalizedString("Way Tags", comment: "")
		} else if tabController.selection?.isRelation() != nil {
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
	}

	deinit {}

	// return -1 if unchanged, else row to set focus
	func updateWithRecomendations(forFeature forceReload: Bool) -> Int {
		let tabController = tabBarController as? POITabBarController
		let geometry = tabController?.selection?.geometry() ?? GEOMETRY.NODE
		let dict = keyValueDictionary()
		let newFeature = PresetsDatabase.shared.matchObjectTagsToFeature(
			dict,
			geometry: geometry,
			includeNSI: true)

		if !forceReload, newFeature?.featureID == featureID {
			return -1
		}
		featureID = newFeature?.featureID

		// remove all entries without key & value
		tags = tags.filter { $0.k != "" && $0.v != "" }

		let nextRow = tags.count

		// add new cell ready to be edited
		tags.append(("", ""))

		// add placeholder keys
		if let newFeature = newFeature {
			let presets = PresetsForFeature(withFeature: newFeature, objectTags: dict, geometry: geometry, update: nil)
			var newKeys: [String] = []
			for section in 0..<presets.sectionCount() {
				for row in 0..<presets.tagsInSection(section) {
					let preset = presets.presetAtSection(section, row: row)
					switch preset {
					case let .group(group):
						for case let .key(presetKey) in group.presetKeys {
							if presetKey.tagKey == "" {
								continue
							}
							newKeys.append(presetKey.tagKey)
						}
					case let .key(presetKey):
						if presetKey.tagKey.count == 0 {
							continue
						}
						newKeys.append(presetKey.tagKey)
					}
				}
			}
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

	// MARK: Accessory buttons

	private func getAssociatedColor(for cell: TextPairTableCell) -> UIView? {
		if let key = cell.text1.text,
		   let value = cell.text2.text,
		   key == "colour" || key == "color" || key.hasSuffix(":colour") || key.hasSuffix(":color")
		{
			let color = Colors.cssColorForColorName(value)
			if let color = color {
				var size = cell.text2.bounds.size.height
				size = CGFloat(round(Double(size * 0.5)))
				let square = UIView(frame: CGRect(x: 0, y: 0, width: size, height: size))
				square.backgroundColor = color
				square.layer.borderColor = UIColor.black.cgColor
				square.layer.borderWidth = 1.0
				let view = UIView(frame: CGRect(x: 0, y: 0, width: size + 6, height: size))
				view.backgroundColor = UIColor.clear
				view.addSubview(square)
				return view
			}
		}
		return nil
	}

	@IBAction func openWebsite(_ sender: UIView?) {
		guard let pair: TextPairTableCell = sender?.superviewOfType(),
		      let key = pair.text1.text,
		      let value = pair.text2.text
		else { return }
		let string: String
		if key == "wikipedia" || key.hasSuffix(":wikipedia") {
			let a = value.components(separatedBy: ":")
			guard a.count >= 2,
			      let lang = a[0].addingPercentEncoding(withAllowedCharacters: CharacterSet.urlPathAllowed),
			      let page = a[1].addingPercentEncoding(withAllowedCharacters: CharacterSet.urlPathAllowed)
			else { return }
			string = "https://\(lang).wikipedia.org/wiki/\(page)"
		} else if key == "wikidata" || key.hasSuffix(":wikidata") {
			guard let page = value.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlPathAllowed)
			else { return }
			string = "https://www.wikidata.org/wiki/\(page)"
		} else if value.hasPrefix("http://") || value.hasPrefix("https://") {
			string = value
		} else {
			return
		}

		let url = URL(string: string)
		if let url = url {
			let viewController = SFSafariViewController(url: url)
			present(viewController, animated: true)
		} else {
			let alert = UIAlertController(
				title: NSLocalizedString("Invalid URL", comment: ""),
				message: nil,
				preferredStyle: .alert)
			alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel, handler: nil))
			present(alert, animated: true)
		}
	}

	private func getWebsiteButton(for cell: TextPairTableCell) -> UIView? {
		if let key = cell.text1.text,
		   let value = cell.text2.text,
		   key == "wikipedia"
		   || key == "wikidata"
		   || key.hasSuffix(":wikipedia")
		   || key.hasSuffix(":wikidata")
		   || value.hasPrefix("http://")
		   || value.hasPrefix("https://")
		{
			let button = UIButton(type: .system)
			button.layer.borderWidth = 2.0
			button.layer.borderColor = UIColor.systemBlue.cgColor
			button.layer.cornerRadius = 15.0
			button.setTitle("🔗", for: .normal)

			button.addTarget(self, action: #selector(openWebsite(_:)), for: .touchUpInside)
			return button
		}
		return nil
	}

	@IBAction func setSurveyDate(_ sender: UIView?) {
		guard let pair: TextPairTableCell = sender?.superviewOfType() else { return }

		let now = Date()
		let dateFormatter = ISO8601DateFormatter()
		dateFormatter.formatOptions = [.withYear, .withMonth, .withDay, .withDashSeparatorInDate]
		dateFormatter.timeZone = NSTimeZone.local
		let text = dateFormatter.string(from: now)
		pair.text2.text = text
		textFieldChanged(pair.text2)
		textFieldEditingDidEnd(pair.text2)
	}

	private func getSurveyDateButton(for cell: TextPairTableCell) -> UIView? {
		let synonyms = [
			"check_date",
			"survey_date",
			"survey:date",
			"survey",
			"lastcheck",
			"last_checked",
			"updated",
			"checked_exists:date"
		]
		if let text = cell.text1.text,
		   synonyms.contains(text)
		{
			let button = UIButton(type: .contactAdd)
			button.addTarget(self, action: #selector(setSurveyDate(_:)), for: .touchUpInside)
			return button
		}
		return nil
	}

	@IBAction func setDirection(_ sender: Any) {
		guard let pair: TextPairTableCell = (sender as? UIView)?.superviewOfType() else { return }

		let directionViewController = DirectionViewController.instantiate(
			key: pair.text1.text ?? "",
			value: pair.text2.text,
			setValue: { [self] newValue in
				pair.text2.text = newValue
				textFieldChanged(pair.text2)
				textFieldEditingDidEnd(pair.text2)
			})
		childViewPresented = true

		present(directionViewController, animated: true)
	}

	private func getDirectionButton(for cell: TextPairTableCell) -> UIView? {
		let synonyms = [
			"direction",
			"camera:direction"
		]
		if let text = cell.text1.text,
		   synonyms.contains(text)
		{
			let button = UIButton(type: .contactAdd)
			button.addTarget(self, action: #selector(setDirection(_:)), for: .touchUpInside)
			return button
		}
		return nil
	}

	@IBAction func setHeight(_ sender: UIView?) {
		guard let pair: TextPairTableCell = sender?.superviewOfType() else { return }

		if HeightViewController.unableToInstantiate(withUserWarning: self) {
			return
		}

		let vc = HeightViewController.instantiate()
		vc.callback = { newValue in
			pair.text2.text = newValue
			self.textFieldChanged(pair.text2)
			self.textFieldEditingDidEnd(pair.text2)
		}
		present(vc, animated: true)
		childViewPresented = true
	}

	private func getHeightButton(for cell: TextPairTableCell) -> UIView? {
		if cell.text1.text == "height" {
			let button = UIButton(type: .contactAdd)
			button.addTarget(self, action: #selector(setHeight(_:)), for: .touchUpInside)
			return button
		}
		return nil
	}

	private func updateAssociatedContent(for cell: TextPairTableCell) {
		let associatedView = getAssociatedColor(for: cell)
			?? getWebsiteButton(for: cell)
			?? getSurveyDateButton(for: cell)
			?? getDirectionButton(for: cell)
			?? getHeightButton(for: cell)

		cell.text2.rightView = associatedView
		cell.text2.rightViewMode = associatedView != nil ? .always : .never
	}

	@IBAction func infoButtonPressed(_ sender: Any?) {
		guard let pair: TextPairTableCell = (sender as? UIView)?.superviewOfType() else { return }

		// show OSM wiki page
		guard let key = pair.text1.text,
		      let value = pair.text2.text,
		      !key.isEmpty
		else { return }
		let presetLanguages = PresetLanguages()
		let languageCode = presetLanguages.preferredLanguageCode

		let progress = UIActivityIndicatorView(style: .gray)
		progress.frame = pair.infoButton.bounds
		pair.infoButton.addSubview(progress)
		pair.infoButton.isEnabled = false
		pair.infoButton.titleLabel?.layer.opacity = 0.0
		progress.startAnimating()
		WikiPage.shared.bestWikiPage(forKey: key, value: value, language: languageCode()) { [self] url in
			progress.removeFromSuperview()
			pair.infoButton.isEnabled = true
			pair.infoButton.titleLabel?.layer.opacity = 1.0
			if url != nil, view.window != nil {
				var viewController: SFSafariViewController?
				if let url = url {
					viewController = SFSafariViewController(url: url)
				}
				childViewPresented = true
				if let viewController = viewController {
					present(viewController, animated: true)
				}
			}
		}
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		if indexPath.section == 0 {
			// Tags
			let cell = tableView.dequeueReusableCell(withIdentifier: "TagCell", for: indexPath) as! TextPairTableCell
			let kv = tags[indexPath.row]
			// assign text contents of fields
			cell.text1.isEnabled = true
			cell.text2.isEnabled = true
			cell.text1.text = kv.k
			cell.text2.text = kv.v

			updateAssociatedContent(for: cell)

			weak var weakCell = cell
			cell.text1.didSelectAutocomplete = {
				weakCell?.text2.becomeFirstResponder()
			}
			cell.text2.didSelectAutocomplete = {
				weakCell?.text2.resignFirstResponder()
			}

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

	@IBAction func textFieldReturn(_ sender: UIView) {
		sender.resignFirstResponder()
		_ = updateWithRecomendations(forFeature: true)
	}

	@IBAction func textFieldEditingDidBegin(_ textField: AutocompleteTextField) {
		currentTextField = textField

		guard let pair: TextPairTableCell = textField.superviewOfType(),
		      let indexPath = tableView.indexPath(for: pair)
		else { return }

		if indexPath.section == 0 {
			let isValue = textField == pair.text2

			if isValue {
				// get list of values for current key
				let kv = tags[indexPath.row]
				let key = kv.k
				if PresetsDatabase.shared.eligibleForAutocomplete(key) {
					var set: Set<String> = PresetsDatabase.shared.allTagValuesForKey(key)
					let appDelegate = AppDelegate.shared
					let values = appDelegate.mapView.editorLayer.mapData.tagValues(forKey: key)
					set = set.union(values)
					let list: [String] = Array(set)
					textField.autocompleteStrings = list
				}
			} else {
				// get list of keys
				let set = PresetsDatabase.shared.allTagKeys()
				let list = Array(set)
				textField.autocompleteStrings = list
			}
		}
	}

	func convertWikiUrlToReference(withKey key: String, value url: String) -> String? {
		if key.hasPrefix("wikipedia") || key.hasSuffix(":wikipedia") {
			// if the value is for wikipedia then convert the URL to the correct format
			// format is https://en.wikipedia.org/wiki/Nova_Scotia
			let scanner = Scanner(string: url)
			var languageCode: NSString?
			var pageName: NSString?
			if scanner.scanString("https://", into: nil) || scanner.scanString("http://", into: nil),
			   scanner.scanUpTo(".", into: &languageCode),
			   scanner.scanString(".m", into: nil) || true,
			   scanner.scanString(".wikipedia.org/wiki/", into: nil),
			   scanner.scanUpTo("/", into: &pageName),
			   scanner.isAtEnd,
			   let languageCode = languageCode as String?,
			   let pageName = pageName as String?,
			   languageCode.count == 2, pageName.count > 0
			{
				return "\(languageCode):\(pageName)"
			}
		} else if key.hasPrefix("wikidata") || key.hasSuffix(":wikidata") {
			// https://www.wikidata.org/wiki/Q90000000
			let scanner = Scanner(string: url)
			var pageName: NSString?
			if scanner.scanString("https://", into: nil) || scanner.scanString("http://", into: nil),
			   scanner.scanString("www.wikidata.org/wiki/", into: nil) || scanner
			   .scanString("m.wikidata.org/wiki/", into: nil),
			   scanner.scanUpTo("/", into: &pageName),
			   scanner.isAtEnd,
			   let pageName = pageName as String?,
			   pageName.count > 0
			{
				return pageName
			}
		}
		return nil
	}

	@objc func textFieldEditingDidEnd(_ textField: UITextField) {
		guard let pair: TextPairTableCell = textField.superviewOfType(),
		      let indexPath = tableView.indexPath(for: pair)
		else { return }

		if indexPath.section == 0 {
			var kv = tags[indexPath.row]

			updateAssociatedContent(for: pair)

			if kv.k.count != 0 && kv.v.count != 0 {
				// do wikipedia conversion
				if let newValue = convertWikiUrlToReference(withKey: kv.k, value: kv.v) {
					kv.v = newValue
					pair.text2.text = newValue
					tags[indexPath.row] = kv
				}

				// move the edited row up
				var index = (0..<indexPath.row)
					.first(where: { tags[$0].k.count == 0 || tags[$0].v.count == 0 }) ?? indexPath.row
				if index < indexPath.row {
					tags.remove(at: indexPath.row)
					tags.insert(kv, at: index)
					tableView.moveRow(at: indexPath, to: IndexPath(row: index, section: 0))
				}

				// if we created a row that defines a key that duplicates a row with
				// the same key elsewhere then delete the other row
				while let i = tags.indices.first(where: { $0 != index && tags[$0].k == kv.k }) {
					tags.remove(at: i)
					tableView.deleteRows(at: [IndexPath(row: i, section: 0)], with: .none)
					if i < index { index -= 1 }
				}

				// update recommended tags
				let nextRow = updateWithRecomendations(forFeature: false)
				if nextRow >= 0 {
					// a new feature was defined
					let newPath = IndexPath(row: nextRow, section: 0)
					tableView.scrollToRow(at: newPath, at: .middle, animated: false)

					// move focus to next empty cell
					let nextCell = tableView.cellForRow(at: newPath) as! TextPairTableCell
					nextCell.text1.becomeFirstResponder()
				}

				tableView.scrollToRow(at: IndexPath(row: index, section: 0), at: .middle, animated: true)

			} else if kv.k.count != 0 || kv.v.count != 0 {
				// ensure there's a blank line either elsewhere, or create one below us
				let haveBlank = tags.first(where: { $0.k.count == 0 && $0.v.count == 0 }) != nil
				if !haveBlank {
					let newPath = IndexPath(row: indexPath.row + 1, section: indexPath.section)
					tags.insert(("", ""), at: newPath.row)
					tableView.insertRows(at: [newPath], with: .none)
				}
			}
		}
	}

	@IBAction func textFieldChanged(_ textField: UITextField) {
		guard let pair: TextPairTableCell = textField.superviewOfType(),
		      let indexPath = tableView.indexPath(for: pair)
		else { return }

		let tabController = tabBarController as! POITabBarController

		if indexPath.section == 0 {
			// edited tags
			var kv = tags[indexPath.row]
			let isValue = textField == pair.text2

			if isValue {
				// new value
				kv.v = textField.text ?? ""
			} else {
				// new key name
				kv.k = textField.text ?? ""
			}
			tags[indexPath.row] = kv

			let dict = keyValueDictionary()
			saveButton.isEnabled = tabController.isTagDictChanged(dict)
			if #available(iOS 13.0, *) {
				tabBarController?.isModalInPresentation = saveButton.isEnabled
			}
		}
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

	@objc func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
		let toolbar = UIToolbar(frame: CGRect(x: 0, y: 0, width: view.frame.size.width, height: 44))
		toolbar.items = [
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
		textField.inputAccessoryView = toolbar
		return true
	}

	@objc func textField(_ textField: UITextField,
	                     shouldChangeCharactersIn range: NSRange,
	                     replacementString string: String) -> Bool
	{
		let MAX_LENGTH = 255
		let oldLength = textField.text?.count ?? 0
		let replacementLength = string.count
		let rangeLength = range.length
		let newLength = oldLength - rangeLength + replacementLength
		let returnKey = string.range(of: "\n") != nil
		return newLength <= MAX_LENGTH || returnKey
	}

	// MARK: - Table view delegate

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

	override func tableView(
		_ tableView: UITableView,
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
