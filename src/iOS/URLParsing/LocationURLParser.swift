//  Converted to Swift 5.4 by Swiftify v5.4.27034 - https://swiftify.com/
//
//  GeoURLParser.h
//  Go Map!!
//
//  Created by Wolfgang Timme on 2/2/20.
//  Copyright © 2020 Bryce. All rights reserved.
//

//
//  GeoURLParser.m
//  Go Map!!
//
//  Created by Wolfgang Timme on 2/2/20.
//  Copyright © 2020 Bryce. All rights reserved.
//

import Foundation

/// An object that parses `geo:` URLs
class LocationURLParser: NSObject {
    /// Attempts to parse the given URL.
    /// @param url The URL to parse.
    /// @return The parser result, if the URL was parsed successfully, or `nil` if the parser was not able to process the URL.
    func parseURL(_ url: URL) -> MapLocation? {
        if url.absoluteString.hasPrefix("geo:") {
            // geo:47.75538,-122.15979?z=18
            var lat: Double = 0
            var lon: Double = 0
            var zoom: Double = 0
            let scanner = Scanner(string: url.absoluteString)
            scanner.scanString("geo:", into: nil)
            if !scanner.scanDouble(&lat) {
                /// Invalid latitude
                return nil
            }
            scanner.scanString(",", into: nil)
            if !scanner.scanDouble(&lon) {
                /// Invalid longitude
                return nil
            }
            while scanner.scanString(";", into: nil) {
                var nonSemicolon = CharacterSet(charactersIn: ";")
                nonSemicolon.invert()
                scanner.scanCharacters(from: nonSemicolon, into: nil)
            }
            if scanner.scanString("?", into: nil) && scanner.scanString("z=", into: nil) {
                scanner.scanDouble(&zoom)
            }

            let parserResult = MapLocation()
            parserResult.longitude = lon
            parserResult.latitude = lat
            parserResult.zoom = zoom
            parserResult.viewState = MAPVIEW_NONE
            return parserResult
        }

        let urlComponents = NSURLComponents(url: url, resolvingAgainstBaseURL: false)

        // https://gomaposm.com/edit?center=47.679056,-122.212559&zoom=21&view=aerial%2Beditor
        if url.absoluteString.hasPrefix("gomaposm://?") || (urlComponents?.host == "gomaposm.com") {
            var hasCenter = false
            var hasZoom = false
            var lat: Double = 0
            var lon: Double = 0
            var zoom: Double = 0
            var view = MAPVIEW_NONE

            for queryItem in urlComponents?.queryItems ?? [] {
                if queryItem.name == "center" {
                    // scan center
                    let scanner = Scanner(string: queryItem.value ?? "")
                    hasCenter = scanner.scanDouble(&lat) && scanner.scanString(",", into: nil) && scanner.scanDouble(&lon) && scanner.isAtEnd
                } else if queryItem.name == "zoom" {
                    // scan zoom
                    let scanner = Scanner(string: queryItem.value ?? "")
                    hasZoom = scanner.scanDouble(&zoom) && scanner.isAtEnd
                } else if queryItem.name == "view" {
                    // scan view
                    if queryItem.value == "aerial+editor" {
                        view = MAPVIEW_EDITORAERIAL
                    } else if queryItem.value == "aerial" {
                        view = MAPVIEW_AERIAL
                    } else if queryItem.value == "mapnik" {
                        view = MAPVIEW_MAPNIK
                    } else if queryItem.value == "editor" {
                        view = MAPVIEW_EDITOR
                    }
                } else {
                    // unrecognized parameter
                }
            }
            if hasCenter {
                let parserResult = MapLocation()
                parserResult.longitude = lon
                parserResult.latitude = lat
                parserResult.zoom = hasZoom ? zoom : 0.0
                parserResult.viewState = view
                return parserResult
            }
        }
        return nil
    }
}
