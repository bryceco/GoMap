//
//  CustomFeatureController.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 3/10/25.
//  Copyright © 2025 Bryce Cogswell. All rights reserved.
//

import UIKit

class CustomFeatureController: UITableViewController {
	@IBOutlet var nameField: UITextField!

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

	private var textFields: [UITextField] = []
	var customFeature: PresetFeature?

	var completion: ((_ customFeature: PresetFeature?) -> Void)?

	@IBAction func contentChanged(_ sender: Any) {
		guard let name = nameField.text,
		      !name.isEmpty,
		      let key = key1Field.text,
		      !key.isEmpty,
		      let value = value1Field.text,
		      !value.isEmpty
		else {
			navigationItem.rightBarButtonItem?.isEnabled = false
			return
		}
		navigationItem.rightBarButtonItem?.isEnabled = true
	}

	@IBAction func done(_ sender: Any) {
		// remove white space from subdomain list
		guard let name = nameField.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
		      name.count > 0
		else {
			return
		}

		var tags: [String: String] = [:]
		for field in textFields {
			guard
				let key = field.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
				!key.isEmpty,
				let value = field.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
				!value.isEmpty
			else {
				continue
			}
			tags[key] = value
		}
		let impliedFeature = PresetsDatabase.shared.presetFeatureMatching(
			tags: tags,
			geometry: .POINT,
			location: AppDelegate.shared.mapView.currentRegion,
			includeNSI: true)
		let feature = PresetFeature(_addTags: [:],
		                            aliases: [],
		                            featureID: "user-" + UUID().uuidString,
		                            fieldsWithRedirect: impliedFeature?.fieldsWithRedirect ?? [],
		                            geometry: impliedFeature?.geometry ?? [],
		                            icon: nil,
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
		completion?(feature)
		navigationController?.popViewController(animated: true)
	}

	@IBAction func cancel(_ sender: Any) {
		navigationController?.popViewController(animated: true)
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		textFields = [
			key1Field, value1Field,
			key2Field, value2Field,
			key3Field, value3Field,
			key4Field, value4Field,
			key5Field, value5Field,
			key6Field, value6Field,
			key7Field, value7Field
		]

		nameField.text = customFeature?.name ?? ""

		var idx = 0
		for kv in customFeature?.tags ?? [:] {
			textFields[idx].text = kv.key
			idx += 1
			textFields[idx].text = kv.value
			idx += 1
		}
	}
}
