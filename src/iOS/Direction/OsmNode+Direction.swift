//
//  OsmNode+Direction.swift
//  Go Map!!
//
//  Created by Wolfgang Timme on 4/10/19.
//  Copyright © 2019 Bryce Cogswell. All rights reserved.
//

import Foundation

extension OsmNode {
	static let cardinalDictionary: [String: Float] = [
		"north": 0,
		"N": 0,
		"NNE": 22.5,
		"NE": 45,
		"ENE": 67.5,
		"east": 90,
		"E": 90,
		"ESE": 112.5,
		"SE": 135,
		"SSE": 157.5,
		"south": 180,
		"S": 180,
		"SSW": 202.5,
		"SW": 225,
		"WSW": 247.5,
		"west": 270,
		"W": 270,
		"WNW": 292.5,
		"NW": 315,
		"NNW": 337.5
	]

	/// The direction in which the node is facing.
	/// If the node does not have a direction value return `nil`.
	var direction: NSRange? {
		let keys = ["direction", "camera:direction"]
		for directionKey in keys {
			if let value = tags[directionKey],
			   let direction = OsmNode.directionFromString(value)
			{
				return direction
			}
		}
		return nil
	}

	/// Tag key (`direction` or `camera:direction`) whose value parses as a technical bearing, if any.
	var technicalDirectionTagKey: String? {
		for key in ["direction", "camera:direction"] {
			if let value = tags[key],
			   OsmNode.directionFromString(value) != nil
			{
				return key
			}
		}
		return nil
	}

	/// Bearing in degrees clockwise from north for a point direction (`direction` length 0).
	var directionPointBearing: Int? {
		guard let range = direction, range.length == 0 else { return nil }
		return range.location
	}

	/// OSM tag value for a bearing, preserving arc span when the current direction is a range.
	func directionTagValue(forBearingDegrees bearing: Int) -> String? {
		guard let range = direction else { return nil }
		let normalized = ((bearing % 360) + 360) % 360
		if range.length == 0 {
			return "\(normalized)"
		}
		let end = (normalized + range.length) % 360
		return "\(normalized)-\(end)"
	}

	private static func directionFromString(_ string: String) -> NSRange? {
		if let direction = Float(string) ?? cardinalDictionary[string] {
			return NSMakeRange(Int(direction), 0)
		} else {
			let a: [String] = string.components(separatedBy: "-")
			if a.count == 2 {
				let a0 = String(a[0])
				let a1 = String(a[1])
				if let d1 = Float(a0) ?? cardinalDictionary[a0],
				   let d2 = Float(a1) ?? cardinalDictionary[a1]
				{
					var angle = Int(d2 - d1)
					if angle < 0 {
						angle += 360
					}
					return NSMakeRange(Int(d1), angle)
				}
			}
		}

		return nil
	}
}
