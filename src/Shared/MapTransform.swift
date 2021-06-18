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

func FromBirdsEye(_ point: OSMPoint, center: CGPoint, birdsEyeDistance: Double, birdsEyeRotation: Double) -> OSMPoint {
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

func ToBirdsEye(_ point: OSMPoint, _ center: CGPoint, _ birdsEyeDistance: Double, _ birdsEyeRotation: Double) -> OSMPoint {
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

// point is 0..256
@inline(__always) func LongitudeLatitudeFromMapPoint(_ point: OSMPoint) -> OSMPoint {
	var x: Double = point.x / 256
	var y: Double = point.y / 256
	x = x - floor(x) // modulus
	y = y - floor(y)
	x = x - 0.5
	y = y - 0.5

	return OSMPoint( x: 360 * x,
					 y: 90 - 360 * atan(exp(y * 2 * .pi)) / .pi )
}

// Convert longitude/latitude to a Web-Mercator projection of 0..256 x 0..256
@inline(__always) func MapPointForLatitudeLongitude(_ latitude: Double, _ longitude: Double) -> OSMPoint {
	let x = (longitude + 180) / 360
	let sinLatitude = sin(latitude * .pi / 180)
	let y = 0.5 - log((1 + sinLatitude) / (1 - sinLatitude)) / (4 * .pi)
	let point = OSMPoint(x: x * 256, y: y * 256)
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



final class MapTransform {

	var center: CGPoint = .zero	// screen center, needed for bird's eye calculations
	var transform: OSMTransform = OSMTransform.identity {
		didSet {
			observers.removeAll(where: {$0.object == nil})
			observers.forEach({ $0.callback() })
		}
	}

	var birdsEyeRotation = 0.0
	let birdsEyeDistance = 1000.0

	func birdsEye() -> (distance: Double, rotation: Double)? {
		if self.birdsEyeRotation != 0.0 {
			return (distance: self.birdsEyeDistance, rotation: self.birdsEyeRotation)
		} else {
			return nil
		}
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

	// MARK: base

	func zoom() -> Double {
		return transform.zoom()
	}
	func scale() -> Double {
		return transform.scale()
	}
	func rotation() -> Double {
		return transform.rotation()
	}

	// MARK: transforms

	func point(on object: OsmBaseObject, for point: CGPoint) -> CGPoint {
		let latLon = longitudeLatitude(forScreenPoint: point, birdsEye: true)
		let latLon2 = object.pointOnObjectForPoint(OSMPoint(x: latLon.longitude, y: latLon.latitude))
		let pos = screenPoint(forLatitude: latLon2.y, longitude: latLon2.x, birdsEye: true)
		return pos
	}

	func longitudeLatitude(forScreenPoint point: CGPoint, birdsEye: Bool) -> CLLocationCoordinate2D {
		let mapPoint = self.mapPoint(fromScreenPoint: OSMPoint(point), birdsEye: birdsEye)
		let coord = LongitudeLatitudeFromMapPoint(mapPoint)
		let loc = CLLocationCoordinate2D(latitude: coord.y, longitude: coord.x)
		return loc
	}

	func screenPoint(forLatitude latitude: Double, longitude: Double, birdsEye: Bool) -> CGPoint {
		var pt = MapPointForLatitudeLongitude(latitude, longitude)
		pt = screenPoint(fromMapPoint: pt, birdsEye: birdsEye)
		return CGPoint(pt)
	}

	func screenPoint(fromMapPoint point: OSMPoint, birdsEye: Bool) -> OSMPoint {
		var point = point.withTransform( transform )
		if birdsEyeRotation != 0.0 && birdsEye {
			point = ToBirdsEye(point, center, Double(birdsEyeDistance), Double(birdsEyeRotation))
		}
		return point
	}
	func mapPoint(fromScreenPoint point: OSMPoint, birdsEye: Bool) -> OSMPoint {
		var point = point
		if birdsEyeRotation != 0.0 && birdsEye {
			point = FromBirdsEye(point,
								 center: center,
								 birdsEyeDistance: Double(birdsEyeDistance),
								 birdsEyeRotation: Double(birdsEyeRotation))
		}
		point = point.withTransform( transform.inverse() )
		return point
	}

	static func mapRect(forLatLonRect latLon: OSMRect) -> OSMRect {
		var rc = latLon
		let p1 = MapPointForLatitudeLongitude(rc.origin.y + rc.size.height, rc.origin.x) // latitude increases opposite of map
		let p2 = MapPointForLatitudeLongitude(rc.origin.y, rc.origin.x + rc.size.width)
		rc = OSMRect(x: p1.x, y: p1.y, width: p2.x - p1.x, height: p2.y - p1.y) // map size
		return rc
	}

	func screenRect(fromMapRect rect: OSMRect) -> OSMRect {
		return rect.withTransform( transform )
	}
	func mapRect(fromScreenRect rect: OSMRect) -> OSMRect {
		return rect.withTransform( transform.inverse() )
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

	func metersPerPixel(at point: CGPoint) -> Double {
		let p1 = point
		let p2 = CGPoint(x: p1.x + 1.0, y: p1.y)	// one pixel apart
		let c1 = longitudeLatitude(forScreenPoint: p1, birdsEye: false)
		let c2 = longitudeLatitude(forScreenPoint: p2, birdsEye: false)
		let o1 = OSMPoint(x: c1.longitude, y: c1.latitude)
		let o2 = OSMPoint(x: c2.longitude, y: c2.latitude)
		let meters = GreatCircleDistance(o1, o2)
		return meters
	}

}
