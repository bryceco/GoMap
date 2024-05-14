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
		case world
		case region(String)
		case geojson(String)
		case latLonRadius((lat: Double, lon: Double, radius: Double))

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
					self = .latLonRadius((lat: n[1].doubleValue, lon: n[0].doubleValue, radius: 25000))
				} else if n.count == 3 {
					self = .latLonRadius((lat: n[1].doubleValue, lon: n[0].doubleValue, radius: n[2].doubleValue))
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

		func matches(mapViewRegion: MapView.CurrentRegion) -> Bool {
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
			case let .latLonRadius((lat, lon, radius)):
				let dist = GreatCircleDistance(LatLon(lon: lon, lat: lat),
				                               mapViewRegion.latLon)
				return dist <= radius
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
