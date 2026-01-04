//
//  CustomFeatureController.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 3/10/25.
//  Copyright © 2025 Bryce Cogswell. All rights reserved.
//

import UIKit

class CustomFeature: PresetFeature, Codable {
	init(featureID: String,
	     name: String,
	     geometry: [String],
	     tags: [String: String])
	{
		let impliedFeature = PresetsDatabase.shared.presetFeatureMatching(
			tags: tags,
			geometry: GEOMETRY(rawValue: geometry.first!)!,
			location: AppDelegate.shared.mapView.currentRegion,
			includeNSI: false)
		super.init(_addTags: nil,
		           aliases: [],
		           featureID: featureID,
		           fieldsWithRedirect: impliedFeature?.fieldsWithRedirect ?? [],
		           geometry: geometry,
		           icon: "CustomFeature",
		           locationSet: LocationSet(withJson: nil),
		           matchScore: impliedFeature?.matchScore ?? 1.0,
		           moreFieldsWithRedirect: impliedFeature?.moreFieldsWithRedirect,
		           nameWithRedirect: name,
		           nsiSuggestion: false,
		           reference: nil,
		           _removeTags: nil,
		           searchable: true,
		           tags: tags,
		           terms: [])
	}

	enum CodingKeys: String, CodingKey {
		case featureID
		case name
		case geometry
		case tags
	}

	required convenience init(from decoder: any Decoder) throws {
		let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
		let feat = try container.decode(String.self, forKey: .featureID)
		let name = try container.decode(String.self, forKey: .name)
		let geom = try container.decode([String].self, forKey: .geometry)
		let tags = try container.decode([String: String].self, forKey: .tags)
		self.init(featureID: feat, name: name, geometry: geom, tags: tags)
	}

	func encode(to encoder: any Encoder) throws {
		var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(featureID, forKey: .featureID)
		try container.encode(localizedName, forKey: .name)
		try container.encode(geometry, forKey: .geometry)
		try container.encode(tags, forKey: .tags)
	}
}

class CustomFeatureController: UITableViewController, UITextFieldDelegate {
	@IBOutlet var nameField: UITextField!

	@IBOutlet var buttonPoint: UIButton!
	@IBOutlet var buttonLine: UIButton!
	@IBOutlet var buttonArea: UIButton!
	@IBOutlet var buttonVertex: UIButton!
	var geomDict: [UIButton: GEOMETRY] = [:]

	@IBOutlet var key1Field: UITextField!
	@IBOutlet var key2Field: UITextField!
	@IBOutlet var key3Field: UITextField!
	@IBOutlet var key4Field: UITextField!
	@IBOutlet var key5Field: UITextField!
	@IBOutlet var key6Field: UITextField!
	@IBOutlet var key7Field: UITextField!
	@IBOutlet var value1Field: UITextField!
	@IBOutlet var value2Field: UITextField!
	@IBOutlet var value3Field: UITextField!
	@IBOutlet var value4Field: UITextField!
	@IBOutlet var value5Field: UITextField!
	@IBOutlet var value6Field: UITextField!
	@IBOutlet var value7Field: UITextField!

	@IBOutlet var featureType: UILabel!

	private var tagFields: [UITextField] = []
	var customFeature: CustomFeature!

	var completion: ((_ customFeature: CustomFeature) -> Void)?

	override func viewDidLoad() {
		super.viewDidLoad()

		tableView.rowHeight = UITableView.automaticDimension
		tableView.estimatedRowHeight = 44 // or any reasonable default

		// If we aren't modifying an existing feature then create a new one
		if customFeature == nil {
			customFeature = CustomFeature(featureID: "user-" + UUID().uuidString,
			                              name: "",
			                              geometry: [GEOMETRY.POINT.rawValue],
			                              tags: [:])
		}

		tagFields = [
			key1Field, value1Field,
			key2Field, value2Field,
			key3Field, value3Field,
			key4Field, value4Field,
			key5Field, value5Field,
			key6Field, value6Field,
			key7Field, value7Field
		]

		geomDict = [buttonArea!: .AREA,
		            buttonLine!: .LINE,
		            buttonPoint!: .POINT,
		            buttonVertex!: .VERTEX]

		nameField.text = customFeature.localizedName
		nameField.delegate = self
		nameField.addTarget(self, action: #selector(dataChanged(_:)), for: .editingChanged)

		// initialize tag values
		var idx = 0
		for kv in customFeature.tags {
			tagFields[idx].text = kv.key
			idx += 1
			tagFields[idx].text = kv.value
			idx += 1
		}

		for text in tagFields {
			text.autocapitalizationType = .none
			text.autocorrectionType = .no
			text.spellCheckingType = .no
			text.addTarget(self, action: #selector(dataChanged(_:)), for: .editingChanged)
			text.delegate = self
		}

		// initialize geometry buttons
		for (button, geom) in geomDict {
			button.addTarget(self, action: #selector(geomButtonTapped(_:)), for: .touchUpInside)

			if customFeature.geometry.contains(geom.rawValue) {
				button.isSelected = true
			}
		}

		// update other UI
		dataChanged(self)
	}

	// Determine whether to enable Save button
	@objc func dataChanged(_ sender: Any) {
		let geom = getGeometry()
		let tags = getTags()
		if let name = nameField.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
		   !name.isEmpty,
		   geom.count > 0,
		   tags.count > 0
		{
			navigationItem.rightBarButtonItem?.isEnabled = true
		} else {
			navigationItem.rightBarButtonItem?.isEnabled = false
		}
		let db = PresetsDatabase.shared
		if let geom = geom.first,
		   let geom = GEOMETRY(rawValue: geom),
		   let impliedFeature = db.presetFeatureMatching(tags: tags,
		                                                 geometry: geom,
		                                                 location: AppDelegate.shared.mapView.currentRegion,
		                                                 includeNSI: false),
		   !impliedFeature.tags.isEmpty
		{
			featureType.text = impliedFeature.localizedName
			featureType.textColor = .label
		} else {
			featureType.text = NSLocalizedString("No match", comment: "No value available")
			featureType.textColor = .secondaryLabel
		}
	}

	// Get a dictionary of tags based on key/value text fields
	func getTags() -> [String: String] {
		var tags: [String: String] = [:]
		for i in stride(from: 0, to: tagFields.count, by: 2) {
			let keyField = tagFields[i]
			let valueField = tagFields[i + 1]
			guard
				let key = keyField.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
				!key.isEmpty,
				let value = valueField.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
				!value.isEmpty
			else {
				continue
			}
			tags[key] = value
		}
		return tags
	}

	// Get a list of geometries based on selected buttons
	func getGeometry() -> [String] {
		return geomDict.compactMap { button, geom in
			button.isSelected ? geom.rawValue : nil
		}
	}

	@IBAction func done(_ sender: Any) {
		// remove white space from subdomain list
		guard let name = nameField.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
		      name.count > 0
		else {
			return
		}
		let geom = getGeometry()
		let tags = getTags()

		let feature = CustomFeature(featureID: customFeature.featureID,
		                            name: name,
		                            geometry: geom,
		                            tags: tags)
		completion?(feature)
		navigationController?.popViewController(animated: true)
	}

	@IBAction func cancel(_ sender: Any) {
		navigationController?.popViewController(animated: true)
	}

	@objc func geomButtonTapped(_ sender: UIButton) {
		sender.isSelected.toggle()
		dataChanged(sender)
	}

	@objc func textFieldShouldReturn(_ textField: UITextField) -> Bool {
		textField.resignFirstResponder()
		return true
	}
}
