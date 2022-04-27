//
//  PathUtil.swift
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 1/24/13.
//  Copyright (c) 2013 Bryce Cogswell. All rights reserved.
//

import CoreGraphics

extension CGPath {
	func apply(action: (CGPathElement) -> Void) {
		// get a copy of the block to invoke on each element
		var action = action
		// call the native CGPath.apply(), passing the block in info
		apply(info: &action, function: { type, element in
			// cast info to be a function pointer
			let block = type!.bindMemory(to: ((CGPathElement) -> Void).self, capacity: 1).pointee
			// call the function
			block(element.pointee)
		})
	}

	func pointCount() -> Int {
		var count = 0
		apply(action: { _ in count += 1 })
		return count
	}

	func getPoints() -> [CGPoint] {
		var list = [CGPoint]()
		list.reserveCapacity(pointCount())
		apply(action: { element in
			switch element.type {
			case .moveToPoint, .addLineToPoint:
				list.append(element.points[0])
			case .closeSubpath:
				list.append(list[0])
			default:
				break
			}
		})
		return list
	}

	func pathDump() {
		apply(action: { element in
			let point = element.points[0]
			print("\(point.x),\(point.y)")
		})
	}

	func invokeBlockAlongPath(
		_ initialOffset: CGFloat,
		_ interval: CGFloat,
		_ callback: (_ pt: CGPoint, _ direction: CGPoint) -> Void)
	{
		var offset = initialOffset
		var previous = CGPoint()

		apply(action: { element in
			switch element.type {
			case .moveToPoint:
				previous = element.points[0]
			case .addLineToPoint:
				let nextPt = element.points[0]
				var dx = nextPt.x - previous.x
				var dy = nextPt.y - previous.y
				let len = CGFloat(sqrt(dx * dx + dy * dy))
				dx /= len
				dy /= len

				while offset < len {
					// found it
					let pos = CGPoint(x: previous.x + offset * dx, y: previous.y + offset * dy)
					let dir = CGPoint(x: dx, y: dy)
					callback(pos, dir)
					offset += interval
				}
				offset -= len
				previous = nextPt
			case .addQuadCurveToPoint, .addCurveToPoint, .closeSubpath:
				assertionFailure()
			@unknown default:
				break
			}
		})
	}

	func pathPositionAndAngleForOffset(
		_ startOffset: CGFloat,
		_ baselineOffsetDistance: CGFloat,
		_ pPos: inout CGPoint,
		_ pAngle: inout CGFloat,
		_ pLength: inout CGFloat)
	{
		var reachedOffset = false
		var quit = false
		var previous: CGPoint = .zero
		var offset = CGFloat(startOffset)

		apply(action: { element in
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
				let baselineOffset = CGPoint(x: dy * baselineOffsetDistance, y: -dx * baselineOffsetDistance)

				if !reachedOffset {
					// always set position/angle because if we fall off the end we need it set
					pPos.x = previous.x + offset * dx + baselineOffset.x
					pPos.y = previous.y + offset * dy + baselineOffset.y
					pAngle = a
					pLength = len - offset
				} else {
					if abs(a - pAngle) < .pi / 40 {
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
				assertionFailure()
			@unknown default:
				break
			}
		})
	}

	private static func DouglasPeuckerCore(
		_ points: ArraySlice<CGPoint>,
		_ epsilon: Double,
		_ result: inout [CGPoint])
	{
		// Find the point the maximum distance away from the line connecting first and last points
		let p1 = OSMPoint(points.first!)
		let p2 = OSMPoint(points.last!)
		let distances = points.map({ OSMPoint($0).distanceToLineSegment(p1, p2) })
		let maxDist = distances.indices.max(by: {distances[$0] < distances[$1]})!

		// If max distance is greater than epsilon, recursively simplify
		if distances[maxDist] > epsilon {
			// Recursive call
			let midpoint = points.startIndex+maxDist
			DouglasPeuckerCore(points[..<midpoint], epsilon, &result)
			result.removeLast()
			DouglasPeuckerCore(points[midpoint...], epsilon, &result)
		} else {
			result.append(CGPoint(p1))
			result.append(CGPoint(p2))
		}
	}

	func pathWithReducedPoints(_ epsilon: Double) -> CGMutablePath {
		let points = getPoints()
		if points.count < 3 {
			return mutableCopy()!
		}
		var result = [CGPoint]()
		CGPath.DouglasPeuckerCore(points[points.indices], epsilon, &result)
		let newPath = CGMutablePath()
		newPath.addLines(between: result)
		return newPath
	}

	func reversed() -> CGMutablePath { // reverse path
		let a = getPoints()
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
