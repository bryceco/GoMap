//
//  PresetDisplayKey.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/12/20.
//  Copyright © 2020 Bryce Cogswell. All rights reserved.
//
//

import Foundation
import UIKit

// A key along with information about possible values
class PresetDisplayKey: NSObject, Codable {
	public class var supportsSecureCoding: Bool { return true }

	let name: String // name of the preset, e.g. Hours
	let type: PresetType // the type of value, e.g. "roadspeed"
	let tagKey: String // the key being set, e.g. opening_hours
	let defaultValue: String? // we don't use this, even though it is present
	let placeholder: String // placeholder text in the UITextField
	let presetValues: [PresetDisplayValue]? // array of potential values, or nil if it's free-form text
	let keyboardType: UIKeyboardType
	let autocapitalizationType: UITextAutocapitalizationType
	let autocorrectType: UITextAutocorrectionType

	init(
		name: String,
		type: PresetType,
		tagKey: String,
		defaultValue: String?,
		placeholder: String?,
		keyboard: UIKeyboardType,
		capitalize: UITextAutocapitalizationType,
		autocorrect: UITextAutocorrectionType,
		presetValues: [PresetDisplayValue]?)
	{
		self.name = name
		self.type = type
		self.tagKey = tagKey
		self.placeholder = placeholder
			?? PresetDisplayKey.placeholderForPresets(presetValues)
			?? PresetTranslations.shared.unknownForLocale
		keyboardType = keyboard
		autocapitalizationType = capitalize
		autocorrectType = autocorrect
		self.presetValues = presetValues?.filter({
			!PresetsDatabase.shared.deprecations.contains(key: tagKey, value: $0.tagValue)
		})
		self.defaultValue = defaultValue
	}

	// This is used only for user-defined keys, called from
	// PresetKeyUserDefined() super.init()
	required init?(coder: NSCoder) {
		if let name = coder.decodeObject(forKey: "name") as? String,
		   let tagKey = coder.decodeObject(forKey: "tagKey") as? String,
		   let placeholder = coder.decodeObject(forKey: "placeholder") as? String,
		   let presetList = coder.decodeObject(forKey: "presetList") as? [PresetDisplayValue],
		   let keyboardType = UIKeyboardType(rawValue: coder.decodeInteger(forKey: "keyboardType")),
		   let autocapitalizationType = UITextAutocapitalizationType(rawValue:
		   	coder.decodeInteger(forKey: "capitalize"))
		{
			self.name = name
			type = presetList.count > 0 ? .combo : .text
			self.tagKey = tagKey
			self.placeholder = placeholder
			self.presetValues = presetList
			self.keyboardType = keyboardType
			self.autocapitalizationType = autocapitalizationType
			autocorrectType = UITextAutocorrectionType.no // user can't set this
			defaultValue = nil
		} else {
			return nil
		}
	}

	enum CodingKeys: String, CodingKey {
		case name
		case tagKey
		case presetList
		case presetType
	}

	// This is used only for user-defined keys, called from
	// it's encoder
	func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(name, forKey: .name)
		try container.encode(tagKey, forKey: .tagKey)
		try container.encode(presetValues, forKey: .presetList)
		try container.encode(type, forKey: .presetType)
	}

	// This is used only for user-defined keys, called from
	// its decoder
	required init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		name = try container.decode(String.self, forKey: .name)
		tagKey = try container.decode(String.self, forKey: .tagKey)
		presetValues = try container.decode([PresetDisplayValue].self, forKey: .presetList)
		// originally we didn't save 'type' so it may not exist.
		// If it exists then use it, otherwise infer the type from the number of presets provided
		type = (try? container.decode(PresetType.self, forKey: .presetType)) ??
			((presetValues?.count ?? 0) > 0 ? .combo : .text)

		defaultValue = nil
		placeholder = PresetDisplayKey.placeholderForPresets(presetValues)
			?? PresetTranslations.shared.unknownForLocale
		keyboardType = .default
		autocapitalizationType = .none
		autocorrectType = .no
		super.init()
	}

	func prettyNameForTagValue(_ value: String) -> String {
		if let presetList = presetValues {
			for presetValue in presetList {
				if presetValue.tagValue == value {
					return presetValue.name
				}
			}
		}
		return value
	}

	func tagValueForPrettyName(_ value: String) -> String {
		if let presetList = presetValues {
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
		switch type {
		case .defaultCheck, .check, .onewayCheck:
			return true
		default:
			return false
		}
	}

	private class func placeholderForPresets(_ presets: [PresetDisplayValue]?) -> String? {
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
