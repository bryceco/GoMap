//
//  LocationSet.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 5/14/24.
//  Copyright © 2024 Bryce Cogswell. All rights reserved.
//

import Foundation

struct LocationSet {
	enum LocationEntry {
		struct LatLonRadius {
			let latLon: LatLon
			let radius: Double

			init(lat: Double, lon: Double, radius: Double) {
				self.latLon = LatLon(lon: lon, lat: lat)
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
					self = .region(s.lowercased())
				}
			case let n as [NSNumber]:
				if n.count == 2 {
					self = .latLonRadius(LatLonRadius(lat: n[1].doubleValue, lon: n[0].doubleValue, radius: 25000))
				} else if n.count == 3 {
					self = .latLonRadius(LatLonRadius(lat: n[1].doubleValue,
					                                  lon: n[0].doubleValue,
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
				return region.caseInsensitiveCompare(countryCode) == .orderedSame
			default:
				return false
			}
		}

		func matches(mapViewRegion: RegionInfoForLocation) -> Bool {
			switch self {
			case .world:
				return true
			case let .region(region):
				return mapViewRegion.regions.contains(region)
			case let .geojson(geoName):
				if let geojson = PresetsDatabase.shared.nsiGeoJson[geoName],
				   geojson.contains(mapViewRegion.latLon)
				{
					return true
				}
				return false
			case let .latLonRadius(latLonRadius):
				let dist = latLonRadius.latLon.greatCircleDistance(to: mapViewRegion.latLon)
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

	func overlaps(_ location: RegionInfoForLocation) -> Bool {
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

// MARK: - Decodable

extension LocationSet.LocationEntry: Decodable {
	init(from decoder: Decoder) throws {
		let container = try decoder.singleValueContainer()
		if let string = try? container.decode(String.self) {
			if string == "001" {
				self = .world
			} else if string.hasSuffix(".geojson") {
				self = .geojson(string)
			} else {
				self = .region(string.lowercased())
			}
		} else {
			let coords = try container.decode([Double].self)
			switch coords.count {
			case 2:
				self = .latLonRadius(LatLonRadius(lat: coords[1], lon: coords[0], radius: 25000))
			case 3:
				self = .latLonRadius(LatLonRadius(lat: coords[1], lon: coords[0], radius: coords[2]))
			default:
				throw DecodingError.dataCorruptedError(in: container,
				                                       debugDescription: "Expected 2 or 3 coordinates, got \(coords.count)")
			}
		}
	}
}

extension LocationSet: Decodable {
	enum CodingKeys: String, CodingKey {
		case include, exclude
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		include = try container.decodeIfPresent([LocationEntry].self, forKey: .include) ?? []
		exclude = try container.decodeIfPresent([LocationEntry].self, forKey: .exclude) ?? []
	}
}
