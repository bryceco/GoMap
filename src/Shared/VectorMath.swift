//
//  VectorMath.swift
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 12/9/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

// On 32-bit systems the CoreGraphics CGFloat (e.g. float not double) doesn't have
// enough precision for a lot of values we work with. Therefore we define our own
// OsmPoint, etc that is explicitely 64-bit double

import CoreLocation
import UIKit

// https://developer.apple.com/library/mac/#samplecode/glut/Listings/gle_vvector_h.html

let TRANSFORM_3D = 0

// MARK: Point

extension CGPoint: @retroactive Hashable {
	public func hash(into hasher: inout Hasher) {
		hasher.combine(x)
		hasher.combine(y)
	}

	static let zero = CGPoint(x: 0.0, y: 0.0)

	@inline(__always) func withOffset(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint {
		return CGPoint(x: x + dx,
		               y: y + dy)
	}

	@inline(__always) func minus(_ b: CGPoint) -> CGPoint {
		return CGPoint(x: x - b.x,
		               y: y - b.y)
	}

	@inline(__always) func plus(_ b: CGPoint) -> CGPoint {
		return CGPoint(x: x + b.x,
		               y: y + b.y)
	}

	@inline(__always) init(_ pt: OSMPoint) {
		self.init(x: pt.x,
		          y: pt.y)
	}
}

@inline(__always) func Dot(_ a: OSMPoint, _ b: OSMPoint) -> Double {
	return a.x * b.x + a.y * b.y
}

@inline(__always) func MagSquared(_ a: OSMPoint) -> Double {
	return a.x * a.x + a.y * a.y
}

@inline(__always) func Mag(_ a: OSMPoint) -> Double {
	return hypot(a.x, a.y)
}

@inline(__always) func Add(_ a: OSMPoint, _ b: OSMPoint) -> OSMPoint {
	return OSMPoint(x: a.x + b.x,
	                y: a.y + b.y)
}

@inline(__always) func Sub(_ a: OSMPoint, _ b: OSMPoint) -> OSMPoint {
	return OSMPoint(x: a.x - b.x,
	                y: a.y - b.y)
}

@inline(__always) func Mult(_ a: OSMPoint, _ c: Double) -> OSMPoint {
	return OSMPoint(x: a.x * c,
	                y: a.y * c)
}

@inline(__always) func CrossMag(_ a: OSMPoint, _ b: OSMPoint) -> Double {
	return a.x * b.y - a.y * b.x
}

func LineSegmentsIntersect(_ p0: OSMPoint, _ p1: OSMPoint, _ p2: OSMPoint, _ p3: OSMPoint) -> Bool {
	let s1 = Sub(p1, p0)
	let s2 = Sub(p3, p2)

	let s: Double = (-s1.y * (p0.x - p2.x) + s1.x * (p0.y - p2.y)) / (-s2.x * s1.y + s1.x * s2.y)
	let t: Double = (s2.x * (p0.y - p2.y) - s2.y * (p0.x - p2.x)) / (-s2.x * s1.y + s1.x * s2.y)

	if s >= 0, s <= 1, t >= 0, t <= 1 {
		return true
	}
	return false
}

func DistanceToVector(_ pos1: OSMPoint, _ dir1: OSMPoint, _ pos2: OSMPoint, _ dir2: OSMPoint) -> Double {
	// returned in terms of units of dir1
	return CrossMag(Sub(pos2, pos1), dir2) / CrossMag(dir1, dir2)
}

func IntersectionOfTwoVectors(_ pos1: OSMPoint, _ dir1: OSMPoint, _ pos2: OSMPoint, _ dir2: OSMPoint) -> OSMPoint {
	let a = CrossMag(Sub(pos2, pos1), dir2) / CrossMag(dir1, dir2)
	let pt = Add(pos1, Mult(dir1, a))
	return pt
}

// MARK: CGRect

extension CGRect {
	@inline(__always) func center() -> CGPoint {
		let c = CGPoint(x: origin.x + size.width / 2,
		                y: origin.y + size.height / 2)
		return c
	}

	@inline(__always) init(_ rc: OSMRect) {
		self.init(x: rc.origin.x,
		          y: rc.origin.y,
		          width: rc.size.width,
		          height: rc.size.height)
	}

	func intersectsLineSegment(_ p1: CGPoint, _ p2: CGPoint) -> Bool {
		let a_rectangleMinX = origin.x
		let a_rectangleMinY = origin.y
		let a_rectangleMaxX = origin.x + size.width
		let a_rectangleMaxY = origin.y + size.height
		let a_p1x = p1.x
		let a_p1y = p1.y
		let a_p2x = p2.x
		let a_p2y = p2.y

		// Find min and max X for the segment
		var minX = a_p1x
		var maxX = a_p2x

		if a_p1x > a_p2x {
			minX = a_p2x
			maxX = a_p1x
		}

		// Find the intersection of the segment's and rectangle's x-projections
		if maxX > a_rectangleMaxX {
			maxX = a_rectangleMaxX
		}
		if minX < a_rectangleMinX {
			minX = a_rectangleMinX
		}
		if minX > maxX {
			// If their projections do not intersect return false
			return false
		}

		// Find corresponding min and max Y for min and max X we found before
		var minY = a_p1y
		var maxY = a_p2y
		let dx = a_p2x - a_p1x
		if abs(dx) > 0.0000001 {
			let a = (a_p2y - a_p1y) / dx
			let b = a_p1y - a * a_p1x
			minY = a * minX + b
			maxY = a * maxX + b
		}

		if minY > maxY {
			let tmp = maxY
			maxY = minY
			minY = tmp
		}

		// Find the intersection of the segment's and rectangle's y-projections
		if maxY > a_rectangleMaxY {
			maxY = a_rectangleMaxY
		}
		if minY < a_rectangleMinY {
			minY = a_rectangleMinY
		}
		if minY > maxY {
			// If Y-projections do not intersect return false
			return false
		}

		return true
	}
}

// MARK: OSMPoint

struct OSMPoint: Equatable, Codable {
	var x: Double
	var y: Double
}

extension OSMPoint {
	static let zero = OSMPoint(x: 0.0, y: 0.0)

	@inline(__always) init(_ pt: CGPoint) {
		self.init(x: Double(pt.x), y: Double(pt.y))
	}

	@inline(__always) init(_ loc: LatLon) {
		self.init(x: loc.lon, y: loc.lat)
	}

	@inline(__always) public static func ==(_ a: OSMPoint, _ b: OSMPoint) -> Bool {
		return a.x == b.x && a.y == b.y
	}

	@inline(__always) func withTransform(_ t: OSMTransform) -> OSMPoint {
#if TRANSFORM_3D
		let zp = 0.0
		var x = t.m11 * pt.x + t.m21 * pt.y + t.m31 * zp + t.m41
		var y = t.m12 * pt.x + t.m22 * pt.y + t.m32 * zp + t.m42
		if false {
			if t.m34 {
				let z = t.m13 * pt.x + t.m23 * pt.y + t.m33 * zp + t.m43
				// use z and m34 to "shrink" objects as they get farther away (perspective)
				// http://en.wikipedia.org/wiki/3D_projection
				let ex = x // eye position
				let ey = y
				let ez: Double = -1 / t.m34
				var p = OSMTransform(1, 0, 0, 0, 0, 1, 0, 0, -ex / ez, -ey / ez, 1, 1 / ez, 0, 0, 0, 0)
				x += -ex / ez
				y += -ey / ez
			}
		}
		return OSMPoint(x, y)
#else
		return OSMPoint(x: self.x * t.a + self.y * t.c + t.tx,
		                y: self.x * t.b + self.y * t.d + t.ty)
#endif
	}

	@inline(__always) func unitVector() -> OSMPoint {
		let d = Mag(self)
		return OSMPoint(x: x / d,
		                y: y / d)
	}

	@inline(__always) func distanceToPoint(_ b: OSMPoint) -> Double {
		return Mag(Sub(self, b))
	}

	public func distanceToLineSegment(_ line1: OSMPoint, _ line2: OSMPoint) -> Double {
		let length2 = MagSquared(Sub(line1, line2))
		if length2 == 0.0 {
			return distanceToPoint(line1)
		}
		let t = Dot(Sub(self, line1), Sub(line2, line1)) / Double(length2)
		if t < 0.0 {
			return distanceToPoint(line1)
		}
		if t > 1.0 {
			return distanceToPoint(line2)
		}

		let projection = Add(line1, Mult(Sub(line2, line1), Double(t)))
		return distanceToPoint(projection)
	}

	func distanceFromLine(_ lineStart: OSMPoint, _ lineDirection: OSMPoint) -> Double {
		// note: lineDirection must be unit vector
		let dir = Sub(lineStart, self)
		let dist = Mag(Sub(dir, Mult(lineDirection, Dot(dir, lineDirection))))
		return dist
	}

	func nearestPointOnLineSegment(lineA: OSMPoint, lineB: OSMPoint) -> OSMPoint {
		let ap = Sub(self, lineA)
		let ab = Sub(lineB, lineA)

		let ab2 = ab.x * ab.x + ab.y * ab.y

		let ap_dot_ab = Dot(ap, ab)
		let t = ap_dot_ab / ab2 // The normalized "distance" from a to point

		if t <= 0 {
			return lineA
		}
		if t >= 1.0 {
			return lineB
		}
		return Add(lineA, Mult(ab, t))
	}
}

extension OSMPoint: CustomStringConvertible {
	var description: String {
		return "OSMPoint(x:\(x),y:\(y))"
	}
}

// MARK: OSMSize

struct OSMSize: Equatable, Codable {
	var width: Double
	var height: Double
}

extension OSMSize {
	static let zero = OSMSize(width: 0.0, height: 0.0)

	@inline(__always) init(_ sz: CGSize) {
		self.init(width: Double(sz.width), height: Double(sz.height))
	}

	@inline(__always) public static func ==(_ a: OSMSize, _ b: OSMSize) -> Bool {
		return a.width == b.width && a.height == b.height
	}
}

extension OSMSize: CustomStringConvertible {
	var description: String {
		return "OSMSize(w:\(width),h:\(height))"
	}
}

// MARK: OSMRect

struct OSMRect: Equatable, Codable {
	var origin: OSMPoint
	var size: OSMSize
}

extension OSMRect {
	static let zero = OSMRect(origin: OSMPoint(x: 0.0, y: 0.0), size: OSMSize(width: 0.0, height: 0.0))

	@inline(__always) init(x: Double, y: Double, width: Double, height: Double) {
		self.init(origin: OSMPoint(x: x, y: y), size: OSMSize(width: width, height: height))
	}

	@inline(__always) init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
		self.init(
			origin: OSMPoint(x: Double(x), y: Double(y)),
			size: OSMSize(width: Double(width), height: Double(height)))
	}

	@inline(__always) init(origin: CGPoint, size: CGSize) {
		self.init(origin: OSMPoint(origin), size: OSMSize(size))
	}

	@inline(__always) init(_ cg: CGRect) {
		self.init(x: cg.origin.x, y: cg.origin.y, width: cg.size.width, height: cg.size.height)
	}

	@inline(__always) func containsPoint(_ pt: OSMPoint) -> Bool {
		return pt.x >= origin.x &&
			pt.x <= origin.x + size.width &&
			pt.y >= origin.y &&
			pt.y <= origin.y + size.height
	}

	@inline(__always) func intersectsRect(_ b: OSMRect) -> Bool {
		if origin.x >= b.origin.x + b.size.width { return false }
		if origin.y >= b.origin.y + b.size.height { return false }
		if origin.x + size.width < b.origin.x { return false }
		if origin.y + size.height < b.origin.y { return false }
		return true
	}

	@inline(__always) func containsRect(_ b: OSMRect) -> Bool {
		return origin.x <= b.origin.x &&
			origin.y <= b.origin.y &&
			origin.x + size.width >= b.origin.x + b.size.width &&
			origin.y + size.height >= b.origin.y + b.size.height
	}

	@inline(__always) func union(_ b: OSMRect) -> OSMRect {
		let minX = Double(min(origin.x, b.origin.x))
		let minY = Double(min(origin.y, b.origin.y))
		let maxX = Double(max(origin.x + size.width, b.origin.x + b.size.width))
		let maxY = Double(max(origin.y + size.height, b.origin.y + b.size.height))
		let r = OSMRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
		return r
	}

	@inline(__always) public static func ==(_ a: OSMRect, _ b: OSMRect) -> Bool {
		return a.origin == b.origin && a.size == b.size
	}

	@inline(__always) func withTransform(_ transform: OSMTransform) -> OSMRect {
		var p1 = origin
		var p2 = OSMPoint(x: origin.x + size.width, y: origin.y + size.height)
		p1 = p1.withTransform(transform)
		p2 = p2.withTransform(transform)
		let r2 = OSMRect(x: p1.x,
		                 y: p1.y,
		                 width: p2.x - p1.x,
		                 height: p2.y - p1.y)
		return r2
	}

	func corners() -> [OSMPoint] {
		return [OSMPoint(x: origin.x, y: origin.y),
		        OSMPoint(x: origin.x + size.width, y: origin.y),
		        OSMPoint(x: origin.x + size.width, y: origin.y + size.height),
		        OSMPoint(x: origin.x, y: origin.y + size.height)]
	}

	@inline(__always) func offsetBy(dx: Double, dy: Double) -> OSMRect {
		var rect = self
		rect.origin.x += dx
		rect.origin.y += dy
		return rect
	}

	func metersSizeForLatLon() -> OSMSize {
		let w = GreatCircleDistance(LatLon(x: origin.x, y: origin.y), LatLon(x: origin.x + size.width, y: origin.y))
		let h = GreatCircleDistance(LatLon(x: origin.x, y: origin.y), LatLon(x: origin.x, y: origin.y + size.height))
		return OSMSize(width: w, height: h)
	}

	var boundsString: String {
		return "OSMRect(ul:(\(origin.x),\(origin.y)),lr:(\(origin.x + size.width),\(origin.y + size.height))"
	}
}

extension OSMRect: CustomStringConvertible {
	var description: String {
		return "OSMRect(x:\(origin.x),y:\(origin.y),w:\(size.width),h:\(size.height)"
	}
}

// MARK: OSMTransform

#if TRANSFORM_3D
typealias OSMTransform = CATransform3D
#else
struct OSMTransform: Equatable {
	//      |  a   b   0  |
	//      |  c   d   0  |
	//      | tx  ty   1  |
	var a, b, c, d: Double
	var tx, ty: Double
}
#endif

extension OSMTransform {
#if TRANSFORM_3D
	static let identity = CATransform3DIdentity
#else
	static let identity = OSMTransform(a: 1.0, b: 0.0, c: 0.0, d: 1.0, tx: 0.0, ty: 0.0)
#endif

	/// Rotation around Z-axis
	@inline(__always) func rotation() -> Double {
#if TRANSFORM_3D
		return atan2(m12, m11)
#else
		return atan2(b, a)
#endif
	}

	// Scaling factor: 1.0 == identity
	@inline(__always) func scale() -> Double {
#if TRANSFORM_3D
		let d = sqrt(m11 * m11 + m12 * m12 + m13 * m13)
		return d
#else
		return hypot(a, c)
#endif
	}

	@inline(__always) func zoom() -> Double {
		let scaleX = scale()
		return log2(scaleX)
	}

	// Inverse transform
	func inverse() -> OSMTransform {
#if TRANSFORM_3D
		return CATransform3DInvert(self)
#else
		//	|  a   b   0  |
		//	|  c   d   0  |
		//	| tx  ty   1  |

		let det = determinant()
		let s = 1.0 / det

		let a = s * self.d
		let c = s * -self.c
		let tx = s * (self.c * self.ty - self.d * self.tx)
		let b = s * -self.b
		let d = s * self.a
		let ty = s * (self.b * self.tx - self.a * self.ty)

		let r = OSMTransform(a: a, b: b, c: c, d: d, tx: tx, ty: ty)
		return r
#endif
	}

	// Return CGFloat equivalent
	@inline(__always) func cgAffineTransform() -> CGAffineTransform {
#if TRANSFORM_3D
		return CATransform3DGetAffineTransform(self)
#else
		let t = CGAffineTransform(
			a: CGFloat(a),
			b: CGFloat(b),
			c: CGFloat(c),
			d: CGFloat(d),
			tx: CGFloat(tx),
			ty: CGFloat(ty))
		return t
#endif
	}

	@inline(__always) static func ==(_ t1: OSMTransform, _ t2: OSMTransform) -> Bool {
		var t1 = t1
		var t2 = t2
		return memcmp(&t1, &t2, MemoryLayout.size(ofValue: t1)) == 0
	}

	/// Returns the unit vector for (1.0,0.0) rotated by the current transform
	@inline(__always) func unitX() -> OSMPoint {
#if TRANSFORM_3D
		let p = UnitVector(OSMPoint(m11, m12))
		return p
#else
		return OSMPoint(x: a, y: b).unitVector()
#endif
	}

	@inline(__always) func translation() -> OSMPoint {
#if TRANSFORM_3D
		let p = OSMPoint(m41, m42)
		return p
#else
		return OSMPoint(x: tx, y: ty)
#endif
	}

	@inline(__always) func scaledBy(_ scale: Double) -> OSMTransform {
#if TRANSFORM_3D
		return CATransform3DScale(self, CGFloat(scale), CGFloat(scale), CGFloat(scale))
#else
		var t = self
		t.a *= scale
		t.b *= scale
		t.c *= scale
		t.d *= scale
		return t
#endif
	}

	@inline(__always) func translatedBy(dx: Double, dy: Double) -> OSMTransform {
#if TRANSFORM_3D
		return CATransform3DTranslate(self, CGFloat(dx), CGFloat(dy), 0)
#else
		var t = self
		t.tx += t.a * dx + t.c * dy
		t.ty += t.b * dx + t.d * dy
		return t
#endif
	}

	@inline(__always) func scaledBy(scaleX: Double, scaleY: Double) -> OSMTransform {
#if TRANSFORM_3D
		return CATransform3DScale(self, CGFloat(scale), CGFloat(scaleY), 1.0)
#else
		var t = self
		t.a *= scaleX
		t.b *= scaleY
		t.c *= scaleX
		t.d *= scaleY
		return t
#endif
	}

	@inline(__always) func rotatedBy(_ angle: Double) -> OSMTransform {
#if TRANSFORM_3D
		return CATransform3DRotate(self, CGFloat(angle), 0, 0, 1)
#else
		let s = sin(angle)
		let c = cos(angle)
		let t = OSMTransform(a: c, b: s, c: -s, d: c, tx: 0.0, ty: 0.0)
		return t.concat(self)
#endif
	}

	@inline(__always) static func translation(_ dx: Double, _ dy: Double) -> OSMTransform {
#if TRANSFORM_3D
		return CATransform3DMakeTranslation(CGFloat(dx), CGFloat(dy), 0)
#else
		let t = OSMTransform(a: 1, b: 0, c: 0, d: 1, tx: dx, ty: dy)
		return t
#endif
	}

	@inline(__always) func concat(_ b: OSMTransform) -> OSMTransform {
#if TRANSFORM_3D
		return CATransform3DConcat(self, b)
#else
		//	|  a   b   0  |
		//	|  c   d   0  |
		//	| tx  ty   1  |
		let a = self
		let t = OSMTransform(
			a: a.a * b.a + a.b * b.c,
			b: a.a * b.b + a.b * b.d,
			c: a.c * b.a + a.d * b.c,
			d: a.c * b.b + a.d * b.d,
			tx: a.tx * b.a + a.ty * b.c + b.tx,
			ty: a.tx * b.b + a.ty * b.d + b.ty)
		return t
#endif
	}

	func determinant() -> Double {
		return a * d - b * c
	}
}

struct LatLon: Equatable, Codable {
	var lon: Double
	var lat: Double

	static let zero = LatLon(lon: 0.0, lat: 0.0)

	init(lon: Double, lat: Double) {
		self.lon = lon
		self.lat = lat
	}

	init(x: Double, y: Double) {
		lon = x
		lat = y
	}

	init(latitude: Double, longitude: Double) {
		lon = longitude
		lat = latitude
	}

	init(_ loc: CLLocationCoordinate2D) {
		lon = loc.longitude
		lat = loc.latitude
	}

	init(_ pt: OSMPoint) {
		self.init(lon: pt.x, lat: pt.y)
	}

	@inline(__always) public static func ==(_ a: LatLon, _ b: LatLon) -> Bool {
		return a.lon == b.lon && a.lat == b.lat
	}
}

// MARK: miscellaneous

/// Radius in meters
let EarthRadius = 6_378137.0

@inline(__always) func radiansFromDegrees(_ degrees: Double) -> Double {
	return degrees * (.pi / 180)
}

func MetersPerDegreeAt(latitude: Double) -> OSMPoint {
	let latitude = latitude * .pi / 180
	let lat = 111132.954 - 559.822 * cos(2 * latitude) + 1.175 * cos(4 * latitude)
	let lon = 111132.954 * cos(latitude)
	return OSMPoint(x: lon, y: lat)
}

// convert a distance in meters to degrees
// different than the previous function, we should probably pick one or the other :)
func metersToDegrees(meters: Double, latitude: Double) -> Double {
	let metersPerDegreeAtEquator = 111321.0 // meters
	let scalingFactor = cos(latitude * .pi / 180.0)
	let degrees = meters / (metersPerDegreeAtEquator * scalingFactor)
	return degrees
}

// area in square meters
func SurfaceAreaOfRect(_ latLon: OSMRect) -> Double {
	// http://mathforum.org/library/drmath/view/63767.html
	let lon1 = latLon.origin.x * .pi / 180.0
	let lat1 = latLon.origin.y * .pi / 180.0
	let lon2: Double = (latLon.origin.x + latLon.size.width) * .pi / 180.0
	let lat2: Double = (latLon.origin.y + latLon.size.height) * .pi / 180.0
	let A = EarthRadius * EarthRadius * abs(sin(lat1) - sin(lat2)) * abs(lon1 - lon2)
	return A
}

// http://www.movable-type.co.uk/scripts/latlong.html
/// Distance between two lon,lat  points in degrees, result in meters
func GreatCircleDistance(_ p1: LatLon, _ p2: LatLon) -> Double {
	// haversine formula
	let dlon = (p2.lon - p1.lon) * .pi / 180
	let dlat = (p2.lat - p1.lat) * .pi / 180
	let a: Double = pow(sin(dlat / 2), 2) + cos(p1.lat * .pi / 180) * cos(p2.lat * .pi / 180) * pow(sin(dlon / 2), 2)
	let c: Double = 2 * atan2(sqrt(a), sqrt(1 - a))
	let meters = EarthRadius * c
	return meters
}

// area of a closed polygon (first and last points repeat), and boolean if it's clockwise
func AreaOfPolygonClockwise(_ points: [CGPoint]) -> (area: Double, clockwise: Bool)? {
	if points.count < 4 {
		return nil // not a polygon
	}
	if points[0] != points.last! {
		return nil // first and last aren't identical
	}
	// we skip the last/first wrap-around, but last is a duplicate of first so the algorithm still works correctly
	var area = 0.0
	var previous = points[0]
	for point in points.dropFirst() {
		area += (previous.x + point.x) * (previous.y - point.y)
		previous = point
	}
	area *= 0.5
	return area < 0 ? (-area, true) : (area, false)
}

func IsClockwisePolygon(_ points: [CGPoint]) -> Bool? {
	return AreaOfPolygonClockwise(points)?.clockwise
}

// Input is a list of points in degrees, with the first and last points being equal
func AreaInSquareMeters(points: [LatLon]) -> Double {
	guard points.count > 3, points[0] == points.last! else { return 0.0 }
	// convert to radians
	let radians = points.map { LatLon(lon: $0.lon * (.pi / 180),
	                                  lat: $0.lat * (.pi / 180)) }
	var area = 0.0
	var p1 = radians[0]
	for p2 in radians[1..<radians.count] {
		let delta = (p2.lon - p1.lon) * (2 + sin(p1.lat) + sin(p2.lat))
		area += delta
		p1 = p2
	}
	area = area * EarthRadius * EarthRadius / 2
	return abs(area)
}
