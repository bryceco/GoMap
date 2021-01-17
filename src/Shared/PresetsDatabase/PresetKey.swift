//
//  PresetKey.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/12/20.
//  Copyright © 2020 Bryce. All rights reserved.
//
//

import Foundation
import UIKit

#if os(iOS)
#else
typealias UIKeyboardType = Int
typealias UITextAutocapitalizationType = Int
#if !os(iOS)
let UIKeyboardTypeDefault = 0
let UIKeyboardTypeNumbersAndPunctuation = 1
let UIKeyboardTypeURL = 2
let UITextAutocapitalizationTypeNone = 0
let UITextAutocapitalizationTypeSentences = 1
let UITextAutocapitalizationTypeWords = 2
#endif

#endif

let GEOMETRY_AREA = "area"
let GEOMETRY_WAY = "line"
let GEOMETRY_NODE = "point"
let GEOMETRY_VERTEX = "vertex"

// A key along with information about possible values
class PresetKey: NSCoder {
	@objc let name: String					// name of the preset, e.g. Hours
	@objc let tagKey: String				// the key being set, e.g. opening_hours
	@objc let defaultValue: String?
	@objc let placeholder: String			// placeholder text in the UITextField
	@objc let presetList: [PresetValue]?	// array of potential values, or nil if it's free-form text
	@objc let keyboardType: UIKeyboardType
	@objc let autocapitalizationType: UITextAutocapitalizationType

	init(
		name: String,
		tagKey tag: String,
		defaultValue: String?,
		placeholder: String?,
		keyboard: UIKeyboardType,
		capitalize: UITextAutocapitalizationType,
		presets: [PresetValue]?
	) {
		self.name = name
		self.tagKey = tag
		self.placeholder = placeholder ?? PresetKey.placeholderForPresets(presets) ?? ""
		self.keyboardType = keyboard
		self.autocapitalizationType = capitalize
		self.presetList = presets
		self.defaultValue = defaultValue
	}

	@objc required init?(withCoder coder: NSCoder) {
		if let name = coder.decodeObject(forKey: "name") as? String,
		   let tagKey = coder.decodeObject(forKey: "tagKey") as? String,
		   let placeholder = coder.decodeObject(forKey: "placeholder") as? String,
		   let presetList = coder.decodeObject(forKey: "presetList") as? [PresetValue],
		   let keyboardType = UIKeyboardType(rawValue: coder.decodeInteger(forKey: "keyboardType")),
		   let autocapitalizationType = UITextAutocapitalizationType(rawValue: coder.decodeInteger(forKey: "capitalize"))
		{
			self.name = name
			self.tagKey = tagKey
			self.placeholder = placeholder
			self.presetList = presetList
			self.keyboardType = keyboardType
			self.autocapitalizationType = autocapitalizationType
			self.defaultValue = nil
		} else {
			return nil
		}
	}

	@objc func encode(withCoder coder: NSCoder) {
		coder.encode(name, forKey: "name")
		coder.encode(tagKey, forKey: "tagKey")
		coder.encode(placeholder, forKey: "placeholder")
		coder.encode(presetList, forKey: "presetList")
		coder.encode(keyboardType.rawValue, forKey: "keyboardType")
		coder.encode(autocapitalizationType.rawValue, forKey: "capitalize")
	}

	@objc func prettyNameForTagValue(_ value: String) -> String {
		if let presetList = presetList {
			for presetValue in presetList {
				if presetValue.tagValue == value {
					return presetValue.name
				}
			}
		}
		return value
	}

	@objc func tagValueForPrettyName(_ value: String) -> String {
		if let presetList = presetList {
			for presetValue in presetList {
				let diff: ComparisonResult? = presetValue.name.compare(value, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], range: nil, locale: .current)
				if diff == .orderedSame {
					return presetValue.tagValue
				}
			}
		}
		return value
	}

	class private func placeholderForPresets(_ presets:[PresetValue]?) -> String?
	{
		// use the first 3 values as the placeholder text
		if let presets = presets,
		   presets.count > 1
		{
			var s = ""
			for i in 0..<min(3,presets.count) {
				let p = presets[i]
				if p.name.count >= 20 {
					continue
				}
				if s.count != 0 {
					s += ", "
				}
				s += p.name
			}
			s += "..."
			return s
		}
		return nil
	}

	override var description: String {
		return name
	}
}
