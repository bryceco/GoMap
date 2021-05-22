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

	@objc func multiComboSummary(ofDict dict:[String:String]?, isPlaceholder:Bool) -> String
	{
		var summary = ""
		for preset in presetKeys {
			if let preset = preset as? PresetKey,
			   let values = preset.presetList,
			   values.count == 2,
			   values[0].tagValue == "yes",
			   values[1].tagValue == "no"
			{
				if let v = isPlaceholder ? "yes" : dict?[ preset.tagKey ],
				   OsmTags.isOsmBooleanTrue( v )
				{
					if summary.isEmpty {
						summary = preset.name
					} else {
						summary = summary + ", " + preset.name
					}
				}
			} else {
				// it's not a multiCombo
				return ""
			}
		}
		return summary
	}
}

