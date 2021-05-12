//  Converted to Swift 5.4 by Swiftify v5.4.27034 - https://swiftify.com/
//
//  PathUtil.swift
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 1/24/13.
//  Copyright (c) 2013 Bryce Cogswell. All rights reserved.
//

//#define OpenStreetMap_PathUtil_h
//typealias ApplyPathCallback = (CGPathElementType?, UnsafeMutablePointer<CGPoint>?) -> Void

private func InvokeBlockAlongPathCallback2(_ info: Void, _ element: CGPathElement?) {
    let block = info as ApplyPathCallback
    block(element?.type, element?.points)
}

func CGPathApplyBlockEx(_ path: CGPath, _ block: ApplyPathCallback) {
    CGpathApply(path, block, InvokeBlockAlongPathCallback2)
    path.apply(info: block, function: InvokeBlockAlongPathCallback2)
}

func CGPathPointCount(_ path: CGPath) -> Int {
    var count = 0
    CGPathApplyBlockEx(path, { type, points in
        count += 1
    })
    return count
}

func CGPathGetPoints(_ path: CGPath, _ pointList: inout [CGPoint]) -> Int {
    var index = 0
    CGPathApplyBlockEx(path, { type, points in
        switch type {
            case .moveToPoint, .addLineToPoint:
                pointList[index] = points?[0] ?? CGPoint.zero
                index += 1
            case .closeSubpath:
                pointList[index] = pointList[0]
                index += 1
            default:
                break
        }
    })
    return index
}

func CGPathDump(_ path: CGPath) {
    CGPathApplyBlockEx(path, { type, points in
        print("\(points?.pointee.x ?? 0.0),\(points?.pointee.y ?? 0.0)")
    })
}

func InvokeBlockAlongPath(_ path: CGPath?, _ initialOffset: Double, _ interval: Double, _ callback: (_ pt: CGPoint, _ direction: CGPoint) -> Void) {
    var offset = CGFloat(initialOffset)
    var previous: CGPoint

    let block: ((_ type: CGPathElementType, _ points: [CGPoint]) -> Void) = { type, points in
        switch type {
            case .moveToPoint:
                
                previous = points[0]
            case .addLineToPoint:
                let nextPt = points[0]
                var dx = Double((nextPt.x) - previous.x)
                var dy = Double((nextPt.y) - previous.y)
                let len = sqrt(dx * dx + dy * dy)
                dx /= len
                dy /= len

                while Double(offset) < len {
                    // found it
                    let pos = CGPoint(x: Double(previous.x) + Double(offset) * dx, y: Double(previous.y) + Double(offset) * dy)
                    let dir = CGPoint(x: dx, y: dy)
                    callback(pos, dir)
                    offset += CGFloat(interval)
                }
                offset -= CGFloat(len)
                previous = nextPt
            case .addQuadCurveToPoint, .addCurveToPoint, .closeSubpath:
                assert(false)
            @unknown default:
                break
        }
    }
    CGPathApplyBlockEx(path, block)
}

func PathPositionAndAngleForOffset(_ path: CGPath, _ startOffset: Double, _ baselineOffsetDistance: Double, _ pPos: inout CGPoint, _ pAngle: inout CGFloat, _ pLength: inout CGFloat) {
    var reachedOffset = false
    var quit = false
    var previous: CGPoint = .zero
    var offset = CGFloat(startOffset)

    CGPathApplyBlockEx(path, { type, points in
        if quit {
            return
        }
        switch type {
            case .moveToPoint:
                previous = points?[0] ?? CGPoint.zero
            case .addLineToPoint:
                let pt = points?[0]
                var dx = (pt?.x ?? 0.0) - previous.x
                var dy = (pt?.y ?? 0.0) - previous.y
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
                previous = pt ?? CGPoint.zero
            case .addQuadCurveToPoint, .addCurveToPoint, .closeSubpath:
                assert(false)
            @unknown default:
                break
        }
    })
}

func PathReversed(_ path: CGPath) -> CGMutablePath { // reverse path
    var a: [OSMPointBoxed] = []
    CGPathApplyBlockEx(path, { type, points in
        if type == .moveToPoint || type == .addLineToPoint {
            let cgPoint = points?[0]
            let pt = OSMPoint(x: Double(cgPoint?.x ?? 0.0), y: Double(cgPoint?.y ?? 0.0))
            let boxed = OSMPointBoxed.point(with: pt)
            if let boxed = boxed {
                a.append(boxed)
            }
        }
    })
    let newPath = CGMutablePath()
    var first = true
    for pt in a {
        if first {
            first = false
            newPath.move(to: CGPoint(x: pt.point.x, y: pt.point.y ), transform: .identity)
        } else {
            newPath.addLine(to: CGPoint(x: pt.point.x, y: pt.point.y), transform: .identity)
        }
    }
    return newPath
}

private func DouglasPeuckerCore(_ points: [CGPoint], _ first: Int, _ last: Int, _ epsilon: Double, _ result: inout CGPoint) -> CGPoint {
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
        result = DouglasPeuckerCore(points, first, index, epsilon, &result)
        result = DouglasPeuckerCore(points, index, last, epsilon, &result - 1)
    } else {
        result = (result ?? CGPoint.zero) + 1 = CGPointFromOSMPoint(end1)
        result = (result ?? CGPoint.zero) + 1 = CGPointFromOSMPoint(end2)
    }
    return result
}

func PathWithReducePoints(_ path: CGPath, _ epsilon: Double) -> CGMutablePath? {
    let count = CGPathPointCount(path)
    if count < 3 {
        return path.mutableCopy()
    }
    let points = malloc(count * MemoryLayout.size(ofValue: points?[0])) as? CGPoint
    let result = malloc(count * MemoryLayout.size(ofValue: result?[0])) as? CGPoint
    CGPathGetPoints(path, points ?? [])
    let resultLast = DouglasPeuckerCore(points ?? [], 0, count - 1, epsilon, &result)
    let resultCount = (resultLast ?? CGPoint.zero) - (result ?? CGPoint.zero)
    let newPath = CGMutablePath()
    newPath.addLines(between: result, transform: .identity)
    free(points)
    free(result)
    return newPath
}
