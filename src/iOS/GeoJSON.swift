//
//  GeoJSON.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 10/25/22.
//  Copyright © 2022 Bryce. All rights reserved.
//

import CoreGraphics.CGPath
import Foundation
import UIKit.UIBezierPath

protocol DoubleValue {
	var doubleValue: Double { get }
}

extension Double: DoubleValue {
	var doubleValue: Double { self }
}

extension NSNumber: DoubleValue {}

struct GeoJSON {
	struct Geometry: Decodable {
		enum PointList: Decodable {
			case polygon([[[Double]]])
			case multiPolygon([[[[Double]]]])

			init(from decoder: Decoder) throws {
				let container = try decoder.singleValueContainer()
				if let x = try? container.decode([[[Double]]].self) {
					self = .polygon(x)
					return
				}
				if let x = try? container.decode([[[[Double]]]].self) {
					self = .multiPolygon(x)
					return
				}
				throw DecodingError.typeMismatch(PointList.self,
				                                 DecodingError.Context(codingPath: decoder.codingPath,
				                                                       debugDescription: "Wrong type for Geometry.pointList"))
			}
		}

		let coordinates: PointList
		let type: GeometryType
	}

	enum GeometryType: String, Decodable {
		case multiPolygon = "MultiPolygon"
		case polygon = "Polygon"
	}

	enum GeoJsonError: Error {
		case invalidFormat
	}

	let bezierPath: UIBezierPath
	var cgPath: CGPath { return bezierPath.cgPath }

	func contains(_ point: CGPoint) -> Bool {
		return bezierPath.contains(point)
	}

	func contains(_ latLon: LatLon) -> Bool {
		let cgPoint = CGPoint(x: latLon.lon, y: latLon.lat)
		return contains(cgPoint)
	}

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

	static func bezierPathFor<T: DoubleValue>(polygon points: [[[T]]]) throws -> UIBezierPath  {
		let path = UIBezierPath()
		try Self.addPolygonPoints(points, to: path)
		return path
	}

	static func bezierPathFor<T: DoubleValue>(multipolygon points: [[[[T]]]]) throws -> UIBezierPath  {
		let path = UIBezierPath()
		try Self.addMultiPolygonPoints(points, to: path)
		return path
	}

	init(type: GeometryType, points: Geometry.PointList) throws {
		switch type {
		case .polygon:
			guard case let .polygon(points) = points else {
				throw GeoJsonError.invalidFormat
			}
			self.bezierPath = try Self.bezierPathFor(polygon: points)
		case .multiPolygon:
			guard case let .multiPolygon(points) = points else {
				throw GeoJsonError.invalidFormat
			}
			self.bezierPath = try Self.bezierPathFor(multipolygon: points)
		}
	}

	init(geometry: Geometry) throws {
		try self.init(type: geometry.type, points: geometry.coordinates)
	}

	init(geometry: [String: Any]) throws {
		guard let type = geometry["type"] as? String,
		      let points = geometry["coordinates"] as? [Any]
		else {
			throw GeoJsonError.invalidFormat
		}
		switch type {
		case GeometryType.polygon.rawValue:
			guard let nsPoints = points as? [[[NSNumber]]] else { throw GeoJsonError.invalidFormat }
			self.bezierPath = try Self.bezierPathFor(polygon: nsPoints)
		case GeometryType.multiPolygon.rawValue:
			guard let nsPoints = points as? [[[[NSNumber]]]] else { throw GeoJsonError.invalidFormat }
			self.bezierPath = try Self.bezierPathFor(multipolygon: nsPoints)
		default:
			throw GeoJsonError.invalidFormat
		}
	}
}
