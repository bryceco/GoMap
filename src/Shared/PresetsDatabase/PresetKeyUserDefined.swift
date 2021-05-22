//
//  CustomPreset.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/13/20.
//  Copyright © 2020 Bryce. All rights reserved.
//

import Foundation


// A preset the user defined as a custom preset
@objc class PresetKeyUserDefined: PresetKey {
	override public class var supportsSecureCoding: Bool { return true }

	@objc let appliesToKey: String		// "" if not used
	@objc let appliesToValue: String	// "" if not used

	@objc required init?(coder: NSCoder) {
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

	@objc init(appliesToKey: String,	// empty string is possible
			   appliesToValue: String,	// empty string is possible
			   name: String,
			   tagKey key: String,
			   placeholder: String?,
			   keyboard: UIKeyboardType,
			   capitalize: UITextAutocapitalizationType,
			   presets: [PresetValue])
	{
		self.appliesToKey = appliesToKey
		self.appliesToValue = appliesToValue
		super.init(name: name, tagKey: key, defaultValue: nil, placeholder: placeholder, keyboard: keyboard, capitalize: capitalize, presets: presets)
	}

	@objc override func encode(with coder: NSCoder) {
		super.encode(with: coder)
		coder.encode(appliesToKey, forKey: "appliesToKey")
		coder.encode(appliesToValue, forKey: "appliesToValue")
	}
}

@objc class PresetKeyUserDefinedList: NSObject {
	@objc var list: [PresetKeyUserDefined] = []

	@objc public static let shared = PresetKeyUserDefinedList()

	override init()
	{
		super.init()
		self.load()
	}

	func load() {
		do {
			// some people experience a crash during loading...
			let path = PresetKeyUserDefinedList.archivePath()
			// decode
			if #available(iOS 11.0, *) {
				let data = try Data(contentsOf: URL(fileURLWithPath: path))
				let classList = [NSArray.self,
								 PresetKeyUserDefined.self,
								 PresetValue.self]
				list = try! NSKeyedUnarchiver.unarchivedObject(ofClasses: classList, from: data) as? [PresetKeyUserDefined] ?? []
			} else {
				let oldList = NSKeyedUnarchiver.unarchiveObject(withFile: path)
				list = oldList as? [PresetKeyUserDefined] ?? []
			}
		} catch {
			print("error loading custom presets")
			list = []
		}
	}

	@objc func save() {
		let path = PresetKeyUserDefinedList.archivePath()
		if #available(iOS 11.0, *) {
			do {
				let data = try? NSKeyedArchiver.archivedData(withRootObject: list as NSArray, requiringSecureCoding:true)
				try data?.write(to: URL(fileURLWithPath: path))
			} catch {}
		} else {
			NSKeyedArchiver.archiveRootObject(list as NSArray, toFile: path)
		}
	}

	@objc func addPreset(_ preset: PresetKeyUserDefined, atIndex index: Int) {
		list.insert(preset, at: index)
	}

	@objc func removePresetAtIndex(_ index: Int ) {
		list.remove(at: index)
	}

	private class func archivePath() -> String {
		let paths = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).map(\.path)
		let cacheDirectory = paths[0]
		let fullPath = URL(fileURLWithPath: cacheDirectory).appendingPathComponent("CustomPresetList.data").path
		return fullPath
	}
}
