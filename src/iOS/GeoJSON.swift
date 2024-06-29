//
//  GeoJSON.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 10/25/22.
//  Copyright © 2022 Bryce Cogswell. All rights reserved.
//

import Foundation
import UIKit.UIBezierPath

enum GeoJsonError: Error {
	case unsupportedFormat
	case invalidFormat
}

struct GeoJSONFile: Decodable {
	let type: String // e.g. "FeatureCollection"
	let features: [GeoJSONFeature]

	init(data: Data) throws {
		self = try JSONDecoder().decode(Self.self, from: data)
	}

	init(url: URL) throws {
		let data = try Data(contentsOf: url)
		try self.init(data: data)
	}

	func firstPoint() -> LatLon? {
		// First try to get a point connected to a line
		if let pt = features.lazy.compactMap({ $0.geometry?.firstLinePoint() }).first {
			return pt
		}
		// If that fails then take any point
		return features.first?.geometry?.firstPoint()
	}
}

struct GeoJSONFeature: Decodable {
	let type: String // e.g. "Feature"
	let id: String? // String or Number
	let geometry: GeoJSONGeometry?
	let properties: AnyJSON?
}

extension LatLon {
	init(array: [Double]) throws {
		if array.count != 2 {
			throw GeoJsonError.invalidFormat
		}
		lon = array[0]
		lat = array[1]
	}

	init(array: [NSNumber]) throws {
		if array.count != 2 {
			throw GeoJsonError.invalidFormat
		}
		lon = array[0].doubleValue
		lat = array[1].doubleValue
	}

	init(from decoder: Decoder) throws {
		do {
			enum CodingKeys: String, CodingKey {
				case lat
				case lon
			}
			let container = try decoder.container(keyedBy: CodingKeys.self)
			let lat = try container.decode(Double.self, forKey: .lat)
			let lon = try container.decode(Double.self, forKey: .lon)
			self.init(lon: lon, lat: lat)
		} catch {
			// try decoding as [Double]
			let container = try decoder.singleValueContainer()
			let array = try container.decode([Double].self)
			try self.init(array: array)
		}
	}
}

struct GeoJSONGeometry: Codable {
	let geometryPoints: GeometryType
	let latLonBezierPath: UIBezierPath?
	let uuid = UUID()

	typealias LineString = [LatLon]
	typealias Polygon = [[LatLon]]

	enum GeometryType: Codable {
		case point(points: LatLon)
		case multiPoint(points: [LatLon])
		case lineString(points: LineString)
		case multiLineString(points: [LineString])
		case polygon(points: Polygon)
		case multiPolygon(points: [Polygon])
		case geometryCollection(points: [GeoJSONGeometry])

		private enum CodingKeys: String, CodingKey {
			case type
			case coordinates
			case geometries
		}

		// This is called when parsing NSI geojsons, CountryCoder, etc
		init(from decoder: Decoder) throws {
			do {
				let container = try decoder.container(keyedBy: CodingKeys.self)
				let type = try container.decode(String.self, forKey: .type)
				switch type {
				case "Point":
					let points = try container.decode(LatLon.self, forKey: .coordinates)
					self = .point(points: points)
				case "MultiPoint":
					let points = try container.decode([LatLon].self, forKey: .coordinates)
					self = .multiPoint(points: points)
				case "LineString":
					let points = try container.decode([LatLon].self, forKey: .coordinates)
					self = .lineString(points: points)
				case "MultiLineString":
					let points = try container.decode([[LatLon]].self, forKey: .coordinates)
					self = .multiLineString(points: points)
				case "Polygon":
					let points = try container.decode([[LatLon]].self, forKey: .coordinates)
					self = .polygon(points: points)
				case "MultiPolygon":
					let points = try container.decode([[[LatLon]]].self, forKey: .coordinates)
					self = .multiPolygon(points: points)
				case "GeometryCollection":
					let points = try container.decode([GeoJSONGeometry].self, forKey: .geometries)
					self = .geometryCollection(points: points)
				default:
					throw GeoJsonError.invalidFormat
				}
			} catch {
				print("\(error)")
				throw error
			}
		}

		func encode(to encoder: any Encoder) throws {
			// not implemented
			fatalError()
		}

		// Everything below is for when we decoded the JSON explicitely:

		private init(pointJSON json: Any) throws {
			guard let nsPoints = json as? [NSNumber] else { throw GeoJsonError.invalidFormat }
			self = .point(points: try LatLon(array: nsPoints))
		}

		private init(multiPointJSON json: Any) throws {
			guard let nsPoints = json as? [[NSNumber]] else { throw GeoJsonError.invalidFormat }
			self = .multiPoint(points: try nsPoints.map { try LatLon(array: $0) })
		}

		private init(lineStringJSON json: Any) throws {
			guard let nsPoints = json as? [[NSNumber]] else { throw GeoJsonError.invalidFormat }
			self = .lineString(points: try nsPoints.map { try LatLon(array: $0) })
		}

		private init(multiLineStringJSON json: Any) throws {
			guard let nsPoints = json as? [[[NSNumber]]] else { throw GeoJsonError.invalidFormat }
			self = .multiLineString(points: try nsPoints.map { try $0.map { try LatLon(array: $0) }})
		}

		private init(polygonJSON json: Any) throws {
			guard let nsPoints = json as? [[[NSNumber]]] else { throw GeoJsonError.invalidFormat }
			self = .polygon(points: try nsPoints.map { try $0.map { try LatLon(array: $0) }})
		}

		private init(multiPolygonJSON json: Any) throws {
			guard let nsPoints = json as? [[[[NSNumber]]]] else { throw GeoJsonError.invalidFormat }
			self = .multiPolygon(points: try nsPoints.map { try $0.map { try $0.map { try LatLon(array: $0) }}})
		}

		private init(geometryCollectionJSON json: Any) throws {
			guard let list = json as? [[String: Any]] else { throw GeoJsonError.invalidFormat }
			let geomList = try list.map { try GeoJSONGeometry(geometry: $0) }
			self = .geometryCollection(points: geomList)
		}

		// This init is used by TileServerList, where the JSON is already decoded
		init(json: [String: Any]) throws {
			guard
				let type = json["type"] as? String,
				let points = json["coordinates"]
			else {
				throw GeoJsonError.invalidFormat
			}
			switch type {
			case "Point":
				self = try GeometryType(pointJSON: points)
			case "MultiPoint":
				self = try GeometryType(multiPointJSON: points)
			case "LineString":
				self = try GeometryType(lineStringJSON: points)
			case "MultiLineString":
				self = try GeometryType(multiLineStringJSON: points)
			case "Polygon":
				self = try GeometryType(polygonJSON: points)
			case "MultiPolygon":
				self = try GeometryType(multiPolygonJSON: points)
			case "GeometryCollection":
				self = try GeometryType(geometryCollectionJSON: points)
			default:
				throw GeoJsonError.invalidFormat
			}
		}
	}

	init(geometry: GeometryType) {
		geometryPoints = geometry
		do {
			latLonBezierPath = try geometryPoints.bezierPath()
		} catch {
			print("GeoJSON bezier path: \(error)")
			latLonBezierPath = nil
		}
	}

	init(geometry: [String: Any]) throws {
		self.init(geometry: try GeometryType(json: geometry))
	}

	init?(geometry: [String: Any]?) throws {
		guard let geometry = geometry else { return nil }
		try self.init(geometry: geometry)
	}

	init(from decoder: Decoder) throws {
		do {
			self.init(geometry: try GeometryType(from: decoder))
		} catch {
			print("\(error)")
			throw error
		}
	}

	func firstPoint() -> LatLon? {
		switch geometryPoints {
		case let .point(points: pt):
			return pt
		case let .multiPoint(points: pts):
			return pts.first
		default:
			if let pt = latLonBezierPath?.cgPath.getPoints().first {
				return LatLon(lon: pt.x, lat: pt.y)
			}
		}
		return nil
	}

	func firstLinePoint() -> LatLon? {
		if let pt = latLonBezierPath?.cgPath.getPoints().first {
			return LatLon(lon: pt.x, lat: pt.y)
		}
		return nil
	}

	func encode(to encoder: Encoder) throws {
		try geometryPoints.encode(to: encoder)
	}

	func contains(_ point: CGPoint) -> Bool {
		return latLonBezierPath?.contains(point) ?? false
	}

	func contains(_ latLon: LatLon) -> Bool {
		let cgPoint = CGPoint(x: latLon.lon, y: latLon.lat)
		return contains(cgPoint)
	}
}

// MARK: Bezier path stuff

extension GeoJSONGeometry.GeometryType {
	private static func cgForPoint(_ point: LatLon) -> CGPoint {
		return CGPoint(x: point.lon, y: point.lat)
	}

	private static func addLineStringPoints(_ points: [LatLon], to path: UIBezierPath) throws {
		if points.count < 2 {
			throw GeoJsonError.invalidFormat
		}
		path.move(to: Self.cgForPoint(points[0]))
		for pt in points.dropFirst() {
			path.addLine(to: Self.cgForPoint(pt))
		}
	}

	private static func addLoopPoints(_ points: [LatLon], to path: UIBezierPath) throws {
		if points.count < 4 {
			throw GeoJsonError.invalidFormat
		}
		path.move(to: Self.cgForPoint(points[0]))
		for pt in points.dropFirst() {
			path.addLine(to: Self.cgForPoint(pt))
		}
		path.close()
	}

	// A Polygon is an outer ring plus optional holes
	private static func addPolygonPoints(_ points: [[LatLon]], to path: UIBezierPath) throws {
		for loop in points {
			try Self.addLoopPoints(loop, to: path)
		}
	}

	// A MultiPolygon is a list of Polygons
	private static func addMultiPolygonPoints(_ points: [[[LatLon]]], to path: UIBezierPath) throws {
		for loop in points {
			try Self.addPolygonPoints(loop, to: path)
		}
	}

	static func bezierPathFor(lineString points: [LatLon]) throws -> UIBezierPath {
		let path = UIBezierPath()
		try Self.addLineStringPoints(points, to: path)
		return path
	}

	static func bezierPathFor(multiLineString points: [[LatLon]]) throws -> UIBezierPath {
		let path = UIBezierPath()
		for line in points {
			try Self.addLineStringPoints(line, to: path)
		}
		return path
	}

	static func bezierPathFor(polygon points: [[LatLon]]) throws -> UIBezierPath {
		let path = UIBezierPath()
		try Self.addPolygonPoints(points, to: path)
		return path
	}

	static func bezierPathFor(multipolygon points: [[[LatLon]]]) throws -> UIBezierPath {
		let path = UIBezierPath()
		try Self.addMultiPolygonPoints(points, to: path)
		return path
	}

	func bezierPath() throws -> UIBezierPath {
		switch self {
		case .point, .multiPoint:
			return UIBezierPath()
		case let .lineString(points):
			return try Self.bezierPathFor(lineString: points)
		case let .multiLineString(points):
			return try Self.bezierPathFor(multiLineString: points)
		case let .polygon(points):
			return try Self.bezierPathFor(polygon: points)
		case let .multiPolygon(points):
			return try Self.bezierPathFor(multipolygon: points)
		case let .geometryCollection(points):
			let all = UIBezierPath()
			for geo in points {
				let path = try geo.geometryPoints.bezierPath()
				all.append(path)
			}
			return all
		}
	}
}
