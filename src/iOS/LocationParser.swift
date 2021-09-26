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

		var candidates = [(sLon: String, lon: Double,
		                   sLat: String, lat: Double)]()

		while true {
			scanner.scanUpToCharacters(from: digits, into: nil)
			if scanner.isAtEnd {
				break
			}
			let pos = scanner.scanLocation
			var sLat: NSString?
			var sLon: NSString?
			if scanner.scanCharacters(from: floats, into: &sLat),
			   let sLat = sLat,
			   let lat = Double(sLat as String),
			   lat > -90,
			   lat < 90,
			   scanner.scanCharacters(from: comma, into: nil),
			   scanner.scanCharacters(from: floats, into: &sLon),
			   let sLon = sLon,
			   let lon = Double(sLon as String),
			   lon >= -180,
			   lon <= 180
			{
				candidates.append((sLon as String, lon, sLat as String, lat))
			}
			if scanner.scanLocation == pos {
				scanner.scanLocation = pos + 1
			} else {
				scanner.scanLocation = pos
				scanner.scanCharacters(from: floats, into: nil)
			}
		}
		if candidates.isEmpty {
			return nil
		}
		if candidates.count > 1 {
			// remove any that lack decimal points
			let best = candidates.filter({ $0.sLon.contains(".") && $0.sLat.contains(".") })
			if !best.isEmpty {
				candidates = best
			}
		}
		return MapLocation(longitude: candidates.first!.lon,
		                   latitude: candidates.first!.lat,
		                   zoom: 0.0,
		                   viewState: nil)
	}

	/// Attempts to parse the given URL.
	/// @param url The URL to parse.
	/// @return The parser result, if the URL was parsed successfully, or `nil` if the parser was not able to process the URL.
	class func mapLocationFrom(url: URL) -> MapLocation? {
		guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
			return nil
		}

		// geo:47.75538,-122.15979?z=18
		if components.scheme == "geo" {
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
			if let z = components.queryItems?.first(where: { $0.name == "z" })?.value,
			   let z2 = Double(z)
			{
				zoom = z2
			}
			return MapLocation(longitude: lon, latitude: lat, zoom: zoom, viewState: nil)
		}

		// https://gomaposm.com/edit?center=47.679056,-122.212559&zoom=21&view=aerial%2Beditor
		if components.scheme == "gomaposm" ||
			components.host == "gomaposm.com"
		{
			var lat: Double?
			var lon: Double?
			var zoom: Double?
			var direction: Double?
			var view: MapViewState?

			for queryItem in components.queryItems ?? [] {
				switch queryItem.name {
				case "center":
					// scan center
					let scanner = Scanner(string: queryItem.value ?? "")
					var pLat: Double = 0.0
					var pLon: Double = 0.0
					if scanner.scanDouble(&pLat),
					   scanner.scanString(",", into: nil),
					   scanner.scanDouble(&pLon),
					   scanner.isAtEnd
					{
						lat = pLat
						lon = pLon
					}
				case "zoom":
					// scan zoom
					if let val = queryItem.value {
						zoom = Double(val)
					}
				case "view":
					// scan view
					switch queryItem.value {
					case "aerial+editor": view = .EDITORAERIAL
					case "aerial": view = .AERIAL
					case "mapnik": view = .MAPNIK
					case "editor": view = .EDITOR
					default: break
					}
				case "direction":
					// direction facing
					if let val = queryItem.value {
						direction = Double(val)
					}
				default:
					// unrecognized parameter
					break
				}
			}
			if let lat = lat,
			   let lon = lon
			{
				return MapLocation(longitude: lon,
				                   latitude: lat,
				                   zoom: zoom ?? 0.0,
				                   direction: direction ?? 0.0,
				                   viewState: view)
			}
		}

		// decode as apple maps link
		if components.host == "maps.apple.com",
		   let latLon = components.queryItems?.first(where: { $0.name == "ll" })?.value
		{
			var lat = 0.0, lon = 0.0
			let scanner = Scanner(string: latLon)
			if scanner.scanDouble(&lat),
			   scanner.scanString(",", into: nil),
			   scanner.scanDouble(&lon)
			{
				return MapLocation(longitude: lon,
				                   latitude: lat,
				                   zoom: 0.0,
				                   viewState: nil)
			}
		}

		// try parsing as any URL containing lat=,lon=
		if let lat2 = components.queryItems?.first(where: { $0.name == "lat" })?.value,
		   let lon2 = components.queryItems?.first(where: { $0.name == "lon" })?.value,
		   let lat = Double(lat2),
		   let lon = Double(lon2)
		{
			return MapLocation(longitude: lon,
			                   latitude: lat,
			                   zoom: 0.0,
			                   viewState: nil)
		}

		// try parsing as a link containing zoom/lat/lon triple
		let fragments = (components.queryItems?.map({ $0.value }) ?? []) + [components.fragment]
		for fragment in fragments.compactMap({ $0 }) {
			let integer = #"[0-9]+"#
			let float = #"-?(0|[1-9]\d*)(\.\d+)?"#
			let pattern = "(\(integer))/(\(float))/(\(float))"
			let regex = try! NSRegularExpression(pattern: pattern, options: [])
			let nsrange = NSRange(fragment.startIndex..<fragment.endIndex,
			                      in: fragment)
			let matches = regex.matches(in: fragment,
			                            options: [],
			                            range: nsrange)
			for match in matches {
				if let zoomRange = Range(match.range(at: 1), in: fragment),
				   let latRange = Range(match.range(at: 2), in: fragment),
				   let lonRange = Range(match.range(at: 5), in: fragment)
				{
					let zoom = fragment[zoomRange]
					let lat = fragment[latRange]
					let lon = fragment[lonRange]
					if let zoom = Int(zoom),
					   let lat = Double(lat),
					   let lon = Double(lon),
					   (1...21).contains(zoom),
					   (-90.0...90.0).contains(lat),
					   (-180.0...180.0).contains(lon)
					{
						return MapLocation(longitude: lon,
						                   latitude: lat,
						                   zoom: Double(zoom),
						                   viewState: nil)
					}
				}
			}
		}

		return nil
	}
}
