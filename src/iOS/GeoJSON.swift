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

// Sometimes the geojson points use double, and other times NSNumber, so
// this allows us to treat both identically:
protocol DoubleValue {
	var doubleValue: Double { get }
}

extension Double: DoubleValue {
	var doubleValue: Double { self }
}

extension NSNumber: DoubleValue {}

struct GeoJSON: Codable, FastCodable {
	enum PointList: Codable, FastCodable {
		case polygon(points: [[[Double]]])
		case multiPolygon(points: [[[[Double]]]])

		func fastEncode(to encoder: FastEncoder) {
			switch self {
			case let .multiPolygon(points):
				1.fastEncode(to: encoder)
				points.fastEncode(to: encoder)
			case let .polygon(points):
				2.fastEncode(to: encoder)
				points.fastEncode(to: encoder)
			}
		}

		init(fromFast decoder: FastDecoder) throws {
			let type = try Int(fromFast: decoder)
			switch type {
			case 1:
				let points = try [[[[Double]]]].init(fromFast: decoder)
				self = .multiPolygon(points: points)
			case 2:
				let points = try [[[Double]]].init(fromFast: decoder)
				self = .polygon(points: points)
			default:
				fatalError()
			}
		}

		init(from decoder: Decoder) throws {
			// If we're decoding JSON then we may not know the type, so just guess until one works
			let container = try decoder.singleValueContainer()
			// These are used if it was encoded by a Swift synthesized encoder
			if let x = try? container.decode([String: [String: [[[Double]]]]].self) {
				self = .polygon(points: x.first!.value.first!.value)
				return
			}
			if let x = try? container.decode([String: [String: [[[[Double]]]]]].self) {
				self = .multiPolygon(points: x.first!.value.first!.value)
				return
			}
			// These are used if we're decoding JSON from CountryCoder borders.json
			if let x = try? container.decode([[[Double]]].self) {
				self = .polygon(points: x)
				return
			}
			if let x = try? container.decode([[[[Double]]]].self) {
				self = .multiPolygon(points: x)
				return
			}
			throw DecodingError.typeMismatch(PointList.self,
			                                 DecodingError.Context(codingPath: decoder.codingPath,
			                                                       debugDescription: "Wrong type for Geometry.pointList"))
		}
	}

	let coordinates: PointList
	var type: GeometryType {
		switch coordinates {
		case .polygon: return .polygon
		case .multiPolygon: return .multiPolygon
		}
	}

	private enum CodingKeys: String, CodingKey {
		case coordinates
	}

	init(from decoder: Decoder) throws {
		do {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			coordinates = try container.decode(PointList.self, forKey: .coordinates)
			bezierPath = try Self.bezierPath(for: coordinates)
		} catch {
			print("\(error)")
			throw error
		}
	}

	func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(coordinates, forKey: .coordinates)
	}

	func fastEncode(to encoder: FastEncoder) {
		coordinates.fastEncode(to: encoder)
	}

	init(fromFast decoder: FastDecoder) throws {
		coordinates = try PointList(fromFast: decoder)
		bezierPath = try Self.bezierPath(for: coordinates)
	}

	init?(geometry: [String: Any]?) throws {
		guard let geometry = geometry else { return nil }
		guard
			let type = geometry["type"] as? String,
			let type = GeometryType(rawValue: type),
			let points = geometry["coordinates"] as? [Any]
		else {
			throw GeoJsonError.invalidFormat
		}
		switch type {
		case .polygon:
			guard let nsPoints = points as? [[[NSNumber]]] else { throw GeoJsonError.invalidFormat }
			coordinates = .polygon(points: nsPoints.map { $0.map { $0.map { $0.doubleValue }}})
		case .multiPolygon:
			guard let nsPoints = points as? [[[[NSNumber]]]] else { throw GeoJsonError.invalidFormat }
			coordinates = .multiPolygon(points: nsPoints.map { $0.map { $0.map { $0.map { $0.doubleValue }}}})
		}
		bezierPath = try Self.bezierPath(for: coordinates)
	}

	enum GeometryType: String, Codable {
		case multiPolygon = "MultiPolygon"
		case polygon = "Polygon"
	}

	enum GeoJsonError: Error {
		case invalidFormat
	}

	var bezierPath: UIBezierPath

	var cgPath: CGPath { return bezierPath.cgPath }

	func contains(_ point: CGPoint) -> Bool {
		return bezierPath.contains(point)
	}

	func contains(_ latLon: LatLon) -> Bool {
		let cgPoint = CGPoint(x: latLon.lon, y: latLon.lat)
		return contains(cgPoint)
	}

	init(type: GeometryType, points: PointList) throws {
		coordinates = points
		bezierPath = try Self.bezierPath(for: points)

		// verify the type is consistent
		guard type == self.type else {
			throw GeoJsonError.invalidFormat
		}
	}
}

// MARK: Bezier path stuff

extension GeoJSON {
	private static func pointForPointArray<T: DoubleValue>(_ point: [T]) throws -> CGPoint {
		guard point.count == 2 else {
			throw GeoJsonError.invalidFormat
		}
		let lon = point[0].doubleValue
		let lat = point[1].doubleValue
		return CGPoint(x: lon, y: lat)
	}

	private static func addLoopPoints<T: DoubleValue>(_ points: [[T]], to path: UIBezierPath) throws {
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
	private static func addPolygonPoints<T: DoubleValue>(_ points: [[[T]]], to path: UIBezierPath) throws {
		for loop in points {
			try Self.addLoopPoints(loop, to: path)
		}
	}

	// A MultiPolygon is a list of Polygons
	private static func addMultiPolygonPoints<T: DoubleValue>(_ points: [[[[T]]]], to path: UIBezierPath) throws {
		for loop in points {
			try Self.addPolygonPoints(loop, to: path)
		}
	}

	static func bezierPathFor<T: DoubleValue>(polygon points: [[[T]]]) throws -> UIBezierPath {
		let path = UIBezierPath()
		try Self.addPolygonPoints(points, to: path)
		return path
	}

	static func bezierPathFor<T: DoubleValue>(multipolygon points: [[[[T]]]]) throws -> UIBezierPath {
		let path = UIBezierPath()
		try Self.addMultiPolygonPoints(points, to: path)
		return path
	}

	static func bezierPath(for coordinates: PointList) throws -> UIBezierPath {
		switch coordinates {
		case let .polygon(points):
			return try Self.bezierPathFor(polygon: points)
		case let .multiPolygon(points):
			return try Self.bezierPathFor(multipolygon: points)
		}
	}
}
