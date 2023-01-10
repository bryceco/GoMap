//
//  POIPresetValuePickerController.swift
//  Go Map!!
//
//  Copyright © 2021 Bryce Cogswell. All rights reserved.
//

import UIKit

class POIPresetValuePickerController: UITableViewController {
	static let ImageWidth = 80
	var key = ""
	var presetValueList: [PresetValue] = []
	var onSetValue: ((String) -> Void)?
	var descriptions: [String: String] = [:]
	var images: [String: UIImage] = [:]

	let placeholderImage: UIImage = {
		UIGraphicsBeginImageContextWithOptions(
			CGSize(width: ImageWidth, height: ImageWidth / 2),
			false,
			UIScreen.main.scale)
		let image = UIGraphicsGetImageFromCurrentImageContext()!
		UIGraphicsEndImageContext()
		return image
	}()

	func displayImagesAndDescriptions() {
		let languageCode = PresetLanguages().preferredLanguageCode()
		for preset in presetValueList {
			if let meta = WikiPage.shared.wikiDataFor(
				key: key,
				value: preset.tagValue,
				language: languageCode,
				imageWidth: Self.ImageWidth,
				completion: { meta in
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
		// displayImagesAndDescriptions()
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
