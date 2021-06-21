//
//  LocationURLParser.swift
//  Go Map!!
//
//  Created by Wolfgang Timme on 2/2/20.
//  Copyright © 2020 Bryce Cogswell. All rights reserved.
//

import Foundation

/// An object that parses `geo:` URLs
class LocationURLParser {
	/// Attempts to parse the given URL.
	/// @param url The URL to parse.
	/// @return The parser result, if the URL was parsed successfully, or `nil` if the parser was not able to process the URL.
	class func parseURL(_ url: URL) -> MapLocation? {
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
			if scanner.scanString("?", into: nil), scanner.scanString("z=", into: nil) {
				scanner.scanDouble(&zoom)
			}

			return MapLocation(longitude: lon, latitude: lat, zoom: zoom, viewState: nil)
		}

		let urlComponents = NSURLComponents(url: url, resolvingAgainstBaseURL: false)

		// https://gomaposm.com/edit?center=47.679056,-122.212559&zoom=21&view=aerial%2Beditor
		if url.absoluteString.hasPrefix("gomaposm://?") || (urlComponents?.host == "gomaposm.com") {
			var hasCenter = false
			var hasZoom = false
			var lat: Double = 0
			var lon: Double = 0
			var zoom: Double = 0
			var view: MapViewState?

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
						view = MapViewState.EDITORAERIAL
					} else if queryItem.value == "aerial" {
						view = MapViewState.AERIAL
					} else if queryItem.value == "mapnik" {
						view = MapViewState.MAPNIK
					} else if queryItem.value == "editor" {
						view = MapViewState.EDITOR
					}
				} else {
					// unrecognized parameter
				}
			}
			if hasCenter {
				return MapLocation(longitude: lon,
				                   latitude: lat,
				                   zoom: hasZoom ? zoom : 0.0,
				                   viewState: view)
			}
		}
		return nil
	}
}
