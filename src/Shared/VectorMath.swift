//
//  VectorMath.swift
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 12/9/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

import UIKit

// https://developer.apple.com/library/mac/#samplecode/glut/Listings/gle_vvector_h.html

let TRANSFORM_3D = 0

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

if TRANSFORM_3D {
typealias OSMTransform = CATransform3D
} else {
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

// MARK: Point
@inline(__always) func CGPointWithOffset(_ pt: CGPoint, _ dx: CGFloat, _ dy: CGFloat) -> CGPoint {
    return CGPoint(x: pt.x + dx, y: pt.y + dy)
}

@inline(__always) func CGPointSubtract(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
    let pt = CGPoint(x: Double(a.x - b.x), y: Double(a.y - b.y))
    return pt
}

@inline(__always) func OSMPointMake(_ x: Double, _ y: Double) -> OSMPoint {
    let pt = OSMPoint(x, y)
    return pt
}

@inline(__always) func OSMPointFromCGPoint(_ pt: CGPoint) -> OSMPoint {
    let point = OSMPoint(pt.x, pt.y)
    return point
}

@inline(__always) func CGPointFromOSMPoint(_ pt: OSMPoint) -> CGPoint {
    let p = CGPoint(x: Double(CGFloat(pt.x)), y: Double(CGFloat(pt.y)))
    return p
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
    return OSMPointMake(a.x + b.x, a.y + b.y)
}

@inline(__always) func Sub(_ a: OSMPoint, _ b: OSMPoint) -> OSMPoint {
    return OSMPointMake(a.x - b.x, a.y - b.y)
}

@inline(__always) func Mult(_ a: OSMPoint, _ c: Double) -> OSMPoint {
    return OSMPointMake(a.x * c, a.y * c)
}

@inline(__always) func UnitVector(_ a: OSMPoint) -> OSMPoint {
    let d = Mag(a)
    return OSMPointMake(a.x / d, a.y / d)
}

@inline(__always) func CrossMag(_ a: OSMPoint, _ b: OSMPoint) -> Double {
    return a.x * b.y - a.y * b.x
}

@inline(__always) func DistanceFromPointToPoint(_ a: OSMPoint, _ b: OSMPoint) -> Double {
    return Mag(Sub(a, b))
}

@inline(__always) func OffsetPoint(_ p: OSMPoint, _ dx: Double, _ dy: Double) -> OSMPoint {
    let p2 = OSMPoint(p.x + dx, p.y + dy)
    return p2
}

func ClosestPointOnLineToPoint(_ a: OSMPoint, _ b: OSMPoint, _ p: OSMPoint) -> OSMPoint {
    let ap = Sub(p, a)
    let ab = Sub(b, a)

    let ab2: Double = ab.x * ab.x + ab.y * ab.y

    let ap_dot_ab = Dot(ap, ab)
    let t = ap_dot_ab / ab2 // The normalized "distance" from a to point

    if t <= 0 {
        return a
    }
    if t >= 1.0 {
        return b
    }
    return Add(a, Mult(ab, t))
}

func DistanceFromPointToLineSegment(_ point: OSMPoint, _ line1: OSMPoint, _ line2: OSMPoint) -> CGFloat {
    let length2 = CGFloat(MagSquared(Sub(line1, line2)))
    if length2 == 0.0 {
        return CGFloat(DistanceFromPointToPoint(point, line1))
    }
    let t = CGFloat(Dot(Sub(point, line1), Sub(line2, line1)) / Double(length2))
    if t < 0.0 {
        return CGFloat(DistanceFromPointToPoint(point, line1))
    }
    if t > 1.0 {
        return CGFloat(DistanceFromPointToPoint(point, line2))
    }

    let projection = Add(line1, Mult(Sub(line2, line1), Double(t)))
    return CGFloat(DistanceFromPointToPoint(point, projection))
}

func DistanceFromLineToPoint(_ lineStart: OSMPoint, _ lineDirection: OSMPoint, _ point: OSMPoint) -> CGFloat {
    // note: lineDirection must be unit vector
    let dir = Sub(lineStart, point)
    let dist = CGFloat(Mag(Sub(dir, Mult(lineDirection, Dot(dir, lineDirection)))))
    return dist
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

func LineSegmentIntersectsRectangle(_ p1: OSMPoint, _ p2: OSMPoint, _ rect: OSMRect) -> Bool {
    let a_rectangleMinX = rect.origin.x
    let a_rectangleMinY = rect.origin.y
    let a_rectangleMaxX: Double = rect.origin.x + rect.size.width
    let a_rectangleMaxY: Double = rect.origin.y + rect.size.height
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
    if abs(Float(dx)) > 0.0000001 {
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

// MARK: Rect
@inline(__always) func CGRectCenter(_ rc: CGRect) -> CGPoint {
    let c = CGPoint(x: Double(rc.origin.x + rc.size.width / 2), y: Double(rc.origin.y + rc.size.height / 2))
    return c
}

@inline(__always) func CGRectFromOSMRect(_ rc: OSMRect) -> CGRect {
    let r = CGRect(x: Double(CGFloat(rc.origin.x)), y: Double(CGFloat(rc.origin.y)), width: Double(CGFloat(rc.size.width)), height: Double(CGFloat(rc.size.height)))
    return r
}

@inline(__always) func OSMRectZero() -> OSMRect {
    let rc = OSMRect(0)
    return rc
}

@inline(__always) func OSMRectOffset(_ rect: OSMRect, _ dx: Double, _ dy: Double) -> OSMRect {
    rect.origin.x += dx
    rect.origin.y += dy
    return rect
}

@inline(__always) func OSMRectFromCGRect(_ cg: CGRect) -> OSMRect {
    let rc = OSMRect(cg.origin.x, cg.origin.y, cg.size.width, cg.size.height)
    return rc
}

@inline(__always) func OSMRectContainsPoint(_ rc: OSMRect, _ pt: OSMPoint) -> Bool {
    return pt.x >= rc.origin.x && pt.x <= rc.origin.x + rc.size.width && pt.y >= rc.origin.y && pt.y <= rc.origin.y + rc.size.height
}

@inline(__always) func OSMRectIntersectsRect(_ a: OSMRect, _ b: OSMRect) -> Bool {
    if a.origin.x >= b.origin.x + b.size.width {
        return false
    }
    if a.origin.x + a.size.width < b.origin.x {
        return false
    }
    if a.origin.y >= b.origin.y + b.size.height {
        return false
    }
    if a.origin.y + a.size.height < b.origin.y {
        return false
    }
    return true
}

@inline(__always) func OSMRectUnion(_ a: OSMRect, _ b: OSMRect) -> OSMRect {
    let minX = Double(min(a.origin.x, b.origin.x))
    let minY = Double(min(a.origin.y, b.origin.y))
    let maxX = Double(max(a.origin.x + a.size.width, b.origin.x + b.size.width))
    let maxY = Double(max(a.origin.y + a.size.height, b.origin.y + b.size.height))
    let r = OSMRect(minX, minY, maxX - minX, maxY - minY)
    return r
}

@inline(__always) func OSMRectContainsRect(_ a: OSMRect, _ b: OSMRect) -> Bool {
    return a.origin.x <= b.origin.x && a.origin.y <= b.origin.y && a.origin.x + a.size.width >= b.origin.x + b.size.width && a.origin.y + a.size.height >= b.origin.y + b.size.height
}

// MARK: Transform
func OSMTransformInvert(_ t: OSMTransform) -> OSMTransform {
    if TRANSFORM_3D {
		return CATransform3DInvert(t)
    } else {
		//	|  a   b   0  |
		//	|  c   d   0  |
		//	| tx  ty   1  |

		let det = Determinant(t)
		let s = 1.0 / det
		let a: OSMTransform

		a.a = s * t.d
		a.c = s * -t.c
		a.tx = s * (t.c * t.ty - t.d * t.tx)
		a.b = s * -t.b
		a.d = s * t.a
		a.ty = s * (t.b * t.tx - t.a * t.ty)

		return a
    }
}

func FromBirdsEye(_ point: OSMPoint, _ center: CGPoint, _ birdsEyeDistance: Double, _ birdsEyeRotation: Double) -> OSMPoint {
    var point = point
    let D = birdsEyeDistance // distance from eye to center of screen
    let r = birdsEyeRotation

    point.x -= center.x
    point.y -= center.y

    point.y *= D / (D * cos(r) + point.y * sin(r))
    point.x -= point.x * point.y * sin(r) / D

    point.x += center.x
    point.y += center.y
    return point
}

func ToBirdsEye(_ point: OSMPoint, _ center: CGPoint, _ birdsEyeDistance: Double, _ birdsEyeRotation: Double) -> OSMPoint {
    var point = point
    // narrow things toward top of screen
    let D = birdsEyeDistance // distance from eye to center of screen
    point.x -= center.x
    point.y -= center.y

    let z: Double = point.y * -sin(birdsEyeRotation) // rotation around x axis gives a z value from y offset
    var scale = D / (D + z)
    if scale < 0 {
        scale = 1.0 / 0.0
    }
    point.x *= scale
    point.y *= scale * cos(birdsEyeRotation)

    point.x += center.x
    point.y += center.y
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

    var loc: OSMPoint
    loc.y = 90 - 360 * atan(exp(y * 2 * .pi)) / .pi
    loc.x = 360 * x
    return loc
}

@inline(__always) func MapPointForLatitudeLongitude(_ latitude: Double, _ longitude: Double) -> OSMPoint {
    let x = (longitude + 180) / 360
    let sinLatitude = sin(latitude * .pi / 180)
    let y = 0.5 - log((1 + sinLatitude) / (1 - sinLatitude)) / (4 * .pi)
    let point = OSMPoint(x * 256, y * 256)
    return point
}

@inline(__always) func CGAffineTransformFromOSMTransform(_ transform: OSMTransform) -> CGAffineTransform {
    if TRANSFORM_3D {
    return CATransform3DGetAffineTransform(transform)
    } else {
    let t: CGAffineTransform
    t.a = transform.a
    t.b = transform.b
    t.c = transform.c
    t.d = transform.d
    t.tx = transform.tx
    t.ty = transform.ty
    return t
    }
}

@inline(__always) func OSMTransformIdentity() -> OSMTransform {
    if TRANSFORM_3D {
    return CATransform3DIdentity
    } else {
    let transform = OSMTransform(0)
    transform.d = 1.0
    transform.a = transform.d
    return transform
    }
}

@inline(__always) func OSMTransformEqual(_ t1: OSMTransform, _ t2: OSMTransform) -> Bool {
    var t1 = t1
    var t2 = t2
    return memcmp(&t1, &t2, MemoryLayout.size(ofValue: t1)) == 0
}

@inline(__always) func OSMTransformScaleX(_ t: OSMTransform) -> Double {
    if TRANSFORM_3D {
    let d = sqrt(t.m11 * t.m11 + t.m12 * t.m12 + t.m13 * t.m13)
    return d
    } else {
    return hypot(t.a, t.c)
    }
}

@inline(__always) func OSMTransformConcat(_ a: OSMTransform, _ b: OSMTransform) -> OSMTransform {
    if TRANSFORM_3D {
    return CATransform3DConcat(a, b)
    } else {
    //	|  a   b   0  |
    //	|  c   d   0  |
    //	| tx  ty   1  |
    let c: OSMTransform
    c.a = a.a * b.a + a.b * b.c
    c.b = a.a * b.b + a.b * b.d
    c.c = a.c * b.a + a.d * b.c
    c.d = a.c * b.b + a.d * b.d
    c.tx = a.tx * b.a + a.ty * b.c + b.tx
    c.ty = a.tx * b.b + a.ty * b.d + b.ty
    return c
    }
}

@inline(__always) func OSMTransformRotation(_ t: OSMTransform) -> Double {
    if TRANSFORM_3D {
    return atan2(t.m12, t.m11)
    } else {
    return atan2(t.b, t.a)
    }
}

@inline(__always) func OSMTransformMakeTranslation(_ dx: Double, _ dy: Double) -> OSMTransform {
    if TRANSFORM_3D {
    return CATransform3DMakeTranslation(CGFloat(dx), CGFloat(dy), 0)
    } else {
    let t = OSMTransform(1, 0, 0, 1, dx, dy)
    return t
    }
}

@inline(__always) func OSMTransformTranslate(_ t: OSMTransform, _ dx: Double, _ dy: Double) -> OSMTransform {
    if TRANSFORM_3D {
    return CATransform3DTranslate(t, CGFloat(dx), CGFloat(dy), 0)
    } else {
    t.tx += t.a * dx + t.c * dy
    t.ty += t.b * dx + t.d * dy
    return t
    }
}

@inline(__always) func OSMTransformScale(_ t: OSMTransform, _ scale: Double) -> OSMTransform {
    if TRANSFORM_3D {
    return CATransform3DScale(t, CGFloat(scale), CGFloat(scale), CGFloat(scale))
    } else {
    t.a *= scale
    t.b *= scale
    t.c *= scale
    t.d *= scale
    return t
    }
}

@inline(__always) func OSMTransformScaleXY(_ t: OSMTransform, _ scaleX: Double, _ scaleY: Double) -> OSMTransform {
    if TRANSFORM_3D {
    return CATransform3DScale(t, CGFloat(scaleX), CGFloat(scaleY), 1.0)
    } else {
    t.a *= scaleX
    t.b *= scaleY
    t.c *= scaleX
    t.d *= scaleY
    return t
    }
}

@inline(__always) func OSMTransformRotate(_ transform: OSMTransform, _ angle: Double) -> OSMTransform {
    if TRANSFORM_3D {
    return CATransform3DRotate(transform, CGFloat(angle), 0, 0, 1)
    } else {
    let s = sin(angle)
    let c = cos(angle)
    let t = OSMTransform(c, s, -s, c, 0, 0)
    return OSMTransformConcat(t, transform)
    }
}

@inline(__always) func OSMPointApplyTransform(_ pt: OSMPoint, _ t: OSMTransform) -> OSMPoint {
    if TRANSFORM_3D {
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
    return OSMPointMake(x, y)
    } else {
    var p: OSMPoint
    p.x = pt.x * t.a + pt.y * t.c + t.tx
    p.y = pt.x * t.b + pt.y * t.d + t.ty
    return p
    }
}

@inline(__always) func OSMRectApplyTransform(_ rc: OSMRect, _ transform: OSMTransform) -> OSMRect {
    let p1 = OSMPointApplyTransform(rc.origin, transform)
    let p2 = OSMPointApplyTransform(OSMPointMake(rc.origin.x + rc.size.width, rc.origin.y + rc.size.height), transform)
    let r2 = OSMRect(p1.x, p1.y, p2.x - p1.x, p2.y - p1.y)
    return r2
}

@inline(__always) func UnitX(_ t: OSMTransform) -> OSMPoint {
    if TRANSFORM_3D {
    let p = UnitVector(OSMPointMake(t.m11, t.m12))
    return p
    } else {
    return UnitVector(OSMPointMake(t.a, t.b))
    }
}

@inline(__always) func Translation(_ t: OSMTransform) -> OSMPoint {
    if TRANSFORM_3D {
    let p = OSMPointMake(t.m41, t.m42)
    return p
    } else {
    return OSMPointMake(t.tx, t.ty)
    }
}

@inline(__always) func latp2lat(_ a: Double) -> Double {
    return 180 / .pi * (2 * atan(exp(a * .pi / 180)) - .pi / 2)
}

@inline(__always) func lat2latp(_ a: Double) -> Double {
    return 180 / .pi * log(tan(.pi / 4 + a * (.pi / 180) / 2))
}

// MARK: miscellaneous
@inline(__always) func radiansFromDegrees(_ degrees: Double) -> Double {
    return degrees * (.pi / 180)
}

func Determinant(_ t: OSMTransform) -> Double {
    return t.a * t.d - t.b * t.c
}

// area in square meters
func SurfaceArea(_ latLon: OSMRect) -> Double {
	// http://mathforum.org/library/drmath/view/63767.html
	let SurfaceAreaEarthRadius: Double = 6378137
	let lon1 = latLon.origin.x
	let lat1 = latLon.origin.y
	let lon2: Double = latLon.origin.x + latLon.size.width
	let lat2: Double = latLon.origin.y + latLon.size.height
	let A = .pi * SurfaceAreaEarthRadius * SurfaceAreaEarthRadius * Double(abs(sin(lat1 * (.pi / 180)) - sin(lat2 * (.pi / 180)))) * Double(abs(Float(lon1 - lon2))) / 180
	return A
}

// http://www.movable-type.co.uk/scripts/latlong.html
func GreatCircleDistance(_ p1: OSMPoint, _ p2: OSMPoint) -> Double {
	let earthRadius = 6378137.0 // meters
	// haversine formula
	let dlon = (p2.x - p1.x) * .pi / 180
	let dlat = (p2.y - p1.y) * .pi / 180
	let a: Double = pow(sin(dlat / 2), 2) + cos(p1.y * .pi / 180) * cos(p2.y * .pi / 180) * pow(sin(dlon / 2), 2)
	let c: Double = 2 * atan2(sqrt(a), sqrt(1 - a))
	let meters = earthRadius * c
	return meters
}
