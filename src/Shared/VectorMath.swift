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


import UIKit
import CoreLocation

// https://developer.apple.com/library/mac/#samplecode/glut/Listings/gle_vvector_h.html

let TRANSFORM_3D = 0

#if false
struct OSMPoint {
    var x: Double
    var y: Double
}

struct OSMSize {
    var width: Double
    var height: Double
}

struct OSMRect {
    var origin: OSMPoint
    var size: OSMSize
}

#if TRANSFORM_3D
typealias OSMTransform = CATransform3D
#else
struct OSMTransform {
    //	|  a   b   0  |
    //	|  c   d   0  |
    //	| tx  ty   1  |
    var a: Double
    var b: Double
    var c: Double
    var d: Double
    var tx: Double
    var ty: Double
}
#endif
#endif

// MARK: Point
extension CGPoint {
	static let zero = CGPoint(x: 0.0, y: 0.0)

	@inline(__always) func withOffset(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint {
		return CGPoint(x: self.x + dx,
					   y: self.y + dy)
	}
	@inline(__always) func minus(_ b: CGPoint) -> CGPoint {
		return CGPoint(x: self.x - b.x,
					   y: self.y - b.y)
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

    if s >= 0 && s <= 1 && t >= 0 && t <= 1 {
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
		let c = CGPoint(x: self.origin.x + self.size.width / 2,
						y: self.origin.y + self.size.height / 2)
		return c
	}

	@inline(__always) init(_ rc: OSMRect) {
		self.init(x: rc.origin.x,
				  y: rc.origin.y,
				  width: rc.size.width,
				  height: rc.size.height)
	}
}

// MARK: OSMPoint
struct OSMPoint: Codable {
	var x: Double
	var y: Double
}

extension OSMPoint {
	static let zero = OSMPoint(x: 0.0, y: 0.0)

	@inline(__always) init(_ pt: CGPoint) {
		self.init(x: Double(pt.x), y: Double(pt.y))
	}
	@inline(__always) init(_ loc: LatLon) {
		self.init( x: loc.longitude, y: loc.latitude )
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
		return OSMPoint( x: self.x * t.a + self.y * t.c + t.tx,
						 y: self.x * t.b + self.y * t.d + t.ty )
		#endif
	}

	@inline(__always) func unitVector() -> OSMPoint {
		let d = Mag(self)
		return OSMPoint(x: self.x / d,
						y: self.y / d)
	}

	@inline(__always) func distanceToPoint(_ b: OSMPoint) -> Double {
		return Mag(Sub(self, b))
	}

	public func distanceToLineSegment(_ line1: OSMPoint, _ line2: OSMPoint) -> Double {
		let length2 = MagSquared(Sub(line1, line2))
		if length2 == 0.0 {
			return self.distanceToPoint( line1 )
		}
		let t = Dot(Sub(self, line1), Sub(line2, line1)) / Double(length2)
		if t < 0.0 {
			return self.distanceToPoint( line1 )
		}
		if t > 1.0 {
			return self.distanceToPoint( line2 )
		}

		let projection = Add(line1, Mult(Sub(line2, line1), Double(t)))
		return self.distanceToPoint( projection )
	}

	func distanceFromLine(_ lineStart: OSMPoint, _ lineDirection: OSMPoint) -> Double {
		// note: lineDirection must be unit vector
		let dir = Sub(lineStart, self)
		let dist = Mag(Sub(dir, Mult(lineDirection, Dot(dir, lineDirection))))
		return dist
	}

	func nearestPointOnLineSegment( lineA: OSMPoint, lineB: OSMPoint) -> OSMPoint {
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

// MARK: OSMSize

struct OSMSize: Codable {
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

// MARK: OSMRect

struct OSMRect: Codable {
	var origin: OSMPoint
	var size: OSMSize
}

extension OSMRect {
	static let zero = OSMRect(origin: OSMPoint(x: 0.0, y: 0.0), size: OSMSize(width: 0.0, height: 0.0))

	@inline(__always) init(x: Double, y: Double, width: Double, height: Double) {
		self.init(origin: OSMPoint(x: x, y: y), size: OSMSize(width: width, height: height))
	}
	@inline(__always) init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
		self.init(origin: OSMPoint(x: Double(x), y: Double(y)), size: OSMSize(width: Double(width), height: Double(height)))
	}
	@inline(__always) init(origin: CGPoint, size: CGSize) {
		self.init(origin: OSMPoint(origin), size: OSMSize(size))
	}
	@inline(__always) init(_ cg: CGRect) {
		self.init(x: cg.origin.x, y: cg.origin.y, width: cg.size.width, height: cg.size.height)
	}
	@inline(__always) func containsPoint(_ pt: OSMPoint) -> Bool {
		return pt.x >= self.origin.x &&
			pt.x <= self.origin.x + self.size.width &&
			pt.y >= self.origin.y &&
			pt.y <= self.origin.y + self.size.height
	}
	@inline(__always) func intersectsRect(_ b: OSMRect) -> Bool {
		if self.origin.x >= b.origin.x + b.size.width {		return false	}
		if self.origin.x + self.size.width < b.origin.x {	return false	}
		if self.origin.y >= b.origin.y + b.size.height {	return false	}
		if self.origin.y + self.size.height < b.origin.y {	return false	}
		return true
	}

	@inline(__always) func containsRect( b: OSMRect ) -> Bool {
		return	self.origin.x <= b.origin.x &&
				self.origin.y <= b.origin.y &&
				self.origin.x + self.size.width >= b.origin.x + b.size.width &&
				self.origin.y + self.size.height >= b.origin.y + b.size.height
	}

	@inline(__always) func union(_ b: OSMRect) -> OSMRect {
		let minX = Double(min(self.origin.x, b.origin.x))
		let minY = Double(min(self.origin.y, b.origin.y))
		let maxX = Double(max(self.origin.x + self.size.width, b.origin.x + b.size.width))
		let maxY = Double(max(self.origin.y + self.size.height, b.origin.y + b.size.height))
		let r = OSMRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
		return r
	}

	@inline(__always) func containsRect(_ b: OSMRect) -> Bool {
		return self.origin.x <= b.origin.x &&
			self.origin.y <= b.origin.y &&
			self.origin.x + self.size.width >= b.origin.x + b.size.width &&
			self.origin.y + self.size.height >= b.origin.y + b.size.height
	}
	@inline(__always) public static func ==(_ a: OSMRect, _ b: OSMRect) -> Bool {
		return a.origin == b.origin && a.size == b.size
	}

	@inline(__always) func withTransform(_ transform: OSMTransform) -> OSMRect {
		var p1 = origin
		var p2 = OSMPoint(x: origin.x + size.width, y: origin.y + size.height)
		p1 = p1.withTransform( transform )
		p2 = p2.withTransform( transform )
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

	@inline(__always) func offsetBy( dx: Double, dy: Double) -> OSMRect {
		var rect = self
		rect.origin.x += dx
		rect.origin.y += dy
		return rect
	}


	func intersectsLineSegment(_ p1: OSMPoint, _ p2: OSMPoint) -> Bool {
		let a_rectangleMinX = self.origin.x
		let a_rectangleMinY = self.origin.y
		let a_rectangleMaxX = self.origin.x + self.size.width
		let a_rectangleMaxY = self.origin.y + self.size.height
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

// MARK: OSMTransform

#if TRANSFORM_3D
typealias OSMTransform = CATransform3D
#else
struct OSMTransform {
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
		return atan2(self.m12, self.m11)
		#else
		return atan2(self.b, self.a)
		#endif
	}

	// Scaling factor: 1.0 == identity
	@inline(__always) func scale() -> Double {
		#if TRANSFORM_3D
		let d = sqrt(self.m11 * self.m11 + self.m12 * self.m12 + self.m13 * self.m13)
		return d
		#else
		return hypot(self.a, self.c)
		#endif
	}

	@inline(__always) func zoom() -> Double {
		let scaleX = self.scale()
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

		let det = self.determinant()
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
					 a: CGFloat(self.a),
					 b: CGFloat(self.b),
					 c: CGFloat(self.c),
					 d: CGFloat(self.d),
					 tx: CGFloat(self.tx),
					 ty: CGFloat(self.ty))
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
		let p = UnitVector(OSMPoint(self.m11, self.m12))
		return p
		#else
		return OSMPoint(x: self.a, y: self.b).unitVector()
		#endif
	}

	@inline(__always) func translation() -> OSMPoint {
		#if TRANSFORM_3D
		let p = OSMPoint(self.m41, self.m42)
		return p
		#else
		return OSMPoint(x: self.tx, y: self.ty)
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

	@inline(__always) func translatedBy( dx: Double, dy: Double) -> OSMTransform {
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
		return t.concat( self )
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
		return self.a * self.d - self.b * self.c
	}
}

struct LatLon {
	var longitude: Double
	var latitude: Double

	static let zero = LatLon(lon: 0.0, lat: 0.0)

	init( lon: Double, lat: Double ) {
		self.longitude = lon
		self.latitude = lat
	}
	init( x: Double, y: Double ) {
		self.longitude = x
		self.latitude = y
	}
	init( latitude: Double, longitude: Double ) {
		self.longitude = longitude
		self.latitude = latitude
	}

	init( _ loc: CLLocationCoordinate2D ) {
		self.longitude = loc.longitude
		self.latitude = loc.latitude
	}

	init(_ pt: OSMPoint) {
		self.init(lon: pt.x, lat: pt.y)
	}
}


// MARK: miscellaneous

/// Radius in meters
let EarthRadius: Double = 6378137.0

@inline(__always) func radiansFromDegrees(_ degrees: Double) -> Double {
    return degrees * (.pi / 180)
}

func MetersPerDegreeAt(latitude: Double) -> OSMPoint {
	let latitude = latitude * .pi / 180
	let lat = 111132.954 - 559.822 * cos(2 * latitude) + 1.175 * cos(4 * latitude)
	let lon = 111132.954 * cos(latitude)
	return OSMPoint( x: lon, y: lat)
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
	let dlon = (p2.longitude - p1.longitude) * .pi / 180
	let dlat = (p2.latitude - p1.latitude) * .pi / 180
	let a: Double = pow(sin(dlat / 2), 2) + cos(p1.latitude * .pi / 180) * cos(p2.latitude * .pi / 180) * pow(sin(dlon / 2), 2)
	let c: Double = 2 * atan2(sqrt(a), sqrt(1 - a))
	let meters = EarthRadius * c
	return meters
}
