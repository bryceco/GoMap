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
	let bezierPath: UIBezierPath

	private static func addPoints(_ points: [[NSNumber]], to path: UIBezierPath) {
		var first = true
		for pt in points {
			if pt.count != 2 {
				continue
			}
			let lon = CGFloat(pt[0].doubleValue)
			let lat = CGFloat(pt[1].doubleValue)
			let cgPoint = CGPoint(x: lon, y: lat)
			if first {
				path.move(to: cgPoint)
				first = false
			} else {
				path.addLine(to: cgPoint)
			}
		}
		path.close()
	}

	init?(geometry: [String: Any?]) {
		guard let polygonPoints = geometry["coordinates"],
		      let type = geometry["type"] as? String
		else { return nil }

		let path = UIBezierPath()
		switch type {
		case "Polygon":
			guard let polygonPoints = polygonPoints as? [[[NSNumber]]] else { return nil }
			for loop in polygonPoints {
				Self.addPoints(loop, to: path)
			}
		case "MultiPolygon":
			guard let polygonPoints = polygonPoints as? [[[[NSNumber]]]] else { return nil }
			for outer in polygonPoints {
				for loop in outer {
					Self.addPoints(loop, to: path)
				}
			}
		default:
			return nil
		}
		bezierPath = path
	}
}
