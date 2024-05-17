//
//  GeoJSON.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 10/25/22.
//  Copyright © 2022 Bryce Cogswell. All rights reserved.
//

import CoreGraphics.CGPath
import FastCodable
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
}

struct GeoJSONFeature: Decodable {
	let type: String // e.g. "Feature"
	let id: String?
	let geometry: GeoJSONGeometry
}

struct GeoJSONGeometry: Codable {
	let geometryPoints: GeometryType
	let bezierPath: UIBezierPath
	var cgPath: CGPath { return bezierPath.cgPath }

	typealias Point = [Double]
	typealias LineString = [Point]
	typealias Polygon = [[Point]]

	enum GeometryType: Codable {
		case point(points: Point)
		case multiPoint(points: [Point])
		case lineString(points: LineString)
		case multiLineString(points: [LineString])
		case polygon(points: Polygon)
		case multiPolygon(points: [Polygon])

		init(point points: [Any]) throws {
			guard let nsPoints = points as? [NSNumber] else { throw GeoJsonError.invalidFormat }
			self = .point(points: nsPoints.map { $0.doubleValue })
		}

		init(multiPoint points: [Any]) throws {
			guard let nsPoints = points as? [[NSNumber]] else { throw GeoJsonError.invalidFormat }
			self = .multiPoint(points: nsPoints.map { $0.map { $0.doubleValue }})
		}

		init(lineString points: [Any]) throws {
			guard let nsPoints = points as? [[NSNumber]] else { throw GeoJsonError.invalidFormat }
			self = .lineString(points: nsPoints.map { $0.map { $0.doubleValue }})
		}

		init(multiLineString points: [Any]) throws {
			guard let nsPoints = points as? [[[NSNumber]]] else { throw GeoJsonError.invalidFormat }
			self = .multiLineString(points: nsPoints.map { $0.map { $0.map { $0.doubleValue }}})
		}

		init(polygon points: [Any]) throws {
			guard let nsPoints = points as? [[[NSNumber]]] else { throw GeoJsonError.invalidFormat }
			self = .polygon(points: nsPoints.map { $0.map { $0.map { $0.doubleValue }}})
		}

		init(multiPolygon points: [Any]) throws {
			guard let nsPoints = points as? [[[[NSNumber]]]] else { throw GeoJsonError.invalidFormat }
			self = .multiPolygon(points: nsPoints.map { $0.map { $0.map { $0.map { $0.doubleValue }}}})
		}

		// This init is used by TileServerList, where the JSON is already decoded
		init(json: [String: Any]) throws {
			guard
				let type = json["type"] as? String,
				let points = json["coordinates"] as? [Any]
			else {
				throw GeoJsonError.invalidFormat
			}
			switch type {
			case "Point":
				self = try GeometryType(point: points)
			case "MultiPoint":
				self = try GeometryType(multiPoint: points)
			case "LineString":
				self = try GeometryType(lineString: points)
			case "MultiLineString":
				self = try GeometryType(multiLineString: points)
			case "Polygon":
				self = try GeometryType(polygon: points)
			case "MultiPolygon":
				self = try GeometryType(multiPolygon: points)
			default:
				throw GeoJsonError.invalidFormat
			}
		}

		private enum CodingKeys: String, CodingKey {
			case type
			case coordinates
		}

		init(from decoder: Decoder) throws {
			do {
				let container = try decoder.container(keyedBy: CodingKeys.self)
				let type = try container.decode(String.self, forKey: .type)
				switch type {
				case "Point":
					let points = try container.decode(Point.self, forKey: .coordinates)
					self = try GeometryType(point: points)
				case "MultiPoint":
					let points = try container.decode([Point].self, forKey: .coordinates)
					self = try GeometryType(multiPoint: points)
				case "LineString":
					let points = try container.decode(LineString.self, forKey: .coordinates)
					self = try GeometryType(lineString: points)
				case "MultiLineString":
					let points = try container.decode([LineString].self, forKey: .coordinates)
					self = try GeometryType(multiLineString: points)
				case "Polygon":
					let points = try container.decode(Polygon.self, forKey: .coordinates)
					self = try GeometryType(polygon: points)
				case "MultiPolygon":
					let points = try container.decode([Polygon].self, forKey: .coordinates)
					self = try GeometryType(multiPolygon: points)
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
	}

	init?(geometry: [String: Any]?) throws {
		guard let geometry = geometry else { return nil }
		geometryPoints = try GeometryType(json: geometry)
		bezierPath = try Self.bezierPath(for: geometryPoints)
	}

	init(from decoder: Decoder) throws {
		do {
			geometryPoints = try GeometryType(from: decoder)
			bezierPath = try Self.bezierPath(for: geometryPoints)
		} catch {
			print("\(error)")
			throw error
		}
	}

	func encode(to encoder: Encoder) throws {
		try geometryPoints.encode(to: encoder)
	}

	func contains(_ point: CGPoint) -> Bool {
		return bezierPath.contains(point)
	}

	func contains(_ latLon: LatLon) -> Bool {
		let cgPoint = CGPoint(x: latLon.lon, y: latLon.lat)
		return contains(cgPoint)
	}
}

// MARK: Bezier path stuff

extension GeoJSONGeometry {
	private static func pointForPointArray(_ point: [Double]) throws -> CGPoint {
		guard point.count == 2 else {
			throw GeoJsonError.invalidFormat
		}
		let lon = point[0]
		let lat = point[1]
		return CGPoint(x: lon, y: lat)
	}

	private static func addLineStringPoints(_ points: [[Double]], to path: UIBezierPath) throws {
		if points.count < 2 {
			throw GeoJsonError.invalidFormat
		}
		path.move(to: try Self.pointForPointArray(points[0]))
		for pt in points.dropFirst() {
			path.addLine(to: try Self.pointForPointArray(pt))
		}
	}

	private static func addLoopPoints(_ points: [[Double]], to path: UIBezierPath) throws {
		if points.count < 4 {
			throw GeoJsonError.invalidFormat
		}
		path.move(to: try Self.pointForPointArray(points[0]))
		for pt in points.dropFirst() {
			path.addLine(to: try Self.pointForPointArray(pt))
		}
		path.close()
	}

	// A Polygon is an outer ring plus optional holes
	private static func addPolygonPoints(_ points: [[[Double]]], to path: UIBezierPath) throws {
		for loop in points {
			try Self.addLoopPoints(loop, to: path)
		}
	}

	// A MultiPolygon is a list of Polygons
	private static func addMultiPolygonPoints(_ points: [[[[Double]]]], to path: UIBezierPath) throws {
		for loop in points {
			try Self.addPolygonPoints(loop, to: path)
		}
	}

	static func bezierPathFor(lineString points: [[Double]]) throws -> UIBezierPath {
		let path = UIBezierPath()
		try Self.addLineStringPoints(points, to: path)
		return path
	}

	static func bezierPathFor(multiLineString points: [[[Double]]]) throws -> UIBezierPath {
		let path = UIBezierPath()
		for line in points {
			try Self.addLineStringPoints(line, to: path)
		}
		return path
	}

	static func bezierPathFor(polygon points: [[[Double]]]) throws -> UIBezierPath {
		let path = UIBezierPath()
		try Self.addPolygonPoints(points, to: path)
		return path
	}

	static func bezierPathFor(multipolygon points: [[[[Double]]]]) throws -> UIBezierPath {
		let path = UIBezierPath()
		try Self.addMultiPolygonPoints(points, to: path)
		return path
	}

	static func bezierPath(for coordinates: GeometryType) throws -> UIBezierPath {
		switch coordinates {
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
		}
	}
}

extension GeoJSONGeometry.GeometryType: FastCodable {
	func fastEncode(to encoder: FastEncoder) {
		switch self {
		case let .point(points):
			1.fastEncode(to: encoder)
			points.fastEncode(to: encoder)
		case let .multiPoint(points):
			2.fastEncode(to: encoder)
			points.fastEncode(to: encoder)
		case let .lineString(points):
			3.fastEncode(to: encoder)
			points.fastEncode(to: encoder)
		case let .multiLineString(points):
			4.fastEncode(to: encoder)
			points.fastEncode(to: encoder)
		case let .polygon(points):
			5.fastEncode(to: encoder)
			points.fastEncode(to: encoder)
		case let .multiPolygon(points):
			6.fastEncode(to: encoder)
			points.fastEncode(to: encoder)
		}
	}

	init(fromFast decoder: FastDecoder) throws {
		let type = try Int(fromFast: decoder)
		switch type {
		case 1:
			let points = try [Double].init(fromFast: decoder)
			self = .point(points: points)
		case 2:
			let points = try [[Double]].init(fromFast: decoder)
			self = .multiPoint(points: points)
		case 3:
			let points = try [[Double]].init(fromFast: decoder)
			self = .lineString(points: points)
		case 4:
			let points = try [[[Double]]].init(fromFast: decoder)
			self = .multiLineString(points: points)
		case 5:
			let points = try [[[Double]]].init(fromFast: decoder)
			self = .polygon(points: points)
		case 6:
			let points = try [[[[Double]]]].init(fromFast: decoder)
			self = .multiPolygon(points: points)
		default:
			fatalError()
		}
	}
}

extension GeoJSONGeometry: FastCodable {
	func fastEncode(to encoder: FastEncoder) {
		geometryPoints.fastEncode(to: encoder)
	}

	init(fromFast decoder: FastDecoder) throws {
		geometryPoints = try GeometryType(fromFast: decoder)
		bezierPath = try Self.bezierPath(for: geometryPoints)
	}
}
