//
//  PresetKey.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/12/20.
//  Copyright © 2020 Bryce Cogswell. All rights reserved.
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

// A key along with information about possible values
class PresetKey: NSObject, NSSecureCoding {
	public class var supportsSecureCoding: Bool { return true }

	let name: String // name of the preset, e.g. Hours
	let type: String // the type of value, e.g. "roadspeed"
	let tagKey: String // the key being set, e.g. opening_hours
	let defaultValue: String?
	let placeholder: String // placeholder text in the UITextField
	let presetList: [PresetValue]? // array of potential values, or nil if it's free-form text
	let keyboardType: UIKeyboardType
	let autocapitalizationType: UITextAutocapitalizationType
	let autocorrectType: UITextAutocorrectionType

	init(
		name: String,
		type: String,
		tagKey tag: String,
		defaultValue: String?,
		placeholder: String?,
		keyboard: UIKeyboardType,
		capitalize: UITextAutocapitalizationType,
		autocorrect: UITextAutocorrectionType,
		presets: [PresetValue]?)
	{
		self.name = name
		self.type = type
		tagKey = tag
		self.placeholder = placeholder
			?? PresetKey.placeholderForPresets(presets)
			?? PresetsDatabase.shared.unknownForLocale
		keyboardType = keyboard
		autocapitalizationType = capitalize
		autocorrectType = autocorrect
		presetList = presets
		self.defaultValue = defaultValue
	}

	// This is used only for user-defined keys, call from
	// PresetKeyUserDefined() super.init()
	required init?(coder: NSCoder) {
		if let name = coder.decodeObject(forKey: "name") as? String,
		   let tagKey = coder.decodeObject(forKey: "tagKey") as? String,
		   let placeholder = coder.decodeObject(forKey: "placeholder") as? String,
		   let presetList = coder.decodeObject(forKey: "presetList") as? [PresetValue],
		   let keyboardType = UIKeyboardType(rawValue: coder.decodeInteger(forKey: "keyboardType")),
		   let autocapitalizationType = UITextAutocapitalizationType(rawValue:
		   	coder.decodeInteger(forKey: "capitalize"))
		{
			self.name = name
			type = ""
			self.tagKey = tagKey
			self.placeholder = placeholder
			self.presetList = presetList
			self.keyboardType = keyboardType
			self.autocapitalizationType = autocapitalizationType
			autocorrectType = UITextAutocorrectionType.no // user can't set this
			defaultValue = nil
		} else {
			return nil
		}
	}

	func encode(with coder: NSCoder) {
		coder.encode(name, forKey: "name")
		coder.encode(tagKey, forKey: "tagKey")
		coder.encode(placeholder, forKey: "placeholder")
		coder.encode(presetList, forKey: "presetList")
		coder.encode(keyboardType.rawValue, forKey: "keyboardType")
		coder.encode(autocapitalizationType.rawValue, forKey: "capitalize")
		// coder.encode(autocorrectType.rawValue, forKey: "autocorrect")
	}

	func prettyNameForTagValue(_ value: String) -> String {
		if let presetList = presetList {
			for presetValue in presetList {
				if presetValue.tagValue == value {
					return presetValue.name
				}
			}
		}
		return value
	}

	func tagValueForPrettyName(_ value: String) -> String {
		if let presetList = presetList {
			for presetValue in presetList {
				let diff: ComparisonResult? = presetValue.name.compare(
					value,
					options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
					range: nil,
					locale: .current)
				if diff == .orderedSame {
					return presetValue.tagValue
				}
			}
		}
		return value
	}

	func isYesNo() -> Bool {
		if let presetList = presetList,
		   presetList.count == 2,
		   presetList[0].tagValue == "yes",
		   presetList[1].tagValue == "no"
		{
			return true
		}
		return false
	}

	private class func placeholderForPresets(_ presets: [PresetValue]?) -> String? {
		// use the first 3 values as the placeholder text
		if let presets = presets,
		   presets.count > 1
		{
			var s = ""
			for i in 0..<min(3, presets.count) {
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
		return "\(tagKey): \(name)"
	}
}
