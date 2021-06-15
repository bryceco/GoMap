//
//  PresetValue.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/12/20.
//  Copyright © 2020 Bryce Cogswell. All rights reserved.
//

import Foundation


// A possible value for a preset key
final class PresetValue: NSObject, NSSecureCoding {
	static let supportsSecureCoding: Bool = true
	
	let name: String
	let details: String?
	let tagValue: String

	init(name: String?, details: String?, tagValue value: String) {
		self.name = name ?? OsmTags.PrettyTag(value)
		self.details = details
		self.tagValue = value
	}

	func encode(with coder: NSCoder) {
		coder.encode(name, forKey: "name")
		coder.encode(details, forKey: "details")
		coder.encode(tagValue, forKey: "tagValue")
	}

	required init?(coder: NSCoder) {
		self.details = coder.decodeObject(forKey: "details") as? String
		if let name = coder.decodeObject(forKey: "name") as? String,
		   let tagValue = coder.decodeObject(forKey: "tagValue") as? String
		{
			self.name = name
			self.tagValue = tagValue
		} else {
			return nil
		}
	}
}
