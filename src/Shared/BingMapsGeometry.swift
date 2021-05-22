//
//  BingMapsGeometry.swift
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 9/26/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

//let EarthRadius: Double = 6378137
//let MinLatitude = -85.05112878
//let MaxLatitude = 85.05112878
//let MinLongitude: Double = -180
//let MaxLongitude: Double = 180
///// <summary>
///// Clips a number to the specified minimum and maximum values.
///// </summary>
///// <param name="n">The number to clip.</param>
///// <param name="minValue">Minimum allowable value.</param>
///// <param name="maxValue">Maximum allowable value.</param>
///// <returns>The clipped value.</returns>
//@inline(__always) func Clip(_ n: Double, _ minValue: Double, _ maxValue: Double) -> Double {
//    return Double(min(max(n, minValue), maxValue))
//}

///// <summary>
///// Determines the map width and height (in pixels) at a specified level
///// of detail.
///// </summary>
///// <param name="levelOfDetail">Level of detail, from 1 (lowest detail)
///// to 23 (highest detail).</param>
///// <returns>The map width and height in pixels.</returns>
//private func MapSize(_ levelOfDetail: Int) -> Int {
//    return Int(256) << levelOfDetail
//}
//
///// <summary>
///// Determines the ground resolution (in meters per pixel) at a specified
///// latitude and level of detail.
///// </summary>
///// <param name="latitude">Latitude (in degrees) at which to measure the
///// ground resolution.</param>
///// <param name="levelOfDetail">Level of detail, from 1 (lowest detail)
///// to 23 (highest detail).</param>
///// <returns>The ground resolution, in meters per pixel.</returns>
//@inline(__always) private func GroundResolution(_ latitude: inout Double, _ levelOfDetail: Int) -> Double {
//    latitude = Clip(latitude, MinLatitude, MaxLatitude)
//    return cos(latitude * .pi / 180) * 2 * .pi * EarthRadius / Double(MapSize(levelOfDetail))
//}
//
//@inline(__always) func MetersPerDegree(_ latitude: Double) -> Double {
//    return cos(latitude * .pi / 180) * 2 * .pi * EarthRadius / 360
//}
//
//@inline(__always) func MinimumLevelOfDetail(_ latitude: inout Double, _ metersPerPixel: Double) -> Int {
//    let res = GroundResolution(&latitude, 0)
//    let levelOfDetail = Int(ceil(log2(res / metersPerPixel)))
//    return levelOfDetail
//}
//
//@inline(__always) func MetersPerDegreeLatitude(_ latitude: inout Double) -> Double {
//    latitude *= .pi / 180
//    return 111132.954 - 559.822 * cos(2 * latitude) + 1.175 * cos(4 * latitude)
//}
//
//@inline(__always) func MetersPerDegreeLongitude(_ latitude: inout Double) -> Double {
//    latitude *= .pi / 180
//    return 111132.954 * cos(latitude)
//}

/// <summary>
/// Converts a point from latitude/longitude WGS-84 coordinates (in degrees)
/// into pixel XY coordinates at a specified level of detail.
/// </summary>
/// <param name="latitude">Latitude of the point, in degrees.</param>
/// <param name="longitude">Longitude of the point, in degrees.</param>
/// <param name="levelOfDetail">Level of detail, from 1 (lowest detail)
/// to 23 (highest detail).</param>
/// <param name="pixelX">Output parameter receiving the X coordinate in pixels.</param>
/// <param name="pixelY">Output parameter receiving the Y coordinate in pixels.</param>
@inline(__always) func LatLongToPixelXY(_ latitude: inout Double, _ longitude: inout Double, _ levelOfDetail: Int, _ pixelX: inout Int, _ pixelY: inout Int) {
    latitude = Clip(latitude, MinLatitude, MaxLatitude)
    longitude = Clip(longitude, MinLongitude, MaxLongitude)

    let x = (longitude + 180) / 360
    let sinLatitude = sin(latitude * .pi / 180)
    let y = 0.5 - log((1 + sinLatitude) / (1 - sinLatitude)) / (4 * .pi)

    let mapSize = MapSize(levelOfDetail)
    pixelX = Int(Clip(x * Double(mapSize) + 0.5, 0, Double(mapSize - 1)))
    pixelY = Int(Clip(y * Double(mapSize) + 0.5, 0, Double(mapSize - 1)))
}

/// <summary>
/// Converts a pixel from pixel XY coordinates at a specified level of detail
/// into latitude/longitude WGS-84 coordinates (in degrees).
/// </summary>
/// <param name="pixelX">X coordinate of the point, in pixels.</param>
/// <param name="pixelY">Y coordinates of the point, in pixels.</param>
/// <param name="levelOfDetail">Level of detail, from 1 (lowest detail)
/// to 23 (highest detail).</param>
/// <param name="latitude">Output parameter receiving the latitude in degrees.</param>
/// <param name="longitude">Output parameter receiving the longitude in degrees.</param>
@inline(__always) func PixelXYToLatLong(_ pixelX: Int, _ pixelY: Int, _ levelOfDetail: Int, _ latitude: inout Double, _ longitude: inout Double) {

    let mapSize = Double(MapSize(levelOfDetail))
    let x = (Clip(Double(pixelX), 0, mapSize - 1) / mapSize) - 0.5
    let y = 0.5 - (Clip(Double(pixelY), 0, mapSize - 1) / mapSize)

    latitude = 90 - 360 * atan(exp(-y * 2 * .pi)) / .pi
    longitude = 360 * x
}

/// <summary>
/// Converts pixel XY coordinates into tile XY coordinates of the tile containing
/// the specified pixel.
/// </summary>
/// <param name="pixelX">Pixel X coordinate.</param>
/// <param name="pixelY">Pixel Y coordinate.</param>
/// <param name="tileX">Output parameter receiving the tile X coordinate.</param>
/// <param name="tileY">Output parameter receiving the tile Y coordinate.</param>
@inline(__always) func PixelXYToTileXY(_ pixelX: Int, _ pixelY: Int, _ tileX: inout Int, _ tileY: inout Int) {
    tileX = pixelX / 256
    tileY = pixelY / 256
}

/// <summary>
/// Converts tile XY coordinates into pixel XY coordinates of the upper-left pixel
/// of the specified tile.
/// </summary>
/// <param name="tileX">Tile X coordinate.</param>
/// <param name="tileY">Tile Y coordinate.</param>
/// <param name="pixelX">Output parameter receiving the pixel X coordinate.</param>
/// <param name="pixelY">Output parameter receiving the pixel Y coordinate.</param>
@inline(__always) func TileXYToPixelXY(_ tileX: Int, _ tileY: Int, _ pixelX: inout Int, _ pixelY: inout Int) {
    pixelX = tileX * 256
    pixelY = tileY * 256
}

/// <summary>
/// Converts tile XY coordinates into a QuadKey at a specified level of detail.
/// </summary>
/// <param name="tileX">Tile X coordinate.</param>
/// <param name="tileY">Tile Y coordinate.</param>
/// <param name="levelOfDetail">Level of detail, from 1 (lowest detail)
/// to 23 (highest detail).</param>
/// <returns>A string containing the QuadKey.</returns>
@inline(__always) func TileXYToQuadKey(_ tileX: Int, _ tileY: Int, _ levelOfDetail: Int) -> NSString {
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
    return quadKey as NSString
}

@inline(__always) func TileXYToQuadKey2(_ tileX: Int, _ tileY: Int, _ levelOfDetail: Int) -> NSString {
    var quadKey = String(repeating: "\0", count: levelOfDetail)
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
    return quadKey as NSString
}

/// <summary>
/// Converts a QuadKey into tile XY coordinates.
/// </summary>
/// <param name="quadKey">QuadKey of the tile.</param>
/// <param name="tileX">Output parameter receiving the tile X coordinate.</param>
/// <param name="tileY">Output parameter receiving the tile Y coordinate.</param>
/// <param name="levelOfDetail">Output parameter receiving the level of detail.</param>
@inline(__always) func QuadKeyToTileXY(_ quadKey: NSString, _ tileX: inout Int, _ tileY: inout Int, _ levelOfDetail: inout Int) {
    levelOfDetail = quadKey.length

    var i = levelOfDetail
    while i > 0 {
        let mask = 1 << (i - 1)
        switch quadKey.character(at: levelOfDetail-i) {
            case unichar(0):
                break
            case unichar(1):
                tileX |= mask
            case unichar(2):
                tileY |= mask
            case unichar(3):
                tileX |= mask
                tileY |= mask
            default:
                assert(false)
        }
        i -= 1
    }
}

