//
//  LocationSet.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 5/14/24.
//  Copyright © 2024 Bryce Cogswell. All rights reserved.
//

import Foundation

/// Hardcoded mapping for Wikidata Q-codes as region identifiers. Only Q46 (EU) is currently supported.
private let Q46_EU_COUNTRY_CODES: Set<String> = [
	"AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR", "DE", "GR", "HU", "IE", "IT", "LV", "LT", "LU", "MT",
	"NL", "PL", "PT", "RO", "SK", "SI", "ES", "SE"
]

extension String {
	var isQ46EU: Bool { caseInsensitiveCompare("Q46") == .orderedSame }
	var isQCode: Bool { uppercased().starts(with: "Q") && Int(dropFirst()) != nil }
}

struct LocationSet {
	enum LocationEntry {
		struct LatLonRadius {
			let lat: Double
			let lon: Double
			let radius: Double

			init(lat: Double, lon: Double, radius: Double) {
				self.lat = lat
				self.lon = lon
				self.radius = radius
			}
		}

		case world
		case region(String)
		case geojson(String)
		case latLonRadius(LatLonRadius)

		init(_ value: Any) {
			switch value {
			case let s as String:
				if s == "001" {
					self = .world
				} else if s.hasSuffix(".geojson") {
					self = .geojson(s)
				} else {
					self = .region(s)
				}
			case let n as [NSNumber]:
				if n.count == 2 {
					self = .latLonRadius(LatLonRadius(lat: n[1].doubleValue, lon: n[0].doubleValue, radius: 25000))
				} else if n.count == 3 {
					self =
						.latLonRadius(LatLonRadius(lat: n[1].doubleValue, lon: n[0].doubleValue,
						                           radius: n[2].doubleValue))
				} else {
					fatalError()
				}
			default:
				fatalError()
			}
		}

		func matches(countryCode: String) -> Bool {
			switch self {
			case .world:
				return true
			case let .region(region):
				if region.isQ46EU {
					// Special case: Q46 = EU; accept any EU country code
					return Q46_EU_COUNTRY_CODES.contains(countryCode.uppercased())
				} else if region.isQCode {
					print(
						"[LocationSet] Warning: Preset region uses unrecognized Q-code \(region), not supported except for Q46 (EU)")
				}
				return region.caseInsensitiveCompare(countryCode) == .orderedSame
			default:
				return false
			}
		}

		func matches(mapViewRegion: MapView.CurrentRegion) -> Bool {
			switch self {
			case .world:
				return true
			case let .region(region):
				if region.isQ46EU {
					return mapViewRegion.regions.contains(where: { Q46_EU_COUNTRY_CODES.contains($0.uppercased()) })
				} else if region.isQCode {
					print(
						"[LocationSet] Warning: Preset region uses unrecognized Q-code \(region), not supported except for Q46 (EU)")
				}
				return mapViewRegion.regions.contains(region)
			case let .geojson(geoName):
				if let geojson = PresetsDatabase.shared.nsiGeoJson[geoName],
				   geojson.contains(mapViewRegion.latLon)
				{
					return true
				}
				return false
			case let .latLonRadius(latLonRadius):
				let dist = GreatCircleDistance(LatLon(lon: latLonRadius.lon, lat: latLonRadius.lat),
				                               mapViewRegion.latLon)
				return dist <= latLonRadius.radius
			}
		}
	}

	let include: [LocationEntry]
	let exclude: [LocationEntry]

	init(withJson json: Any?) {
		guard let json = json else {
			include = []
			exclude = []
			return
		}
		guard let json = json as? [String: [Any]] else {
			fatalError()
		}
		include = json["include"]?.map { LocationEntry($0) } ?? []
		exclude = json["exclude"]?.map { LocationEntry($0) } ?? []
	}

	func contains(countryCode: String) -> Bool {
		if include.count > 0,
		   !include.contains(where: { $0.matches(countryCode: countryCode) })
		{
			return false
		}
		if exclude.contains(where: { $0.matches(countryCode: countryCode) }) {
			return false
		}
		return true
	}

	func overlaps(_ location: MapView.CurrentRegion) -> Bool {
		if include.isEmpty, exclude.isEmpty {
			return true
		}
		if include.count > 0,
		   !include.contains(where: { $0.matches(mapViewRegion: location) })
		{
			return false
		}
		if exclude.contains(where: { $0.matches(mapViewRegion: location) }) {
			return false
		}
		return true
	}
}
