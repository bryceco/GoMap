//
//  POIPresetValuePickerController.swift
//  Go Map!!
//
//  Copyright © 2021 Bryce Cogswell. All rights reserved.
//

import UIKit

class POIPresetValuePickerController: UITableViewController {
	static let ImageWidth = 80.0
	var key = ""
	var presetValueList: [PresetValue] = []
	var onSetValue: ((String) -> Void)?
	var descriptions: [String: String] = [:]
	var images: [String: UIImage] = [:]

	let placeholderImage = UIImage().scaledTo(width: ImageWidth, height: ImageWidth / 2)

	func fetchWikiImagesAndDescriptions() {
		let languageCode = PresetLanguages.preferredPresetLanguageCode()
		for preset in presetValueList {
			if let meta = WikiPage.shared.wikiDataFor(
				key: key,
				value: preset.tagValue,
				language: languageCode,
				imageWidth: Int(Self.ImageWidth),
				update: { meta in
					guard let meta = meta else { return }
					let tag = meta.key + "=" + meta.value
					self.descriptions[tag] = meta.description
					self.images[tag] = meta.image
					self.tableView.reloadData()
				})
			{
				let tag = meta.key + "=" + meta.value
				descriptions[tag] = meta.description
				images[tag] = meta.image
			}
		}
	}

	override func viewWillAppear(_ animated: Bool) {
#if false
		// We have the ability to display relevant OSM Wiki information and images along with
		// the preset, but currently the Wiki doesn't have enough entries to make it worthwhile.
		fetchWikiImagesAndDescriptions()
#endif
		// Set images for icons associated with the presets
		for preset in presetValueList {
			if let iconName = preset.icon {
				let tag = key + "=" + preset.tagValue
				if let image = UIImage(named: iconName) {
					let scaled = image.scaledTo(width: CGFloat(Self.ImageWidth), height: nil)
					images[tag] = scaled
				}
			}
		}
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		tableView.estimatedRowHeight = UITableView.automaticDimension
		tableView.rowHeight = UITableView.automaticDimension
	}

	// MARK: - Table view data source

	override func numberOfSections(in tableView: UITableView) -> Int {
		1
	}

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		presetValueList.count
	}

	override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		return nil
	}

	override func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
		UIView()
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let preset = presetValueList[indexPath.row]

		let cell: UITableViewCell = tableView.dequeueReusableCell(withIdentifier: "SubtitleCell", for: indexPath)
		let tag = key + "=" + preset.tagValue

		if preset.name != "" {
			cell.textLabel?.text = preset.name
			cell.detailTextLabel?.text = preset.details ?? descriptions[tag] ?? ""
		} else {
			let text = preset.tagValue.replacingOccurrences(of: "_", with: " ").capitalized
			cell.textLabel?.text = text
			cell.detailTextLabel?.text = descriptions[tag] ?? ""
		}
		if images.count > 0 {
			cell.imageView?.image = images[tag] ?? placeholderImage
		}

		let tabController = tabBarController as? POITabBarController
		let selected = tabController?.keyValueDict[key] == preset.tagValue
		cell.accessoryType = selected ? .checkmark : .none

		return cell
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		let preset = presetValueList[indexPath.row]
		onSetValue?(preset.tagValue)
		navigationController?.popViewController(animated: true)
	}
}
