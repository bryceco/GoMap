//
//  PathUtil.swift
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 1/24/13.
//  Copyright (c) 2013 Bryce Cogswell. All rights reserved.
//

//#define OpenStreetMap_PathUtil_h
public typealias ApplyPathCallback = (CGPathElementType, CGPoint) -> Void

extension CGPath {
	func apply(action: (CGPathElement)->Void) {
		var action = action
		apply(info: &action, function: { (type,element) in
			let block = type!.bindMemory(to: ((CGPathElement)->()).self, capacity: 1).pointee
			block( element.pointee )
		})
	}
}

func CGPathPointCount(_ path: CGPath) -> Int {
    var count = 0
	path.apply(action: { _ in count += 1 })
    return count
}

func CGPathGetPoints(_ path: CGPath ) -> [CGPoint] {
	let count = CGPathPointCount( path )
	var list = [CGPoint]()
	list.reserveCapacity(count)
	path.apply(action: { element in
		switch element.type {
			case .moveToPoint, .addLineToPoint:
				list.append( element.points[0] )
			case .closeSubpath:
				list.append( list[0] )
			default:
				break
		}
	})
	return list
}

func CGPathDump(_ path: CGPath) {
	path.apply(action: { element in
		let point = element.points[0]
        print("\(point.x),\(point.y)")
    })
}

func InvokeBlockAlongPath(_ path: CGPath, _ initialOffset: Double, _ interval: Double, _ callback: (_ pt: CGPoint, _ direction: CGPoint) -> Void) {
    var offset = initialOffset
    var previous = CGPoint()

	path.apply(action: { element in
		switch element.type {
            case .moveToPoint:
				previous = element.points[0]
            case .addLineToPoint:
                let nextPt = element.points[0]
                var dx = Double((nextPt.x) - previous.x)
                var dy = Double((nextPt.y) - previous.y)
                let len = sqrt(dx * dx + dy * dy)
                dx /= len
                dy /= len

                while offset < len {
                    // found it
                    let pos = CGPoint(x: Double(previous.x) + Double(offset) * dx, y: Double(previous.y) + Double(offset) * dy)
                    let dir = CGPoint(x: dx, y: dy)
                    callback(pos, dir)
                    offset += interval
                }
                offset -= len
                previous = nextPt
            case .addQuadCurveToPoint, .addCurveToPoint, .closeSubpath:
                assert(false)
            @unknown default:
                break
        }
    })
}

func PathPositionAndAngleForOffset(_ path: CGPath, _ startOffset: Double, _ baselineOffsetDistance: Double, _ pPos: inout CGPoint, _ pAngle: inout CGFloat, _ pLength: inout CGFloat) {
    var reachedOffset = false
    var quit = false
    var previous: CGPoint = .zero
    var offset = CGFloat(startOffset)

	path.apply(action: { element in
        if quit {
            return
        }
		switch element.type {
            case .moveToPoint:
                previous = element.points[0]
            case .addLineToPoint:
				let pt = element.points[0]
                var dx = pt.x - previous.x
                var dy = pt.y - previous.y
                let len = hypot(dx, dy)
                dx /= len
                dy /= len
                let a = CGFloat(atan2f(Float(dy), Float(dx)))

                // shift text off baseline
                let baselineOffset = CGPoint(x: Double(dy) * baselineOffsetDistance, y: Double(-dx) * baselineOffsetDistance)

                if !reachedOffset {
                    // always set position/angle because if we fall off the end we need it set
                    pPos.x = previous.x + offset * dx + baselineOffset.x
                    pPos.y = previous.y + offset * dy + baselineOffset.y
                    pAngle = a
                    pLength = len - offset
                } else {
                    if abs(Float(a - CGFloat(pAngle))) < .pi / 40 {
                        // continuation of previous
                        pLength = len - offset
                    } else {
                        quit = true
                    }
                }

                if offset < len {
                    // found it
                    reachedOffset = true
                }
                offset -= len
                previous = pt
            case .addQuadCurveToPoint, .addCurveToPoint, .closeSubpath:
                assert(false)
            @unknown default:
                break
        }
    })
}

class PathUtil {
	static func pathReversed(_ path: CGPath) -> CGMutablePath { // reverse path
		var a: [CGPoint] = []
		path.apply(action: { element in
			if element.type == .moveToPoint || element.type == .addLineToPoint {
				a.append( element.points[0] )
			}
		})
		let newPath = CGMutablePath()
		var first = true
		for pt in a.reversed() {
			if first {
				first = false
				newPath.move(to: pt)
			} else {
				newPath.addLine(to: pt)
			}
		}
		return newPath
	}
}

private func DouglasPeuckerCore(_ points: [CGPoint], _ first: Int, _ last: Int, _ epsilon: Double, _ result: inout [CGPoint] ) {
    // Find the point with the maximum distance
    var dmax: Double = 0.0
    var index: Int = 0
    let end1 = OSMPointFromCGPoint(points[first])
    let end2 = OSMPointFromCGPoint(points[last])
    for i in (first + 1)..<last {
        let p = OSMPointFromCGPoint(points[i])
        let d = DistanceFromPointToLineSegment(p, end1, end2)
        if Double(d) > dmax {
            index = i
            dmax = Double(d)
        }
    }
    // If max distance is greater than epsilon, recursively simplify
    if dmax > epsilon {
        // Recursive call
        DouglasPeuckerCore(points, first, index, epsilon, &result)
		result.removeLast()
		DouglasPeuckerCore(points, index, last, epsilon, &result)
    } else {
		result.append( CGPointFromOSMPoint(end1) )
		result.append( CGPointFromOSMPoint(end2) )
    }
}

func PathWithReducePoints(_ path: CGPath, _ epsilon: Double) -> CGMutablePath {
    let count = CGPathPointCount(path)
    if count < 3 {
        return path.mutableCopy()!
    }
	let points = CGPathGetPoints( path )
	var result = [CGPoint].init(repeating: CGPoint(), count: points.count)
	DouglasPeuckerCore(points, 0, count - 1, epsilon, &result)

    let newPath = CGMutablePath()
    newPath.addLines(between: result, transform: .identity)
	return newPath
}
