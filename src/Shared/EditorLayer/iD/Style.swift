// Copyright (c) 2017, iD Contributors
//
// Permission to use, copy, modify, and/or distribute this software for any
// purpose with or without fee is hereby granted, provided that the above
// copyright notice and this permission notice appear in all copies.
//
// THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
// REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY
// AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
// INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
// LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR
// OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
// PERFORMANCE OF THIS SOFTWARE.

//
//  Style.swift
//  Go Map!!
//
//  Created by Boris Verkhovskiy on 2024-04-02.
//

import Foundation

let primaries = [
	"building", "highway", "railway", "waterway", "aeroway", "aerialway",
	"piste:type", "boundary", "power", "amenity", "natural", "landuse",
	"leisure", "military", "place", "man_made", "route", "attraction",
	"roller_coaster", "building:part", "indoor"
]
let statuses = [
	// nonexistent, might be built
	"proposed", "planned",
	// under maintentance or between groundbreaking and opening
	"construction",
	// existent but not functional
	"disused",
	// dilapidated to nonexistent
	"abandoned", "was",
	// nonexistent, still may appear in imagery
	"dismantled", "razed", "demolished", "destroyed", "removed", "obliterated",
	// existent occasionally, e.g. stormwater drainage basin
	"intermittent"
]
let secondaries = [
	"oneway", "bridge", "tunnel", "embankment", "cutting", "barrier",
	"surface", "tracktype", "footway", "crossing", "service", "sport",
	"public_transport", "location", "parking", "golf", "type", "leisure",
	"man_made", "indoor", "construction", "proposed"
]

let osmPathHighwayTagValues = [
	"path": true, "footway": true, "cycleway": true, "bridleway": true, "pedestrian": true, "corridor": true,
	"steps": true
]

let osmPavedTags: [String: [String: Bool]] = [
	"surface": [
		"paved": true,
		"asphalt": true,
		"concrete": true,
		"chipseal": true,
		"concrete:lanes": true,
		"concrete:plates": true
	],
	"tracktype": [
		"grade1": true
	]
]

let osmSemipavedTags: [String: [String: Bool]] = [
	"surface": [
		"cobblestone": true,
		"cobblestone:flattened": true,
		"unhewn_cobblestone": true,
		"sett": true,
		"paving_stones": true,
		"metal": true,
		"wood": true
	]
]

extension RenderInfo {
	static func style(tags: [String: String]) -> RenderInfo? {
		var primary: String?
		var primaryValue: String?
		var status: String?
		var surface: String?

		// Pick at most one primary classification tag.
		for key in primaries {
			if let val = tags[key], val != "no" {
				primary = key
				if statuses.contains(val) {
					status = val
				} else {
					primaryValue = val
				}

				break
			}
		}

		if primary == nil {
			for stat in statuses {
				for prim in primaries {
					let key = "\(stat):\(prim)"
					if let val = tags[key], val != "no" {
						status = stat
						break
					}
				}
			}
		}

		// Add at most one status tag, only if relates to primary tag..
		if status == nil {
			for stat in statuses {
				if let val = tags[stat], val != "no" {
					if val == "yes" {
						status = stat
					} else if let prim = primary, prim == val {
						status = stat
					} else if primary == nil, primaries.contains(val) {
						status = stat
						primary = val
					}

					if status != nil {
						break
					}
				}
			}
		}

		// For highways, look for surface tagging..
		if (primary == "highway" && !(osmPathHighwayTagValues[tags["highway"] ?? ""] ?? false)) || primary ==
			"aeroway"
		{
			surface = tags["highway"] == "track" ? "unpaved" : "paved"
			for (key, val) in tags {
				if let paved = osmPavedTags[key]?[val] {
					surface = paved ? "paved" : "unpaved"
				}
				if let semipaved = osmSemipavedTags[key]?[val] {
					if semipaved {
						surface = "semipaved"
					}
				}
			}
		}

		return RenderInfo.match(
			primary: primary,
			primaryValue: primaryValue,
			status: status,
			surface: surface,
			tags: tags)
	}
}
