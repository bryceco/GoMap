//
//  OsmNode+Direction.swift
//  Go Map!!
//
//  Created by Wolfgang Timme on 4/10/19.
//  Copyright © 2019 Bryce. All rights reserved.
//

import Foundation

extension OsmNode {

	static let cardinalDictionary : [String: Float] = [
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
				"NW": 315];

    /// The direction in which the node is facing.
    /// Since Objective-C is not able to work with optionals, the direction is `NSNotFound`
    /// if the node does not have a direction value instead of being `nil`.
    @objc var direction: NSRange {
        get {
            let keys = ["direction", "camera:direction"]
            for directionKey in keys {
                if
                    let value = tags?[directionKey],
					let direction = OsmNode.direction(from: value) {
                    return direction
                }
            }
            
            return NSMakeRange(NSNotFound,0)
        }
    }
    
    private static func direction(from string: String) -> NSRange? {
		if let direction = Float(string) ?? cardinalDictionary[string] {
			return NSMakeRange(Int(direction),0)
		} else {
			let a = string.split(separator:"-")
			if a.count == 2 {
				if
					let d1 = Float(a[0]) ?? cardinalDictionary[String(a[0])],
					let d2 = Float(a[1]) ?? cardinalDictionary[String(a[1])] {
					var angle = Int(d2-d1)
					if ( angle < 0 ) {
						angle += 360;
					}
					return NSMakeRange(Int(d1),angle)
				}
			}
		}

        return nil
    }
}
