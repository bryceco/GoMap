//
//  LocationParser.swift
//  Go Map!!
//
//  Created by Wolfgang Timme on 2/2/20.
//  Copyright © 2020 Bryce Cogswell. All rights reserved.
//

import Foundation

/// An object that parses URLs and text for coordinates
class LocationParser {

	class func mapLocationFrom(text: String) -> MapLocation? {

		// first try parsing as a URL
		let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
		if let url = URL(string: text),
		   let loc = Self.mapLocationFrom(url: url)
		{
			return loc
		}

		// look for any pair of adjacent potential lat/lon decimal numbers
		let scanner = Scanner(string: text)
		let digits = CharacterSet(charactersIn: "-0123456789")
		let floats = CharacterSet(charactersIn: "-.0123456789")
		let comma = CharacterSet(charactersIn: ",°/")
		scanner.charactersToBeSkipped = CharacterSet.whitespaces

		while !scanner.isAtEnd {
			scanner.scanUpToCharacters(from: digits, into: nil)
			let pos = scanner.scanLocation
			var sLat: NSString?
			var sLon: NSString?
			if scanner.scanCharacters(from: floats, into: &sLat),
				let sLat = sLat,
				sLat.contains("."),
				let lat = Double(sLat as String),
				lat > -90,
				lat < 90,
				scanner.scanCharacters(from: comma, into: nil),
				scanner.scanCharacters(from: floats, into: &sLon),
				let sLon = sLon,
				sLon.contains("."),
				let lon = Double(sLon as String),
				lon >= -180,
				lon <= 180
			 {
				return MapLocation(longitude: lon,
								   latitude: lat,
								   zoom: 0.0,
								   viewState: nil)
			 }
			 if scanner.scanLocation == pos,
				!scanner.isAtEnd
			 {
				 scanner.scanLocation = pos + 1
			 }
		 }
		 return nil
	}


	/// Attempts to parse the given URL.
	/// @param url The URL to parse.
	/// @return The parser result, if the URL was parsed successfully, or `nil` if the parser was not able to process the URL.
	class func mapLocationFrom(url: URL) -> MapLocation? {
		guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
			return nil
		}

		if components.scheme == "geo" {
			// geo:47.75538,-122.15979?z=18
			var lat: Double = 0
			var lon: Double = 0
			var zoom: Double = 0
			let scanner = Scanner(string: components.path)
			guard scanner.scanDouble(&lat),
			   scanner.scanString(",", into: nil),
			   scanner.scanDouble(&lon)
			else {
				return nil
			}
			if let z = components.queryItems?.first(where: {$0.name == "z"})?.value,
			   let z = Double(z)
			{
				zoom = z
			}

			return MapLocation(longitude: lon, latitude: lat, zoom: zoom, viewState: nil)
		}

		// https://gomaposm.com/edit?center=47.679056,-122.212559&zoom=21&view=aerial%2Beditor
		if components.scheme == "gomaposm" || components.host == "gomaposm.com" {
			var hasCenter = false
			var hasZoom = false
			var lat: Double = 0
			var lon: Double = 0
			var zoom: Double = 0
			var view: MapViewState?

			for queryItem in components.queryItems ?? [] {
				if queryItem.name == "center" {
					// scan center
					let scanner = Scanner(string: queryItem.value ?? "")
					hasCenter = scanner.scanDouble(&lat) && scanner.scanString(",", into: nil) && scanner
						.scanDouble(&lon) && scanner.isAtEnd
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

		 // try parsing as any URL containing lat=,lon=
		 if let lat = components.queryItems?.first(where: { $0.name == "lat" })?.value,
			let lon = components.queryItems?.first(where: { $0.name == "lon" })?.value,
			let lat = Double(lat),
			let lon = Double(lon)
		 {
			return MapLocation(longitude: lon,
							   latitude: lat,
							   zoom: 0.0,
							   viewState: nil)
		}

		return nil
	}
}
