//
//  PresetValue.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/12/20.
//  Copyright © 2020 Bryce. All rights reserved.
//

import Foundation


// A possible value for a preset key
@objc class PresetValue: NSCoder {
	@objc let name: String
	@objc let details: String?
	@objc let tagValue: String

	@objc init(name: String?, tagValue value: String) {
		self.name = name ?? OsmTags.PrettyTag(value)
		self.details = nil
		self.tagValue = value
	}

	@objc func encode(withCoder coder: NSCoder) {
		coder.encode(name, forKey: "name")
		coder.encode(details, forKey: "details")
		coder.encode(tagValue, forKey: "tagValue")
	}

	@objc required init?(withCoder coder: NSCoder) {
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

	override var description: String {
		return name
	}
}
