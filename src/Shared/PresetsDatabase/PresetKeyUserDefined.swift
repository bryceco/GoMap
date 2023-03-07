//
//  CustomPreset.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/13/20.
//  Copyright © 2020 Bryce Cogswell. All rights reserved.
//

import Foundation
import UIKit

// A preset the user defined as a custom preset
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
	let key = "userDefinedPresetKeys"
	private(set) var list: [PresetKeyUserDefined] = []
	private let userPrefs: OsmUserPrefs

	public static let shared = PresetKeyUserDefinedList()

	init() {
		do {
			let path = PresetKeyUserDefinedList.archivePath()
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

		userPrefs = OsmUserPrefs()
		userPrefs.download({ success in
			guard success,
			      let prefString = self.userPrefs.get(key: self.key)
			else {
				return
			}
			let data = Data(prefString.utf8)
			if let list = try? JSONDecoder().decode([PresetKeyUserDefined].self, from: data) {
				self.list = list
			}
		})
	}

	func save() {
		let path = PresetKeyUserDefinedList.archivePath()
		let data = try? NSKeyedArchiver.archivedData(withRootObject: list as NSArray, requiringSecureCoding: true)
		try? data?.write(to: URL(fileURLWithPath: path))

		if let encodeData = try? JSONEncoder().encode(list),
		   let encodeString = String(data: encodeData, encoding: .utf8)
		{
			userPrefs.set(key: key, value: encodeString)
			userPrefs.upload({ _ in })
		}
	}

	func addPreset(_ preset: PresetKeyUserDefined, atIndex index: Int) {
		list.insert(preset, at: index)
	}

	func removePresetAtIndex(_ index: Int) {
		list.remove(at: index)
	}

	private class func archivePath() -> String {
		let paths = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).map(\.path)
		let cacheDirectory = paths[0]
		let fullPath = URL(fileURLWithPath: cacheDirectory).appendingPathComponent("CustomPresetList.data").path
		return fullPath
	}

	// MARK: Codable

	enum CodingKeys: String, CodingKey {
		case list
	}

	required init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		list = try container.decode([PresetKeyUserDefined].self, forKey: .list)
		userPrefs = OsmUserPrefs()
	}

	func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(list, forKey: .list)
	}
}
