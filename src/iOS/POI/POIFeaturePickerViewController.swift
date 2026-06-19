//
//  POIFeaturePickerViewController.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/10/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

import UIKit

protocol POIFeaturePickerDelegate: AnyObject {
	func featurePicker(_ typeViewController: POIFeaturePickerViewController,
	                   didChangeFeatureTo feature: PresetFeature)
}

private let MOST_RECENT_DEFAULT_COUNT = 5
private let MOST_RECENT_SAVED_MAXIMUM = 100

class FeaturePickerCell: UITableViewCell {
	var featureID: String?
	@IBOutlet var title: UILabel!
	@IBOutlet var details: UILabel!
	@IBOutlet var pickerImage: UIImageView!
}

private var mostRecentArray: [PresetFeature] = []
private var mostRecentMaximum = 0
private let nsiToggleCellReuseId = "NsiToggleCell"

class POIFeaturePickerViewController: UITableViewController, UISearchBarDelegate {
	private var featureList: [PresetFeatureOrCategory] = []
	private var searchArray: [PresetFeature] = []
	@IBOutlet var searchBar: UISearchBar!
	private var isTopLevel = false

	var parentCategory: PresetCategory?
	weak var delegate: POIFeaturePickerDelegate?

	class func loadMostRecent(forGeometry geometry: GEOMETRY) {
		if let max = UserPrefs.shared.mostRecentTypesMaximum.value,
		   max > 0
		{
			mostRecentMaximum = max
		} else {
			mostRecentMaximum = MOST_RECENT_DEFAULT_COUNT
		}
		let pref = UserPrefs.shared.mostRecentPrefFor(geom: geometry)
		let a = pref.value ?? []
		mostRecentArray = a.compactMap({ PresetsDatabase.shared.presetFeatureForFeatureID($0) })
	}

	func currentSelectionGeometry() -> GEOMETRY {
		let tabController = tabBarController as? POITabBarController
		let geometry = tabController?.selection?.geometry() ?? GEOMETRY.POINT // a brand new node
		return geometry
	}

	private var isSearching: Bool {
		(searchBar.text?.count ?? 0) > 0
	}

	private var includeNSI: Bool {
		UserPrefs.shared.includeNSISuggestionsEnabled
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		tableView.estimatedRowHeight = 44.0 // or could use UITableViewAutomaticDimension;
		tableView.rowHeight = UITableView.automaticDimension

		let geometry = currentSelectionGeometry()
		Self.loadMostRecent(forGeometry: geometry)

		if let parentCategory = parentCategory {
			featureList = parentCategory.members.map({ .feature($0) })
		} else {
			isTopLevel = true
			featureList = PresetsDatabase.shared.featuresAndCategoriesForGeometry(geometry)
		}
	}

	override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
		return UITableView.automaticDimension
	}

	override func numberOfSections(in tableView: UITableView) -> Int {
		if isSearching {
			// search results + in-panel NSI toggle
			return 2
		}
		return isTopLevel ? 2 : 1
	}

	override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		if isTopLevel, !isSearching {
			return section == 0
				? NSLocalizedString("Most recent", comment: "")
				: NSLocalizedString("All choices", comment: "")
		} else {
			return nil
		}
	}

	override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
		if isTopLevel, !isSearching, section == 1 {
			let countryCode = AppDelegate.shared.mainView.currentRegion.country
			let locale = NSLocale.current as NSLocale
			let countryName = locale.displayName(forKey: .countryCode, value: countryCode) ?? ""

			if countryCode.count == 0 || countryName.count == 0 {
				// There's nothing to display.
				return nil
			}

			return String.localizedStringWithFormat(
				NSLocalizedString("Results for %@ (%@)", comment: "country name,2-character country code"),
				countryName,
				countryCode.uppercased())
		}
		return nil
	}

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		if isSearching {
			if section == 0 {
				return searchArray.count
			}
			return 1
		} else if isTopLevel, section == 0 {
			// showing most recent list
			let count = mostRecentArray.count
			return count < mostRecentMaximum ? count : mostRecentMaximum
		} else {
			// showing feature list
			return featureList.count
		}
	}

	override func tableView(_ tableView: UITableView, canFocusRowAt indexPath: IndexPath) -> Bool {
		return false
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		if isSearching, indexPath.section == 1 {
			return nsiToggleCell(for: tableView, at: indexPath)
		}

		let feature: PresetFeature
		if searchArray.count > 0 {
			feature = searchArray[indexPath.row]
		} else if isTopLevel, indexPath.section == 0 {
			// most recents
			feature = mostRecentArray[indexPath.row]
		} else {
			// type array
			switch featureList[indexPath.row] {
			case let .category(category):
				let cell = tableView.dequeueReusableCell(withIdentifier: "SubCell", for: indexPath)
				cell.textLabel?.text = PresetTranslations.shared.name(for: category) ?? category.categoryID
				cell.imageView?.image = category.icon
				return cell
			case let .feature(f):
				feature = f
			}
		}

		let icon = pickerIcon(for: feature)
		let brand = "☆ "
		let tabController = tabBarController as? POITabBarController
		let geometry = currentSelectionGeometry()

		let currentFeature = PresetsDatabase.shared.presetFeatureMatching(
			tags: tabController?.keyValueDict,
			geometry: geometry,
			location: AppDelegate.shared.mainView.currentRegion,
			includeNSI: includeNSI)
		let cell = tableView.dequeueReusableCell(withIdentifier: "FinalCell", for: indexPath) as! FeaturePickerCell
		cell.title.text = includeNSI && feature.nsiSuggestion ? (brand + feature.friendlyName()) : feature
			.friendlyName()
		cell.pickerImage.image = icon
		if #available(iOS 13.0, *) {
			cell.pickerImage.tintColor = UIColor.label
		} else {
			cell.pickerImage.tintColor = UIColor.black
		}
		cell.pickerImage.contentMode = .scaleAspectFit
		cell.setNeedsUpdateConstraints()
		let description = feature.wikiDescription(update: { desc in
			cell.details.text = desc
			if let index = self.tableView.indexPath(for: cell) {
				self.tableView.reloadRows(at: [index], with: .automatic)
			}
		})
		cell.details.text = description ?? feature.summary()
		cell.accessoryType = currentFeature === feature ? .checkmark : .none
		cell.featureID = feature.featureID
		return cell
	}

	class func updateMostRecentArray(withSelection feature: PresetFeature, geometry: GEOMETRY) {
		mostRecentArray.removeAll(where: { $0.featureID == feature.featureID })
		mostRecentArray.insert(feature, at: 0)
		if mostRecentArray.count > MOST_RECENT_SAVED_MAXIMUM {
			mostRecentArray.removeLast()
		}

		let a = mostRecentArray.map({ $0.featureID })
		let pref = UserPrefs.shared.mostRecentPrefFor(geom: geometry)
		pref.value = a
	}

	func updateTags(with feature: PresetFeature) {
		let geometry = currentSelectionGeometry()
		delegate?.featurePicker(self, didChangeFeatureTo: feature)
		Self.updateMostRecentArray(withSelection: feature, geometry: geometry)
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		if isSearching, indexPath.section == 1 {
			tableView.deselectRow(at: indexPath, animated: true)
			return
		}
		if searchArray.count != 0 {
			let feature = searchArray[indexPath.row]
			updateTags(with: feature)
			navigationController?.popToRootViewController(animated: true)
			return
		} else if isTopLevel, indexPath.section == 0 {
			// most recents
			let feature = mostRecentArray[indexPath.row]
			updateTags(with: feature)
			navigationController?.popToRootViewController(animated: true)
		} else {
			// type list
			switch featureList[indexPath.row] {
			case let .category(category):
				guard let sub = storyboard?.instantiateViewController(
					withIdentifier: "PoiTypeViewController") as? POIFeaturePickerViewController
				else {
					return
				}
				sub.parentCategory = category
				sub.delegate = delegate
				searchBar.resignFirstResponder()
				navigationController?.pushViewController(sub, animated: true)
			case let .feature(feature):
				updateTags(with: feature)
				navigationController?.popToRootViewController(animated: true)
			}
		}
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		if let text = (tabBarController as? POITabBarController)?.preservedFeatureTypeSearchText,
		   !text.isEmpty
		{
			searchBar.text = text
			refreshSearchResults()
			tableView.reloadData()
		}
	}

	func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
		let tabController = tabBarController as? POITabBarController
		if searchText.count == 0 {
			searchArray = []
			tabController?.preservedFeatureTypeSearchText = nil
		} else {
			refreshSearchResults()
			tabController?.preservedFeatureTypeSearchText = searchText
		}
		tableView.reloadData()
	}

	private func refreshSearchResults() {
		let geometry = currentSelectionGeometry()
		searchArray = PresetsDatabase.shared.featuresInCategory(
			parentCategory,
			matching: searchBar.text ?? "",
			geometry: geometry,
			location: AppDelegate.shared.mainView.currentRegion,
			includeNSI: includeNSI)
	}

	private func pickerIcon(for feature: PresetFeature) -> UIImage? {
		if includeNSI {
			return feature.nsiLogo(callback: { img in
				for cell in self.tableView.visibleCells {
					if let cell = cell as? FeaturePickerCell,
					   cell.featureID == feature.featureID
					{
						cell.pickerImage.image = img
					}
				}
			})
		}
		return feature.iconUnscaled?.withRenderingMode(.alwaysTemplate)
	}

	private func nsiToggleCell(for tableView: UITableView, at indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: nsiToggleCellReuseId)
			?? UITableViewCell(style: .default, reuseIdentifier: nsiToggleCellReuseId)
		cell.selectionStyle = .none
		cell.textLabel?.text = NSLocalizedString(
			"Include Chain/Brand names",
			comment: "Include Name Suggestion Index (NSI) chain/brand results in search")
		cell.textLabel?.numberOfLines = 0
		let toggle = UISwitch()
		toggle.isOn = includeNSI
		toggle.addTarget(self, action: #selector(nsiSuggestionsToggled(_:)), for: .valueChanged)
		cell.accessoryView = toggle
		return cell
	}

	@objc private func nsiSuggestionsToggled(_ sender: UISwitch) {
		UserPrefs.shared.includeNSISuggestions.value = sender.isOn
		if isSearching {
			refreshSearchResults()
			tableView.reloadSections(IndexSet(integer: 0), with: .automatic)
		}
	}

	@IBAction func configure(_ sender: Any) {
		let alert = UIAlertController(
			title: NSLocalizedString("Show Recent Items", comment: ""),
			message: NSLocalizedString("Number of recent items to display", comment: ""),
			preferredStyle: .alert)
		alert.addTextField(configurationHandler: { textField in
			textField.keyboardType = .numberPad
			textField.text = String(format: "%ld", Int(mostRecentMaximum))
		})
		alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default, handler: { _ in
			let textField = alert.textFields?[0]
			var count = Int(textField?.text ?? "") ?? 0
			if count < 0 {
				count = 0
			} else if count > 99 {
				count = 99
			}
			mostRecentMaximum = count
			UserPrefs.shared.mostRecentTypesMaximum.value = mostRecentMaximum
		}))
		alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil))
		present(alert, animated: true)
	}

	@IBAction func back(_ sender: Any) {
		dismiss(animated: true)
	}
}
