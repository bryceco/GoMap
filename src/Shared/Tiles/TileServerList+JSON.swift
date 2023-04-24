//
//  TileServerList+JSON.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 3/20/23.
//  Copyright © 2023 Bryce Cogswell. All rights reserved.
//

import UIKit

infix operator -->: AssignmentPrecedence
func --> <T>(lhs: Any?, rhs: T.Type) throws -> T {
	guard let lhs = lhs as? T else {
		throw TypeCastError.invalidType
	}
	return lhs
}

extension TileServerList {
	static let MapBoxLocatorId = "mapbox_locator_overlay"
	static let MapBoxLayerId = "Mapbox"

	private struct Welcome {
		private let json: [String: Any]
		var features: [Feature] { get throws { try (json["features"] --> [Any].self).map({ try Feature($0) }) }}
		var meta: Meta? { get throws { try Meta(json["meta"]) } }
		var type: String { get throws { try json["type"] --> String.self } }

		init(_ json: Any?) throws {
			self.json = try json --> [String: Any].self
		}
	}

	private struct Meta {
		private let json: [String: Any]
		var format_version: String { get throws { try json["format_version"] --> String.self } }
		var generated: String { get throws { try json["generated"] --> String.self } }
		init?(_ json: Any?) throws {
			guard let json = json else { return nil }
			self.json = try json --> [String: Any].self
		}
	}

	private struct Feature {
		private let json: [String: Any]
		var geometry: GeoJSON? { get throws {
			if json["geometry"] is NSNull { return nil }
			return try GeoJSON(geometry: json["geometry"] --> [String: Any]?.self)
		} }
		var properties: Properties { get throws { try Properties(json["properties"] --> Any.self) } }
		var type: String { get throws { try json["type"] --> String.self } }
		init(_ json: Any?) throws {
			self.json = try json --> [String: Any].self
		}
	}

	private struct Properties {
		private let json: [String: Any]
		var attribution: Attribution? { get throws { try Attribution(json["attribution"]) }}
		var category: Category? { get throws {
			let cat = try json["category"] --> String?.self
			return cat != nil ? try Category(string: cat!) : nil
		}}
		var icon: String? { get throws { try json["icon"] --> String?.self } }
		var id: String { get throws { try json["id"] --> String.self }}
		var max_zoom: Int? { get throws { try json["max_zoom"] --> Int?.self }}
		var name: String { get throws { try json["name"] --> String.self }}
		var start_date: String? { get throws { try json["start_date"] --> String?.self }}
		var end_date: String? { get throws { try json["end_date"] --> String?.self }}
		var type: PropertiesType { get throws { try PropertiesType(string: json["type"] --> String.self) }}
		var url: String { get throws { try json["url"] --> String.self }}
		var best: Bool? { get throws { try json["best"] --> Bool?.self }}
		var available_projections: [String]? { get throws { try (json["available_projections"] --> [String]?.self) }}
		var overlay: Bool? { get throws { try json["overlay"] --> Bool?.self } }
		var transparent: Bool? { get throws { try json["transparent"] --> Bool?.self } }
		init(_ json: Any?) throws {
			self.json = try json --> [String: Any].self
		}
	}

	private struct Attribution {
		private let json: [String: Any]
		var attributionRequired: Bool? { get throws { try json["attributionRequired"] --> Bool?.self } }
		var text: String? { get throws { try json["text"] --> String?.self } }
		var url: String? { get throws { try json["url"] --> String?.self }}
		init?(_ json: Any?) throws {
			guard let json = json else { return nil }
			self.json = try json --> [String: Any].self
		}
	}

	private enum Category: String {
		case elevation
		case historicmap
		case historicphoto
		case map
		case osmbasedmap
		case other
		case photo
		case qa
		init(string: String) throws {
			guard let value = Self(rawValue: string) else {
				throw TypeCastError.invalidEnum
			}
			self = value
		}
	}

	private enum PropertiesType: String {
		case bing
		case scanex
		case tms
		case wms
		case wms_endpoint
		case wmts
		init(string: String) throws {
			guard let value = Self(rawValue: string) else {
				throw TypeCastError.invalidEnum
			}
			self = value
		}
	}

	private static func processOsmLabAerialsList(_ featureArray: [Feature]) throws -> [TileServer] {
		let categories: [Category: Bool] = [
			.photo: true,
			.historicphoto: true,
			.elevation: true
		]
		let supportedProjections = Set<String>(TileServer.supportedProjections)

		var externalAerials: [TileServer] = []
		for entry in featureArray {
			guard
				try entry.type == "Feature"
			else {
				print("Aerial: skipping non-Feature")
				continue
			}
			let properties = try entry.properties

			let type = try properties.type
			switch type {
			case .tms, .wms:
				break
			case .scanex,
			     .wms_endpoint,
			     .wmts,
			     .bing:
				// Not supported
				continue
			}

			let name = try properties.name
			if name.hasPrefix("Maxar ") {
				// we special case their imagery because they require a special key
				continue
			}

			let identifier = try properties.id

			if let category = try properties.category,
			   let supported = categories[category],
			   supported
			{
				// good
			} else if identifier == "OpenTopoMap" {
				// special exception for this one
			} else if identifier == MapBoxLocatorId {
				// this can replace our built-in version
			} else {
				continue
			}
			let startDateString = try properties.start_date
			let endDateString = try properties.end_date
			let endDate = TileServer.date(from: endDateString)
			if let endDate = endDate,
			   endDate.timeIntervalSinceNow < -20 * 365.0 * 24 * 60 * 60
			{
				continue
			}
			let url = try properties.url
			guard
				url.hasPrefix("http:") || url.hasPrefix("https:")
			else {
				print("Aerial: bad url: \(name)")
				continue
			}

			let maxZoom = try properties.max_zoom ?? 0

			if (try properties.overlay) ?? false,
			   identifier != MapBoxLocatorId
			{
				// we don@"t support overlays except locator
				continue
			}

			// we only support some types of WMS projections
			var projection: String?
			if type == .wms {
				projection = try properties.available_projections?.first(where: { supportedProjections.contains($0) })
				if projection == nil {
					continue
				}
			}

			let attribIconString = try properties.icon
			let attribDict = try properties.attribution
			let attribString = try attribDict?.text ?? ""
			let attribUrl = try attribDict?.url ?? ""

			let best = try properties.best ?? false

			// support for {apikey}
			var apikey = ""
			if identifier == MapBoxLocatorId || identifier == MapBoxLayerId {
				apikey = MapboxLocatorToken
			} else if url.contains(".thunderforest.com/") {
				// Please don't use in other apps. Sign up for a free account at Thunderforest.com insead.
				apikey = "be3dc024e3924c22beb5f841d098a8a3"
			}
			if url.contains("{apikey}"),
			   apikey == ""
			{
				print("Missing {apikey} for \(name)")
				continue
			}

			let service = TileServer(withName: name,
			                         identifier: identifier,
			                         url: url,
			                         best: best,
			                         apiKey: apikey,
			                         maxZoom: maxZoom,
			                         roundUp: true,
			                         startDate: startDateString,
			                         endDate: endDateString,
			                         wmsProjection: projection,
			                         geoJSON: try? entry.geometry,
			                         attribString: attribString,
			                         attribIconString: attribIconString,
			                         attribUrl: attribUrl)

			externalAerials.append(service)
		}
		return externalAerials
	}

	static func processOsmLabAerialsData(_ data: Data?) -> [TileServer] {
		guard let data = data,
		      data.count > 0
		else { return [] }

		do {
			let json = try JSONSerialization.jsonObject(with: data, options: [])
			let welcome = try Welcome(json)

			if let meta = try welcome.meta {
				// new ELI variety
				guard try meta.format_version == "1.0",
				      try welcome.type == "FeatureCollection"
				else { return [] }
			} else {
				// josm variety
			}
			let features = try welcome.features
			return try Self.processOsmLabAerialsList(features)
		} catch {
			print("\(error)")
			return []
		}
	}
}
