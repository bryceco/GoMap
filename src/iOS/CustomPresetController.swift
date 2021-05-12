//  Converted to Swift 5.2 by Swiftify v5.2.23024 - https://swiftify.com/
//
//  CustomPresetController.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 8/21/14.
//  Copyright (c) 2014 Bryce Cogswell. All rights reserved.
//

import UIKit

class CustomPresetController: UITableViewController {
    @IBOutlet var _nameField: UITextField!
    @IBOutlet var _appliesToTagField: UITextField!
    @IBOutlet var _appliesToValueField: UITextField!
    @IBOutlet var _keyField: UITextField!
    @IBOutlet var _value1Field: UITextField!
    @IBOutlet var _value2Field: UITextField!
    @IBOutlet var _value3Field: UITextField!
    @IBOutlet var _value4Field: UITextField!
    @IBOutlet var _value5Field: UITextField!
    @IBOutlet var _value6Field: UITextField!
    @IBOutlet var _value7Field: UITextField!
    @IBOutlet var _value8Field: UITextField!
    @IBOutlet var _value9Field: UITextField!
    @IBOutlet var _value10Field: UITextField!
    @IBOutlet var _value11Field: UITextField!
    @IBOutlet var _value12Field: UITextField!
    var _valueFieldList: [UITextField] = []

    var customPreset: PresetKeyUserDefined?
    var completion: ((_ customPreset: PresetKeyUserDefined?) -> Void)?

    @IBAction func contentChanged(_ sender: Any) {
        if (_nameField.text?.count ?? 0) > 0 && (_keyField.text?.count ?? 0) > 0 {
            navigationItem.rightBarButtonItem?.isEnabled = true
        } else {
            navigationItem.rightBarButtonItem?.isEnabled = false
        }
    }

    @IBAction func done(_ sender: Any) {
        // remove white space from subdomain list
        let name = _nameField.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        let key = _keyField.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        if name.count == 0 || key.count == 0 {
            return
        }
        let appliesToKey = _appliesToTagField.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        let appliesToVal = _appliesToValueField.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        var presets: [PresetValue] = []
        for field in _valueFieldList {
            let value = field.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
            if value.count != 0 {
                let preset = PresetValue(name: nil, details: nil, tagValue: value)
                presets.append(preset)
            }
        }
        let keyboard: UIKeyboardType = .default
        let capitalize: UITextAutocapitalizationType = .none

        customPreset = PresetKeyUserDefined(
            appliesToKey: appliesToKey,
            appliesToValue: appliesToVal,
            name: name,
            tagKey: key,
            placeholder: nil,
            keyboard: keyboard,
            capitalize: capitalize,
            presets: presets)
        completion?(customPreset)
        navigationController?.popViewController(animated: true)
    }

    @IBAction func cancel(_ sender: Any) {
        navigationController?.popViewController(animated: true)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        _valueFieldList = [
            _value1Field,
            _value2Field,
            _value3Field,
            _value4Field,
            _value5Field,
            _value6Field,
            _value7Field,
            _value8Field,
            _value9Field,
            _value10Field,
            _value11Field,
            _value12Field
        ]

        _nameField.text = customPreset?.name ?? ""
        _appliesToTagField.text = customPreset?.appliesToKey ?? ""
        _appliesToValueField.text = customPreset?.appliesToValue ?? ""
        _keyField.text = customPreset?.tagKey ?? ""

        var idx = 0
        for textField in _valueFieldList {
            if idx >= (customPreset?.presetList?.count ?? 0) {
                break
            }
            let preset = customPreset?.presetList?[idx]
            textField.text = preset?.tagValue
            idx += 1
        }
    }
}
