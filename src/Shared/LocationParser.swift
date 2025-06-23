//
//  LocationParser.swift
//  Go Map!!
//
//  Created by Wolfgang Timme on 2/2/20.
//  Copyright © 2020 Bryce Cogswell. All rights reserved.
//

import Foundation

extension Scanner {
	func scanAnyCharacter(from string: String) -> String? {
		for ch in string {
			let chs = String(ch)
			if scanString(chs) != nil {
				return chs
			}
		}
		return nil
	}
}

/// An object that parses URLs and text for coordinates
class LocationParser {
	enum LatOrLon {
		case lat
		case lon
	}

	private static func scanNSEW(scanner: Scanner) -> (Double, LatOrLon)? {
		switch scanner.scanAnyCharacter(from: "NESW") {
		case "N": return (1.0, .lat)
		case "S": return (-1.0, .lat)
		case "E": return (1.0, .lon)
		case "W": return (-1.0, .lon)
		default: return nil
		}
	}

	private static func scanDegreesMinutesSeconds(scanner: Scanner) -> Double? {
		// Parse degrees, minutes, seconds:
		guard let degrees = scanner.scanInt(), // Degrees (integer),
		      scanner.scanString("°") != nil, // followed by °,
		      let minutes = scanner.scanInt(), // minutes (integer)
		      scanner.scanAnyCharacter(from: "'′") != nil // followed by '
		else {
			return nil
		}
		// optional seconds
		let seconds: Double
		let index = scanner.currentIndex
		if let tempSeconds = scanner.scanDouble(), // seconds (floating point),
		   scanner.scanAnyCharacter(from: "\"″") != nil // followed by "
		{
			seconds = tempSeconds
			// got seconds too
		} else {
			seconds = 0.0
			scanner.currentIndex = index
		}

		let value = Double(abs(degrees)) + Double(minutes) / 60.0 + seconds / 3600.0
		return degrees >= 0 ? value : -value
	}

	// parse a string like:
	// 26°35'36"N 106°40'44"E
	// 19°33'51.6"N+155°56'07.7"W
	// 49° 56′ 49″ W, 41° 43′ 57″ N
	private static func scanDegreesMinutesSecondsPair(string: String) -> (Double, Double)? {
		let scanner = Scanner(string: string)
		scanner.charactersToBeSkipped = .whitespaces

		let firstDir1 = scanNSEW(scanner: scanner)
		guard let first = scanDegreesMinutesSeconds(scanner: scanner)
		else { return nil }
		let firstDir2 = scanNSEW(scanner: scanner)

		let _ = scanner.scanAnyCharacter(from: "+,")

		let secondDir1 = scanNSEW(scanner: scanner)
		guard let second = scanDegreesMinutesSeconds(scanner: scanner)
		else { return nil }
		let secondDir2 = scanNSEW(scanner: scanner)

		// now decode the NSEW values
		switch (firstDir1?.1, firstDir2?.1, secondDir1?.1, secondDir2?.1) {
		case (nil, nil, nil, nil):
			return (first, second)
		case (.lat, nil, .lon, nil):
			return (first * firstDir1!.0, second * secondDir1!.0)
		case (nil, .lat, nil, .lon):
			return (first * firstDir2!.0, second * secondDir2!.0)
		case (.lon, nil, .lat, nil):
			return (second * secondDir1!.0, first * firstDir1!.0)
		case (nil, .lon, nil, .lat):
			return (second * secondDir2!.0, first * firstDir2!.0)
		default:
			return nil
		}
	}

	private class func urlFor(string: String) -> URL? {
		var urlText = string.addingPercentEncodingForNonASCII()
		var c = CharacterSet()
		c.insert(charactersIn: "'")
		c.invert()
		urlText = urlText.addingPercentEncoding(withAllowedCharacters: c)!
		return URL(string: urlText)
	}

	class func mapLocationFrom(string: String) -> MapLocation? {
		// first try parsing as a URL
		let text = string.trimmingCharacters(in: .whitespacesAndNewlines)
		if let url = Self.urlFor(string: text),
		   let loc = Self.mapLocationFrom(url: url)
		{
			return loc
		}

		// Try a formatted value like 26°35'36"N 106°40'44"E
		if let latLon = scanDegreesMinutesSecondsPair(string: text) {
			return MapLocation(longitude: latLon.1,
			                   latitude: latLon.0,
			                   zoom: 0.0,
			                   viewState: nil)
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
			_ = scanner.scanUpToCharacters(from: digits)
			if scanner.isAtEnd {
				break
			}
			let pos = scanner.currentIndex
			if let sLat = scanner.scanCharacters(from: floats),
			   let lat = Double(sLat),
			   lat > -90,
			   lat < 90,
			   scanner.scanCharacters(from: comma) != nil,
			   let sLon = scanner.scanCharacters(from: floats),
			   let lon = Double(sLon),
			   lon >= -180,
			   lon <= 180
			{
				candidates.append((sLon, lon, sLat, lat))
			}
			if scanner.currentIndex == pos {
				scanner.currentIndex = scanner.string.index(after: pos)
			} else {
				scanner.currentIndex = pos
				_ = scanner.scanCharacters(from: floats)
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
			let scanner = Scanner(string: components.path)
			guard let lat = scanner.scanDouble(),
			      scanner.scanString(",") != nil,
			      let lon = scanner.scanDouble()
			else {
				return nil
			}
			var zoom: Double = 0
			if let z = components.queryItems?.first(where: { $0.name == "z" })?.value,
			   let z2 = Double(z)
			{
				zoom = z2
			}
			return MapLocation(longitude: lon, latitude: lat, zoom: zoom, viewState: nil)
		}

		// https://gomaposm.com/edit?center=47.679056,-122.212559&zoom=21&view=aerial%2Beditor
		if components.scheme == "gomaposm" ||
			components.host == "gomaposm.com" ||
			components.host == "www.gomaposm.com"
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
					if let pLat = scanner.scanDouble(),
					   scanner.scanString(",") != nil,
					   let pLon = scanner.scanDouble(),
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
					case "mapnik": view = .BASEMAP
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
		   let latLon = components.queryItems?.first(where: {
		   	$0.name == "ll" || $0.name == "coordinate"
		   })?.value
		{
			let scanner = Scanner(string: latLon)
			if let lat = scanner.scanDouble(),
			   scanner.scanString(",") != nil,
			   let lon = scanner.scanDouble()
			{
				return MapLocation(longitude: lon,
				                   latitude: lat,
				                   zoom: 0.0,
				                   viewState: nil)
			}
		}

		// parse as an Organic Maps shared link
		// See https://github.com/organicmaps/organicmaps/blob/e27bad2e3b53590208a3b3d5bf18dd226fefc7ad/ge0/parser.cpp#L55
		if components.host == "omaps.app",
		   let base64 = components.path.components(separatedBy: "/").dropFirst().first,
		   base64.count == 10
		{
			let map = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
			func decode(_ c: Character) -> Int? {
				if let index = map.firstIndex(of: c) {
					return map.distance(from: map.startIndex, to: index)
				}
				return nil
			}
			let zoom = decode(base64.first!) ?? 0
			var lat = 0
			var lon = 0
			for c in base64.dropFirst() {
				let a = decode(c) ?? 0
				let lat1 = (((a >> 5) & 1) << 2 | ((a >> 3) & 1) << 1 | ((a >> 1) & 1))
				let lon1 = (((a >> 4) & 1) << 2 | ((a >> 2) & 1) << 1 | (a & 1))
				lat |= Int(lat1)
				lon |= Int(lon1)
				lat <<= 3
				lon <<= 3
			}
			lat += 4
			lon += 4
			let maxValue = Double((1 << 30) - 1)
			let dLat = Double(lat) / maxValue * 180 - 90
			let dLon = Double(lon) / (maxValue + 1) * 360 - 180
			return MapLocation(longitude: dLon,
			                   latitude: dLat,
			                   zoom: Double(zoom) / 4 + 4,
			                   viewState: nil)
		}

		// parse as a Google Maps link
		// https://www.google.com/maps/place/Living+Aquaponics+Inc/@19.5643765,-155.935126,20.97z/data=!4m13!1m7!3m6!1s0x0:0xd6494344d03eaa48!2zMTnCsDMzJzUxLjYiTiAxNTXCsDU2JzA3LjciVw!3b1!8m2!3d19.5643333!4d-155.9354722!3m4!1s0x7954071e92209063:0x43b62535ef648685!8m2!3d19.5611044!4d-155.935151
		// https://www.google.com/maps/place/19°33'51.6%22N+155°56'07.7%22W/@19.5637643,-155.9361706,18.29z/data=!4m5!3m4!1s0x0:0xd6494344d03eaa48!8m2!3d19.5643333!4d-155.9354722
		if components.host == "www.google.com" {
			var path = components.path
			while path.hasPrefix("/") {
				path = String(path.dropFirst())
			}
			while path != "" {
				let name = (path as NSString).lastPathComponent
				if name.hasPrefix("@") {
					let scanner = Scanner(string: String(name.dropFirst()))
					if let lat = scanner.scanDouble(),
					   let _ = scanner.scanString(","),
					   let lon = scanner.scanDouble(),
					   let _ = scanner.scanString(","),
					   let zoom = scanner.scanDouble()
					{
						return MapLocation(longitude: lon,
						                   latitude: lat,
						                   zoom: zoom,
						                   viewState: nil)
					}
				}
				path = (path as NSString).deletingLastPathComponent
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

	/// try parsing as an OSM object or URL
	/// Node 4137621426
	/// https://www.openstreetmap.org/node/4137621426
	/// https://www.openstreetmap.org/node/4137621426#map=
	class func osmObjectReference(string: String) -> (OSM_TYPE, Int64)? {
		var string = string.lowercased()
		if let hash = string.firstIndex(of: "#") {
			string = String(string[..<hash])
		}
		let delim = CharacterSet(charactersIn: ":/,. -")
		let scanner = Scanner(string: String(string.reversed()))
		scanner.charactersToBeSkipped = nil
		if let objIdent = scanner.scanCharacters(from: CharacterSet.alphanumerics),
		   let objIdent2 = Int64(String((objIdent as String).reversed())),
		   let _ = scanner.scanCharacters(from: delim),
		   let objType = scanner.scanCharacters(from: CharacterSet.alphanumerics),
		   let objType2 = try? OSM_TYPE(string: String(objType.reversed()))
		{
			return (objType2, objIdent2)
		}
		return nil
	}

	/// decode as google maps
	/// https://maps.app.goo.gl/1G7doKp5QEgBCkir7
	static func isGoogleMapsRedirect(urlString: String, callback: @escaping ((MapLocation?) -> Void)) -> Bool {
		guard let url = URL(string: urlString),
		      let host = url.host,
		      host.hasSuffix("goo.gl") || host.hasSuffix("google.com")
		else {
			return false
		}

		Task {
			// First, resolve the shortened URL
			guard let resolvedURL = await resolveGoogleShortURL(url: url) else {
				callback(nil)
				return
			}

			// Extract the ftid value and construct the new URL
			if let latLong = extractLatLongFromGoogleURL(resolvedURL) {
				callback(latLong)
			} else if let ftid = googleFTID(from: resolvedURL),
			          let url = URL(string: "https://www.google.com/maps?ftid=\(ftid)"),
			          let resolvedURL = await resolveGoogleShortURL(url: url),
			          let latLong = extractLatLongFromGoogleURL(resolvedURL)
			{
				callback(latLong)
			} else {
				callback(nil)
			}
		}
		return true
	}

	static func extractLatLongFromGoogleURL(_ url: URL) -> MapLocation? {
		guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
		      let queryItems = components.queryItems
		else {
			return nil
		}

		if let q = queryItems.first(where: { $0.name == "q" })?.value,
		   let range = q.range(of: ",")
		{
			let latString = String(q[..<range.lowerBound])
			let longString = String(q[range.upperBound...])

			if let lat = Double(latString), let long = Double(longString) {
				return MapLocation(longitude: long, latitude: lat)
			}
		}

		return nil
	}

	static func fetchGoogleLocationDetails(ftid: String) async throws -> MapLocation {
		let url = URL(string: "https://places.googleapis.com/v1/places/\(ftid)")!
		var request = URLRequest(url: url)
		request.allHTTPHeaderFields = ["Accept": "application/json",
		                               "X-Goog-Api-Key": GoogleToken,
		                               "X-Goog-FieldMask": "displayName,formattedAddress"]
		let (data, _) = try await URLSession.shared.data(for: request)
		let text = String(data: data, encoding: .utf8)!
		print("\(text)")
		let response = try JSONDecoder().decode(ApiResponse.self, from: data)
		let location = response.result.geometry.location
		let mapLocation = MapLocation(longitude: location.lng, latitude: location.lat)
		return mapLocation
	}

	struct ApiResponse: Codable {
		let result: Result
	}

	struct Result: Codable {
		let geometry: Geometry
	}

	struct Geometry: Codable {
		let location: Location
	}

	struct Location: Codable {
		let lat: Double
		let lng: Double
	}

	// Helper function to resolve a shortened URL
	static func resolveGoogleShortURL(url: URL) async -> URL? {
		var request = URLRequest(url: url)
		request.httpMethod = "GET" // Changed from HEAD to GET
		guard let (_, response) = try? await URLSession.shared.data(for: request) else {
			return nil
		}
		return (response as? HTTPURLResponse)?.url
	}

	// Helper function to extract the ftid parameter from a URL
	static func googleFTID(from url: URL) -> String? {
		guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
		      let queryItems = components.queryItems,
		      let ftid = queryItems.first(where: { $0.name == "ftid" })?.value
		else {
			return nil
		}
		return ftid
	}
}
