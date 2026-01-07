//
//  PresetDisplayValue.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/12/20.
//  Copyright © 2020 Bryce Cogswell. All rights reserved.
//

import Foundation

// A possible value for a preset key
final class PresetDisplayValue: NSObject, NSSecureCoding, Codable {
	static let supportsSecureCoding = true

	let name: String
	let details: String?
	let tagValue: String
	let icon: String?

	init(name: String?, details: String?, icon: String?, tagValue value: String) {
		self.name = name ?? OsmTags.PrettyTag(value)
		self.details = details
		self.icon = icon
		tagValue = value
	}

	func encode(with coder: NSCoder) {
		coder.encode(name, forKey: "name")
		coder.encode(details, forKey: "details")
		coder.encode(tagValue, forKey: "tagValue")
	}

	required init?(coder: NSCoder) {
		details = coder.decodeObject(forKey: "details") as? String
		if let name = coder.decodeObject(forKey: "name") as? String,
		   let tagValue = coder.decodeObject(forKey: "tagValue") as? String
		{
			self.name = name
			self.tagValue = tagValue
			icon = nil
		} else {
			return nil
		}
	}

	enum CodingKeys: String, CodingKey {
		case name
		case tagValue
	}

	required init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		name = try container.decode(String.self, forKey: .name)
		tagValue = try container.decode(String.self, forKey: .tagValue)
		details = nil
		icon = nil
		super.init()
	}

	func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(name, forKey: .name)
		try container.encode(tagValue, forKey: .tagValue)
	}

	override var description: String {
		return "PresetValue \"\(name.isEmpty ? tagValue : name)\""
	}
}
