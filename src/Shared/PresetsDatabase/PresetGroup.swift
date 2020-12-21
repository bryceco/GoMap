//
//  PresetGroup.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/12/20.
//  Copyright © 2020 Bryce. All rights reserved.
//

import Foundation


// A group of related tags, such as address tags, organized for display purposes
// A group becomes a Section in UITableView
class PresetGroup: NSObject {
	@objc let name: String?				// e.g. Address
	@objc let presetKeys: [AnyHashable]	// either PresetKey or PresetGroup
	@objc var isDrillDown = false

	init(name: String?, tags: [AnyHashable]) {
#if DEBUG
		if tags.count > 0 {
			assert((tags.last is PresetKey) || (tags.last is PresetGroup)) // second case for drill down group
		}
#endif
		self.name = name
		self.presetKeys = tags
		super.init()
	}

	convenience init(fromMerger p1: PresetGroup, with p2: PresetGroup) {
		self.init(name: p1.name, tags: p1.presetKeys + p2.presetKeys)
	}

	override var description: String {
		var text = "\(name ?? "<unknown>"):\n"
		for key in presetKeys {
			text += "   \(key.description)\n"
		}
		return text
	}
}

