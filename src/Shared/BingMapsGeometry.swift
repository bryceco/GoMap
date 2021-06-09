//
//  BingMapsGeometry.swift
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 9/26/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

let EarthRadius: Double = 6378137.0

/// Converts tile XY coordinates into a QuadKey at a specified level of detail.
func TileXYToQuadKey(_ tileX: Int, _ tileY: Int, _ levelOfDetail: Int) -> String {
    var quadKey = ""
    var i = levelOfDetail
    while i > 0 {
        var digit = 0
        let mask = 1 << (i - 1)
        if (tileX & mask) != 0 {
            digit += 1
        }
        if (tileY & mask) != 0 {
            digit += 1
            digit += 1
        }
        quadKey += "\(digit)"
        i -= 1
    }
    return quadKey
}

/// Converts a QuadKey into tile XY coordinates.
func QuadKeyToTileXY(_ quadKey: String) -> (x: Int, y: Int, z: Int) {
	let tileZ = quadKey.count
	var tileX = 0
	var tileY = 0

	var i = tileZ
	for char in quadKey.reversed() {
		let mask = 1 << (i - 1)
		switch char {
			case "0":
                break
            case "1":
                tileX |= mask
            case "2":
                tileY |= mask
            case "3":
				tileX |= mask
                tileY |= mask
			default:
				assert(false)
        }
		i -= 1
    }
	return (tileX, tileY, tileZ)
}

