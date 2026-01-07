//
//  CustomFieldController.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 8/21/14.
//  Copyright (c) 2014 Bryce Cogswell. All rights reserved.
//

import UIKit

class CustomFieldController: UITableViewController {
	@IBOutlet var nameField: UITextField!
	@IBOutlet var appliesToTagField: UITextField!
	@IBOutlet var appliesToValueField: UITextField!
	@IBOutlet var keyField: UITextField!
	@IBOutlet var value1Field: UITextField!
	@IBOutlet var value2Field: UITextField!
	@IBOutlet var value3Field: UITextField!
	@IBOutlet var value4Field: UITextField!
	@IBOutlet var value5Field: UITextField!
	@IBOutlet var value6Field: UITextField!
	@IBOutlet var value7Field: UITextField!
	@IBOutlet var value8Field: UITextField!
	@IBOutlet var value9Field: UITextField!
	@IBOutlet var value10Field: UITextField!
	@IBOutlet var value11Field: UITextField!
	@IBOutlet var value12Field: UITextField!
	private var valueFieldList: [UITextField] = []

	var customField: PresetDisplayKeyUserDefined?
	var completion: ((_ customPreset: PresetDisplayKeyUserDefined?) -> Void)?

	@IBAction func contentChanged(_ sender: Any) {
		if (nameField.text?.count ?? 0) > 0, (keyField.text?.count ?? 0) > 0 {
			navigationItem.rightBarButtonItem?.isEnabled = true
		} else {
			navigationItem.rightBarButtonItem?.isEnabled = false
		}
	}

	@IBAction func done(_ sender: Any) {
		// remove white space from subdomain list
		let name = nameField.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
		let key = keyField.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
		if name.count == 0 || key.count == 0 {
			return
		}
		let appliesToKey = appliesToTagField.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
		let appliesToVal = appliesToValueField.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
		var presetValues: [PresetDisplayValue] = []
		for field in valueFieldList {
			let value = field.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
			if value != "" {
				let preset = PresetDisplayValue(name: nil, details: nil, icon: nil, tagValue: value)
				presetValues.append(preset)
			}
		}
		let keyboard: UIKeyboardType = .default
		let capitalize: UITextAutocapitalizationType = .none
		let autocorrect: UITextAutocorrectionType = .no

		customField = PresetDisplayKeyUserDefined(
			appliesToKey: appliesToKey,
			appliesToValue: appliesToVal,
			name: name,
			tagKey: key,
			placeholder: nil,
			keyboard: keyboard,
			capitalize: capitalize,
			autocorrect: autocorrect,
			presetValues: presetValues)
		completion?(customField)
		navigationController?.popViewController(animated: true)
	}

	@IBAction func cancel(_ sender: Any) {
		navigationController?.popViewController(animated: true)
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		valueFieldList = [
			value1Field,
			value2Field,
			value3Field,
			value4Field,
			value5Field,
			value6Field,
			value7Field,
			value8Field,
			value9Field,
			value10Field,
			value11Field,
			value12Field
		]

		nameField.text = customField?.name ?? ""
		appliesToTagField.text = customField?.appliesToKey ?? ""
		appliesToValueField.text = customField?.appliesToValue ?? ""
		keyField.text = customField?.tagKey ?? ""

		var idx = 0
		for textField in valueFieldList {
			if idx >= (customField?.presetValues?.count ?? 0) {
				break
			}
			let preset = customField?.presetValues?[idx]
			textField.text = preset?.tagValue
			idx += 1
		}
	}
}
