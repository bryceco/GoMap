//
//  CustomPreset.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/13/20.
//  Copyright © 2020 Bryce Cogswell. All rights reserved.
//

import Foundation
import UIKit

// A preset the user defined as a custom field
final class PresetKeyUserDefined: PresetKey {
	override public class var supportsSecureCoding: Bool { return true }

	let appliesToKey: String // "" if not used
	let appliesToValue: String // "" if not used

	required init?(coder: NSCoder) {
		if let appliesToKey = coder.decodeObject(forKey: "appliesToKey") as? String,
		   let appliesToValue = coder.decodeObject(forKey: "appliesToValue") as? String
		{
			self.appliesToKey = appliesToKey
			self.appliesToValue = appliesToValue
			super.init(coder: coder)
		} else {
			return nil
		}
	}

	init(appliesToKey: String, // empty string is possible
	     appliesToValue: String, // empty string is possible
	     name: String,
	     tagKey key: String,
	     placeholder: String?,
	     keyboard: UIKeyboardType,
	     capitalize: UITextAutocapitalizationType,
	     autocorrect: UITextAutocorrectionType,
	     presets: [PresetValue])
	{
		self.appliesToKey = appliesToKey
		self.appliesToValue = appliesToValue
		super.init(name: name,
		           type: "",
		           tagKey: key,
		           defaultValue: nil,
		           placeholder: placeholder,
		           keyboard: keyboard,
		           capitalize: capitalize,
		           autocorrect: autocorrect,
		           presets: presets)
	}

	override func encode(with coder: NSCoder) {
		super.encode(with: coder)
		coder.encode(appliesToKey, forKey: "appliesToKey")
		coder.encode(appliesToValue, forKey: "appliesToValue")
	}

	// MARK: Codable

	enum CodingKeys: String, CodingKey {
		case appliesToKey
		case appliesToValue
	}

	required init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		appliesToKey = try container.decode(String.self, forKey: .appliesToKey)
		appliesToValue = try container.decode(String.self, forKey: .appliesToValue)
		try super.init(from: decoder)
	}

	override func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(appliesToKey, forKey: .appliesToKey)
		try container.encode(appliesToValue, forKey: .appliesToValue)
		try super.encode(to: encoder)
	}
}

class PresetKeyUserDefinedList: Codable {
	private(set) var list: [PresetKeyUserDefined] = []
	public static let shared = PresetKeyUserDefinedList()

	init() {
		// First try reading from UserPrefs
		if let data = UserPrefs.shared.userDefinedPresetKeys.value,
		   let list = try? JSONDecoder().decode([PresetKeyUserDefined].self, from: data)
		{
			self.list = list
		} else {
			// Legacy method of storing data
			do {
				let path = PresetKeyUserDefinedList.legacyArchivePath()
				let data = try Data(contentsOf: URL(fileURLWithPath: path))
				let classList = [NSArray.self,
				                 NSMutableString.self,
				                 PresetKeyUserDefined.self,
				                 PresetValue.self]
				list = try NSKeyedUnarchiver.unarchivedObject(ofClasses: classList, from: data)
					as? [PresetKeyUserDefined] ?? []
			} catch {
				list = []
			}
		}
		UserPrefs.shared.userDefinedPresetKeys.onChangePerform { pref in
			guard
				let data = pref.value,
				let list = try? JSONDecoder().decode([PresetKeyUserDefined].self, from: data)
			else {
				return
			}
			self.list = list
		}
	}

	func save() {
		if let encodeData = try? JSONEncoder().encode(list) {
			UserPrefs.shared.userDefinedPresetKeys.value = encodeData
		}
	}

	func addPreset(_ preset: PresetKeyUserDefined, atIndex index: Int) {
		list.insert(preset, at: index)
	}

	func removePresetAtIndex(_ index: Int) {
		list.remove(at: index)
	}

	private class func legacyArchivePath() -> String {
		return ArchivePath.legacyCustomPresets.path()
	}

	// MARK: Codable

	enum CodingKeys: String, CodingKey {
		case list
	}

	required init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		list = try container.decode([PresetKeyUserDefined].self, forKey: .list)
	}

	func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(list, forKey: .list)
	}
}
