//
//  PresetGroup.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/12/20.
//  Copyright © 2020 Bryce Cogswell. All rights reserved.
//

import Foundation

enum PresetKeyOrGroup {
	case key(PresetKey)
	case group(PresetGroup)

	func flattenedPresets() -> [PresetKey] {
		switch self {
		case let .key(presetKey):
			return [presetKey]
		case let .group(group):
			return group.presetKeys.flatMap { $0.flattenedPresets() }
		}
	}
}

// A group of related tags, such as address tags, organized for display purposes
// A group becomes a Section in UITableView
final class PresetGroup {
	let name: String? // e.g. Address
	let presetKeys: [PresetKeyOrGroup]
	let isDrillDown: Bool
	let usesBoth: Bool // a special group that supports things like left/right/both

	init(name: String?, tags: [PresetKeyOrGroup], isDrillDown: Bool = false, usesBoth: Bool) {
		self.name = name
		presetKeys = tags
		self.isDrillDown = isDrillDown
		self.usesBoth = usesBoth
	}

	convenience init(fromMerger p1: PresetGroup, with p2: PresetGroup, sort: Bool) {
		var list = p1.presetKeys + p2.presetKeys
		if sort {
			list.sort(by: { a, b in
				if case let .key(aa) = a,
				   case let .key(bb) = b
				{
					return aa.name < bb.name
				}
				DbgAssert(false)
				return false // shouldn't happen
			})
		}
		self.init(name: p1.name, tags: list, usesBoth: p1.usesBoth)
	}

	var description: String {
		var text = "\(name ?? "<unknown>"):\n"
		for key in presetKeys {
			switch key {
			case let .key(key): text += "   \(key.description)\n"
			case let .group(group): text += "   \(group.description)\n"
			}
		}
		return text
	}

	func multiComboSummary(ofDict dict: [String: String]?, isPlaceholder: Bool) -> String {
		var summary = ""
		for preset in presetKeys {
			if case let .key(preset) = preset,
			   let values = preset.presetList,
			   values.count == 2,
			   values[0].tagValue == "yes",
			   values[1].tagValue == "no"
			{
				if let v = isPlaceholder ? "yes" : dict?[preset.tagKey],
				   OsmTags.isOsmBooleanTrue(v)
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
