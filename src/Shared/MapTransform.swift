//
//  MapTransform.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 6/17/21.
//  Copyright © 2021 Bryce Cogswell. All rights reserved.
//

import CoreGraphics
import CoreLocation
import Foundation

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
	var center: CGPoint = .zero // screen center, needed for bird's eye calculations

	static let latitudeLimit = 85.051128

	// This matrix translates between a "mapPoint" (a 256x256 mercator map of the world) and the screen
	var transform = OSMTransform.identity {
		didSet {
			notifyObservers()
		}
	}

	// MARK: Observers

	private struct Observer {
		weak var object: AnyObject?
		var callback: () -> Void
	}

	private var observers: [Observer] = []

	func observe(by object: AnyObject, callback: @escaping () -> Void) {
		observers.append(Observer(object: object, callback: callback))
	}

	func notifyObservers() {
		observers.removeAll(where: { $0.object == nil })
		observers.forEach({ $0.callback() })
	}

	// MARK: Bird's eye view

	// These are used for 3-D effects. Rotation is the amount of tilt off the z-axis.
	let birdsEyeDistance = 1000.0
	var birdsEyeRotation = 0.0 {
		didSet {
			notifyObservers()
		}
	}

	private static func FromBirdsEye(
		screenPoint point: OSMPoint,
		screenCenter center: CGPoint,
		birdsEyeDistance: Double,
		birdsEyeRotation: Double) -> OSMPoint
	{
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

	private static func ToBirdsEye(
		screenPoint point: OSMPoint,
		screenCenter center: CGPoint,
		_ birdsEyeDistance: Double,
		_ birdsEyeRotation: Double) -> OSMPoint
	{
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

	func birdsEye() -> (distance: Double, rotation: Double)? {
		if birdsEyeRotation != 0.0 {
			return (distance: birdsEyeDistance, rotation: birdsEyeRotation)
		} else {
			return nil
		}
	}

	func toBirdsEye(_ point: OSMPoint, _ center: CGPoint) -> OSMPoint {
		return Self.ToBirdsEye(screenPoint: point, screenCenter: center, birdsEyeDistance, birdsEyeRotation)
	}

	// MARK: Transform screenPoint <--> mapPoint

	func screenPoint(forMapPoint point: OSMPoint, birdsEye: Bool) -> CGPoint {
		var point = point.withTransform(transform)
		if birdsEyeRotation != 0.0, birdsEye {
			point = Self.ToBirdsEye(screenPoint: point, screenCenter: center, birdsEyeDistance, birdsEyeRotation)
		}
		return CGPoint(point)
	}

	func mapPoint(forScreenPoint point: OSMPoint, birdsEye: Bool) -> OSMPoint {
		var point = point
		if birdsEyeRotation != 0.0, birdsEye {
			point = Self.FromBirdsEye(screenPoint: point,
			                          screenCenter: center,
			                          birdsEyeDistance: Double(birdsEyeDistance),
			                          birdsEyeRotation: Double(birdsEyeRotation))
		}
		point = point.withTransform(transform.inverse())
		return point
	}

	// MARK: Transform mapPoint <--> latLon

	/// Convert Web-Mercator projection of 0..256 x 0..256 to longitude/latitude
	static func latLon(forMapPoint point: OSMPoint) -> LatLon {
		var x: Double = point.x / 256
		var y: Double = point.y / 256
		x = x - floor(x) // modulus
		x = x - 0.5
		y = y - 0.5

		return LatLon(x: 360 * x,
		              y: 90 - 360 * atan(exp(y * 2 * .pi)) / .pi)
	}

	/// Convert longitude/latitude to a Web-Mercator projection of 0..256 x 0..256
	static func mapPoint(forLatLon pt: LatLon) -> OSMPoint {
		let x = (pt.lon + 180) / 360
		let sinLatitude = sin(pt.lat * .pi / 180)
		let y = 0.5 - log((1 + sinLatitude) / (1 - sinLatitude)) / (4 * .pi)
		let point = OSMPoint(x: x * 256, y: y * 256)
		return point
	}

	// MARK: Transform screenPoint <--> latLon

	func latLon(forScreenPoint point: CGPoint) -> LatLon {
		let mapPoint = self.mapPoint(forScreenPoint: OSMPoint(point), birdsEye: true)
		let coord = Self.latLon(forMapPoint: mapPoint)
		return coord
	}

	func screenPoint(forLatLon latLon: LatLon, birdsEye: Bool) -> CGPoint {
		let pt = Self.mapPoint(forLatLon: latLon)
		return screenPoint(forMapPoint: pt, birdsEye: birdsEye)
	}

	// MARK: Transform screenRect <--> mapRect

	func screenRect(fromMapRect rect: OSMRect) -> OSMRect {
		return rect.withTransform(transform)
	}

	func mapRect(fromScreenRect rect: OSMRect) -> OSMRect {
		return rect.withTransform(transform.inverse())
	}

	// MARK: Transform screenRect <--> latLonRect

	static func mapRect(forLatLonRect rc: OSMRect) -> OSMRect {
		let ll1 = LatLon(latitude: rc.origin.y + rc.size.height, longitude: rc.origin.x)
		let ll2 = LatLon(latitude: rc.origin.y, longitude: rc.origin.x + rc.size.width)
		let p1 = Self.mapPoint(forLatLon: ll1) // latitude increases opposite of map
		let p2 = Self.mapPoint(forLatLon: ll2)
		let rc = OSMRect(x: p1.x, y: p1.y, width: p2.x - p1.x, height: p2.y - p1.y) // map size
		return rc
	}

	static func latLon(forMapRect rc: OSMRect) -> OSMRect {
		var rc = rc
		var southwest = OSMPoint(x: rc.origin.x, y: rc.origin.y + rc.size.height)
		var northeast = OSMPoint(x: rc.origin.x + rc.size.width, y: rc.origin.y)
		southwest = OSMPoint(MapTransform.latLon(forMapPoint: southwest))
		northeast = OSMPoint(MapTransform.latLon(forMapPoint: northeast))
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

	// MARK: Transform screenRect <--> mapRect

	static func boundingRectFor(points: [OSMPoint]) -> OSMRect {
		var minX = points[0].x
		var minY = points[0].y
		var maxX = minX
		var maxY = minY
		for pt in points.dropFirst() {
			minX = min(minX, pt.x)
			maxX = max(maxX, pt.x)
			minY = min(minY, pt.y)
			maxY = max(maxY, pt.y)
		}
		return OSMRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
	}

	func boundingScreenRect(forMapRect rc: OSMRect) -> CGRect {
		let corners = rc.corners().map { OSMPoint(screenPoint(forMapPoint: $0, birdsEye: true)) }
		let rect = Self.boundingRectFor(points: corners)
		return CGRect(rect)
	}

	func boundingMapRect(forScreenRect rc: OSMRect) -> OSMRect {
		let corners = rc.corners().map { mapPoint(forScreenPoint: $0, birdsEye: true) }
		return Self.boundingRectFor(points: corners)
	}

	// MARK: Miscellaneous

	func zoom() -> Double {
		return transform.zoom()
	}

	func scale() -> Double {
		return transform.scale()
	}

	func rotation() -> Double {
		return transform.rotation()
	}

	/// When fully zoomed out there can be multiple instances of the earth on-screen.
	/// This function relocates the point to be on the "best" one for purposes of
	/// displaying the user location.
	func wrappedScreenPoint(_ pt: CGPoint, screenBounds rc: CGRect) -> CGPoint {
		guard zoom() < 4 else {
			return pt
		}
		var pt = pt
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
		return pt
	}

	func metersPerPixel(atScreenPoint point: CGPoint) -> Double {
		let p1 = point
		let p2 = CGPoint(x: p1.x + 1.0, y: p1.y) // one pixel apart
		let c1 = latLon(forScreenPoint: p1)
		let c2 = latLon(forScreenPoint: p2)
		let meters = GreatCircleDistance(c1, c2)
		return meters
	}

	func distance(from: CGPoint, to: CGPoint) -> Double {
		let c1 = latLon(forScreenPoint: from)
		let c2 = latLon(forScreenPoint: to)
		let meters = GreatCircleDistance(c1, c2)
		return meters
	}

	func screenPoint(on object: OsmBaseObject, forScreenPoint point: CGPoint) -> CGPoint {
		let latLon = latLon(forScreenPoint: point)
		let latLon2 = object.latLonOnObject(forLatLon: latLon)
		let pos = screenPoint(forLatLon: latLon2, birdsEye: true)
		return pos
	}
}
