//
//  BingMapsGeometry.swift
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 9/26/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

let EarthRadius: Double = 6378137
let MinLatitude = -85.05112878
let MaxLatitude = 85.05112878
let MinLongitude: Double = -180
let MaxLongitude: Double = 180

@inline(__always) func MetersPerDegree(atLatitude latitude: Double) -> OSMPoint {
	let latitude = latitude * .pi / 180
	let lat = 111132.954 - 559.822 * cos(2 * latitude) + 1.175 * cos(4 * latitude)
	let lon = 111132.954 * cos(latitude)
	return OSMPoint( x: lon, y: lat)
}

/// <summary>
/// Converts tile XY coordinates into a QuadKey at a specified level of detail.
/// </summary>
/// <param name="tileX">Tile X coordinate.</param>
/// <param name="tileY">Tile Y coordinate.</param>
/// <param name="levelOfDetail">Level of detail, from 1 (lowest detail)
/// to 23 (highest detail).</param>
/// <returns>A string containing the QuadKey.</returns>
@inline(__always) func TileXYToQuadKey(_ tileX: Int, _ tileY: Int, _ levelOfDetail: Int) -> String {
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


/// <summary>
/// Converts a QuadKey into tile XY coordinates.
/// </summary>
/// <param name="quadKey">QuadKey of the tile.</param>
/// <param name="tileX">Output parameter receiving the tile X coordinate.</param>
/// <param name="tileY">Output parameter receiving the tile Y coordinate.</param>
/// <param name="levelOfDetail">Output parameter receiving the level of detail.</param>
@inline(__always) func QuadKeyToTileXY(_ quadKey: String) -> (x: Int, y: Int, z: Int) {
	let levelOfDetail = quadKey.count
	var tileX = 0
	var tileY = 0

	var i = levelOfDetail
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
	return (tileX, tileY, levelOfDetail)
}

