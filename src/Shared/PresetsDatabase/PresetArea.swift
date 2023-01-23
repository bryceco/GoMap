//
//  PresetArea.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 1/23/23.
//  Copyright © 2023 Bryce. All rights reserved.
//

import Foundation

class PresetArea {
	static let shared = PresetArea(withPresets: PresetsDatabase.shared.stdPresets)

	private static let osmAreaKeysExceptions = [
		"highway": [
			"elevator": true,
			"rest_area": true,
			"services": true
		],
		"public_transport": [
			"platform": true
		],
		"railway": [
			"platform": true,
			"roundhouse": true,
			"station": true,
			"traverser": true,
			"turntable": true,
			"wash": true
		],
		"traffic_calming": [
			"island": true
		],
		"waterway": [
			"dam": true
		]
	]

	let osmAreaKeys: [String: [String: Bool]]

	init(withPresets presets: [String: PresetFeature]) {
		// The ignore list is for keys that imply lines. (We always add `area=yes` for exceptions)
		let ignore = [
			"barrier": true,
			"highway": true,
			"footway": true,
			"railway": true,
			"junction": true,
			"traffic_calming": true,
			"type": true
		]
		var areaKeys = [String: [String: Bool]]()

		// keeplist
		for preset in presets.values {
			// very specific tags aren't suitable for whitelist, since we don't know which key is primary
			// (in iD the JSON order is preserved and it would be the first key)
			guard preset.tags.count == 1,
			      let key = preset.tags.keys.first,
			      ignore[key] == nil
			else { continue }

			if preset.geometry.contains(GEOMETRY.AREA.rawValue) { // probably an area..
				areaKeys[key] = [:]
			}
		}

		// discardlist
		for preset in presets.values {
			for (key, value) in preset.addTags {
				// examine all addTags to get a better sense of what can be tagged on lines - #6800
				if areaKeys[key] != nil, // probably an area...
				   preset.geometry.contains(GEOMETRY.LINE.rawValue), // but sometimes a line
				   value != "*"
				{
					areaKeys[key]![value] = true
				}
			}
		}
		osmAreaKeys = areaKeys
	}

	func isArea(_ way: OsmWay) -> Bool {
		if let value = way.tags["area"] {
			if OsmTags.isOsmBooleanTrue(value) {
				return true
			}
			if OsmTags.isOsmBooleanFalse(value) {
				return false
			}
		}
		if !way.isClosed() {
			return false
		}
		if way.tags.count == 0 {
			return true // newly created closed way
		}
		for (key, val) in way.tags {
			if let area = osmAreaKeys[key],
			   area[val] == nil
			{
				// it contains a key indicating an area, and the value isn't in the exclude list
				return true
			}
			if Self.osmAreaKeysExceptions[key]?[val] != nil {
				return true
			}
		}
		return false
	}

	// Add area=yes if necessary.
	// This is necessary if the geometry is already an area (e.g. user drew an area) AND any of:
	// 1. chosen preset could be either an area or a line (`barrier=city_wall`)
	// 2. chosen preset doesn't have a key in osmAreaKeys (`railway=station`),
	//    and is not an "exceptional area" tag (e.g. `waterway=dam`)
	func needsAreaKey(forTags tags: [String: String], geometry: GEOMETRY, feature: PresetFeature) -> Bool {
		guard
			geometry == .AREA,
			!(feature.addTags["area"] != nil)
		else {
			return false
		}
		for (k, v) in feature.addTags {
			if !feature.geometry.contains(GEOMETRY.LINE.rawValue),
			   osmAreaKeys[k] != nil
			{
				return false
			}
			if Self.osmAreaKeysExceptions[k]?[v] != nil {
				return false
			}
		}
		return true
	}
}
