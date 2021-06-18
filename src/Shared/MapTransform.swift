//
//  MapTransform.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 6/17/21.
//  Copyright © 2021 Bryce. All rights reserved.
//

import Foundation
import CoreGraphics
import CoreLocation

private func FromBirdsEye(screenPoint point: OSMPoint, screenCenter center: CGPoint, birdsEyeDistance: Double, birdsEyeRotation: Double) -> OSMPoint {
	var point = point
	let D = birdsEyeDistance // distance from eye to center of screen
	let r = birdsEyeRotation

	point.x -= Double(center.x)
	point.y -= Double(center.y)

	point.y *= D / (D * cos(r) + point.y * sin(r))
	point.x -= point.x * point.y * sin(r) / D

	point.x += Double(center.x)
	point.y += Double(center.y)
	return point
}

private func ToBirdsEye(screenPoint point: OSMPoint, screenCenter center: CGPoint, _ birdsEyeDistance: Double, _ birdsEyeRotation: Double) -> OSMPoint {
	var point = point
	// narrow things toward top of screen
	let D = birdsEyeDistance // distance from eye to center of screen
	point.x -= Double(center.x)
	point.y -= Double(center.y)

	let z: Double = point.y * -sin(birdsEyeRotation) // rotation around x axis gives a z value from y offset
	var scale = D / (D + z)
	if scale < 0 {
		scale = 1.0 / 0.0
	}
	point.x *= scale
	point.y *= scale * cos(birdsEyeRotation)

	point.x += Double(center.x)
	point.y += Double(center.y)
	return point
}

/// Convert from latitude to Mercator projected latitude
@inline(__always) public func lat2latp(_ a: Double) -> Double {
	return 180 / .pi * log(tan(.pi / 4 + a * (.pi / 180) / 2))
}

/// Convert Mercator projected latitude to latitude
@inline(__always) public func latp2lat(_ a: Double) -> Double {
	return 180 / .pi * (2 * atan(exp(a * .pi / 180)) - .pi / 2)
}


/// Encapsulates all information for translating between a lat/lon coordinate and the screen
final class MapTransform {

	var center: CGPoint = .zero	// screen center, needed for bird's eye calculations

	// This matrix translates between a "map point" (a 256x256 square) and the screen
	var transform: OSMTransform = OSMTransform.identity {
		didSet {
			observers.removeAll(where: {$0.object == nil})
			observers.forEach({ $0.callback() })
		}
	}

	// These are used for 3-D effects. Rotation is the amount of tilt off the z-axis.
	var birdsEyeRotation = 0.0
	let birdsEyeDistance = 1000.0

	func birdsEye() -> (distance: Double, rotation: Double)? {
		if self.birdsEyeRotation != 0.0 {
			return (distance: self.birdsEyeDistance, rotation: self.birdsEyeRotation)
		} else {
			return nil
		}
	}

	func toBirdsEye(_ point: OSMPoint, _ center: CGPoint) -> OSMPoint {
		return ToBirdsEye( screenPoint: point, screenCenter: center, self.birdsEyeDistance, self.birdsEyeRotation)
	}

	// MARK: observe
	private struct Observer {
		weak var object: AnyObject?
		var callback: () -> Void
	}
	private var observers: [Observer] = []

	func observe(by object: AnyObject, callback: @escaping ()->Void) {
		observers.append( Observer(object: object, callback: callback) )
	}

	// MARK: transform screenPoint <--> mapPoint

	func screenPoint(forMapPoint point: OSMPoint, birdsEye: Bool) -> OSMPoint {
		var point = point.withTransform( transform )
		if birdsEyeRotation != 0.0 && birdsEye {
			point = ToBirdsEye(screenPoint: point, screenCenter: center, birdsEyeDistance, birdsEyeRotation)
		}
		return point
	}
	func mapPoint(forScreenPoint point: OSMPoint, birdsEye: Bool) -> OSMPoint {
		var point = point
		if birdsEyeRotation != 0.0 && birdsEye {
			point = FromBirdsEye(screenPoint: point,
								 screenCenter: center,
								 birdsEyeDistance: Double(birdsEyeDistance),
								 birdsEyeRotation: Double(birdsEyeRotation))
		}
		point = point.withTransform( transform.inverse() )
		return point
	}

	// MARK: transform mapPoint <--> latLon

	/// Convert Web-Mercator projection of 0..256 x 0..256 to longitude/latitude
	static func latLon(forMapPoint point: OSMPoint) -> LatLon {
		 var x: Double = point.x / 256
		 var y: Double = point.y / 256
		 x = x - floor(x) // modulus
		 y = y - floor(y)
		 x = x - 0.5
		 y = y - 0.5

		 return LatLon( x: 360 * x,
						y: 90 - 360 * atan(exp(y * 2 * .pi)) / .pi )
	 }

	 /// Convert longitude/latitude to a Web-Mercator projection of 0..256 x 0..256
	 static func mapPoint(forLatLon pt: LatLon) -> OSMPoint {
		 let x = (pt.longitude + 180) / 360
		 let sinLatitude = sin(pt.latitude * .pi / 180)
		 let y = 0.5 - log((1 + sinLatitude) / (1 - sinLatitude)) / (4 * .pi)
		 let point = OSMPoint(x: x * 256, y: y * 256)
		 return point
	 }

	// MARK: transform screenPoint <--> latLon

	func latLon(forScreenPoint point: CGPoint) -> LatLon {
		let mapPoint = self.mapPoint(forScreenPoint: OSMPoint(point), birdsEye: true)
		let coord = Self.latLon(forMapPoint: mapPoint)
		return coord
	}
	func screenPoint(forLatLon latLon: LatLon, birdsEye: Bool) -> CGPoint {
		var pt = Self.mapPoint(forLatLon: latLon)
		pt = screenPoint(forMapPoint: pt, birdsEye: birdsEye)
		return CGPoint(pt)
	}

	// MARK: transform screenRect <--> mapRect

	func screenRect(fromMapRect rect: OSMRect) -> OSMRect {
		return rect.withTransform( transform )
	}
	func mapRect(fromScreenRect rect: OSMRect) -> OSMRect {
		return rect.withTransform( transform.inverse() )
	}

	// MARK: transform screenRect <--> latLonRect

	static func mapRect(forLatLonRect rc: OSMRect) -> OSMRect {
		let ll1 = LatLon( latitude: rc.origin.y + rc.size.height, longitude: rc.origin.x )
		let ll2 = LatLon( latitude: rc.origin.y, longitude: rc.origin.x + rc.size.width )
		let p1 = Self.mapPoint( forLatLon: ll1 ) // latitude increases opposite of map
		let p2 = Self.mapPoint( forLatLon: ll2 )
		let rc = OSMRect(x: p1.x, y: p1.y, width: p2.x - p1.x, height: p2.y - p1.y) // map size
		return rc
	}

	static func latLon(forMapRect rc: OSMRect ) -> OSMRect {
		var rc = rc
		var southwest = OSMPoint(x: rc.origin.x, y: rc.origin.y + rc.size.height)
		var northeast = OSMPoint(x: rc.origin.x + rc.size.width, y: rc.origin.y)
		southwest = OSMPoint( MapTransform.latLon(forMapPoint: southwest) )
		northeast = OSMPoint( MapTransform.latLon(forMapPoint: northeast) )
		rc.origin.x = southwest.x
		rc.origin.y = southwest.y
		rc.size.width = northeast.x - southwest.x
		rc.size.height = northeast.y - southwest.y
		if rc.size.width < 0 {
			rc.size.width += 360
		}
		if rc.size.height < 0 {
			rc.size.height += 180
		}
		return rc
	}

	// MARK: transform screenRect <--> mapRect

	func boundingScreenRect(forMapRect rc: OSMRect) -> CGRect {
		let corners2 = [OSMPoint(x: rc.origin.x, y: rc.origin.y),
						OSMPoint(x: rc.origin.x + rc.size.width, y: rc.origin.y),
						OSMPoint(x: rc.origin.x + rc.size.width, y: rc.origin.y + rc.size.height),
						OSMPoint(x: rc.origin.x, y: rc.origin.y + rc.size.height)]

		let corners = corners2.map { screenPoint(forMapPoint: $0, birdsEye: false) }

		var minX = corners[0].x
		var minY = corners[0].y
		var maxX = minX
		var maxY = minY
		for i in 1..<4 {
			minX = Double(min(minX, corners[i].x))
			maxX = Double(max(maxX, corners[i].x))
			minY = Double(min(minY, corners[i].y))
			maxY = Double(max(maxY, corners[i].y))
		}
		return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
	}

	func boundingMapRect(forScreenRect rc: OSMRect) -> OSMRect {
		let corners2 = [OSMPoint(x: rc.origin.x, y: rc.origin.y),
						OSMPoint(x: rc.origin.x + rc.size.width, y: rc.origin.y),
						OSMPoint(x: rc.origin.x + rc.size.width, y: rc.origin.y + rc.size.height),
						OSMPoint(x: rc.origin.x, y: rc.origin.y + rc.size.height)]
		let corners = corners2.map { mapPoint(forScreenPoint: $0, birdsEye: true) }
		var minX = corners[0].x
		var minY = corners[0].y
		var maxX = minX
		var maxY = minY
		for i in 1..<4 {
			minX = Double(min(minX, corners[i].x))
			maxX = Double(max(maxX, corners[i].x))
			minY = Double(min(minY, corners[i].y))
			maxY = Double(max(maxY, corners[i].y))
		}
		return OSMRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
	}

	// MARK: miscellaneous

	func zoom() -> Double {
		return transform.zoom()
	}
	func scale() -> Double {
		return transform.scale()
	}
	func rotation() -> Double {
		return transform.rotation()
	}

	func wrapScreenPoint(_ pt: CGPoint, screenBounds: CGRect) -> CGPoint {
		var pt = pt
		if true /*fabs(_screenFromMapTransform.a) < 16 && fabs(_screenFromMapTransform.c) < 16*/ {
			// only need to do this if we're zoomed out all the way: pick the best world map on which to display location

			let rc = screenBounds
			let unitX = transform.unitX()
			let unitY = OSMPoint(x: -unitX.y, y: unitX.x)
			let mapSize: Double = 256 * transform.scale()
			if pt.x >= rc.origin.x + rc.size.width {
				pt.x -= CGFloat(mapSize * unitX.x)
				pt.y -= CGFloat(mapSize * unitX.y)
			} else if pt.x < rc.origin.x {
				pt.x += CGFloat(mapSize * unitX.x)
				pt.y += CGFloat(mapSize * unitX.y)
			}
			if pt.y >= rc.origin.y + rc.size.height {
				pt.x -= CGFloat(mapSize * unitY.x)
				pt.y -= CGFloat(mapSize * unitY.y)
			} else if pt.y < rc.origin.y {
				pt.x += CGFloat(mapSize * unitY.x)
				pt.y += CGFloat(mapSize * unitY.y)
			}
		}
		return pt
	}

	func metersPerPixel(atScreenPoint point: CGPoint) -> Double {
		let p1 = point
		let p2 = CGPoint(x: p1.x + 1.0, y: p1.y)	// one pixel apart
		let c1 = latLon(forScreenPoint: p1)
		let c2 = latLon(forScreenPoint: p2)
		let meters = GreatCircleDistance(c1, c2)
		return meters
	}

	func point(on object: OsmBaseObject, for point: CGPoint) -> CGPoint {
		let latLon = latLon(forScreenPoint: point)
		let latLon2 = object.pointOnObjectForPoint( latLon )
		let pos = screenPoint(forLatLon: latLon2, birdsEye: true)
		return pos
	}


}
