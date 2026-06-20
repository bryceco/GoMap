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
	var direction: (key: String, direction: Direction)? {
		let keys = ["direction", "camera:direction"]
		for key in keys {
			if let value = tags[key],
			   let direction = OsmNode.directionFromString(value)
			{
				return (key, direction)
			}
		}
		return nil
	}

	// start and end are always 0..359
	struct Direction {
		var start: Int
		var end: Int

		var direction: Int {
			if start <= end {
				return (start + end) / 2
			} else {
				// wrapped interval, e.g. 350..20
				return Self.clamp((start + end + 360) / 2)
			}
		}
		var arcWidth: Int {
			if start <= end {
				return end - start
			} else {
				// Wrapped interval, e.g. 350 → 20
				return (end + 360) - start
			}
		}

		init(start: Int, end: Int) {
			self.start = Self.clamp(start)
			self.end = Self.clamp(end)
		}

		init(_ direction: Int) {
			self.init(start: direction,
					  end: direction)
		}
		init(start: Float, end: Float) {
			self.init(start: Int(start.rounded()),
					  end: Int(end.rounded()))
		}
		init(_ direction: Float) {
			self.init(start: direction,
					  end: direction)
		}

		/// Returns a new Direction with the given start bearing and the same arc width.
		func with(start newStart: Int) -> Direction {
			return Direction(start: newStart,
							 end: newStart + arcWidth)
		}

		func valueString() -> String {
			if start == end {
				return "\(start)"
			}
			return "\(start)-\(end)"
		}

		static func clamp(_ angle: Int) -> Int {
			return ((angle % 360) + 360) % 360
		}
	}

	private static func directionFromString(_ string: String) -> Direction? {
		if let direction = Float(string) ?? cardinalDictionary[string] {
			return Direction(direction)
		} else {
			let a: [String] = string.components(separatedBy: "-")
			if a.count == 2 {
				let a0 = String(a[0])
				let a1 = String(a[1])
				if let d1 = Float(a0) ?? cardinalDictionary[a0],
				   let d2 = Float(a1) ?? cardinalDictionary[a1]
				{
					return Direction(start: d1, end: d2)
				}
			}
		}

		return nil
	}
}
