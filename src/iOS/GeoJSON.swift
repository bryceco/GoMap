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

final class GeoJSON {
	enum GeoJsonError: Error {
		case invalidFormat
	}

	private let bezierPath: UIBezierPath

	var cgPath: CGPath { return bezierPath.cgPath }

	func contains(_ point: CGPoint) -> Bool {
		return bezierPath.contains(point)
	}

	func contains(_ latLon: LatLon) -> Bool {
		let cgPoint = CGPoint(x: latLon.lon, y: latLon.lat)
		return contains(cgPoint)
	}

	private static func pointForPointArray(_ point: [NSNumber]) throws -> CGPoint {
		if point.count != 2 {
			throw GeoJsonError.invalidFormat
		}
		let lon = CGFloat(point[0].doubleValue)
		let lat = CGFloat(point[1].doubleValue)
		return CGPoint(x: lon, y: lat)
	}

	private static func addLoopPoints(_ points: [[NSNumber]], to path: UIBezierPath) throws {
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
	private static func addPolygonPoints(_ points: [[[NSNumber]]], to path: UIBezierPath) throws {
		for loop in points {
			try Self.addLoopPoints(loop, to: path)
		}
	}

	// A MultiPolygon is a list of Polygons
	private static func addMultiPolygonPoints(_ points: [[[[NSNumber]]]], to path: UIBezierPath) throws {
		for loop in points {
			try Self.addPolygonPoints(loop, to: path)
		}
	}

	init?(geometry: [String: Any?]) {
		guard let points = geometry["coordinates"],
		      let type = geometry["type"] as? String
		else { return nil }

		let path = UIBezierPath()
		do {
			switch type {
			case "Polygon":
				guard let points = points as? [[[NSNumber]]] else { return nil }
				try Self.addPolygonPoints(points, to: path)
			case "MultiPolygon":
				guard let points = points as? [[[[NSNumber]]]] else { return nil }
				try Self.addMultiPolygonPoints(points, to: path)
			default:
				return nil
			}
		} catch {
			return nil
		}
		bezierPath = path
	}
}
