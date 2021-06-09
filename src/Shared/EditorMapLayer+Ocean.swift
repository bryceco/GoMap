//
//  EditorMapLayer+Ocean.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 6/21/20.
//  Copyright © 2020 Bryce. All rights reserved.
//

import Foundation

extension OSMPoint: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(x)
        hasher.combine(y)
    }
}

extension EditorMapLayer {
	
    private static func AppendNodes(_ list: inout [OsmNode], way: OsmWay, addToBack: Bool, reverseNodes: Bool) {
        let nodes = reverseNodes ? way.nodes.reversed() : way.nodes
		if addToBack {
            // insert at back of list
            let a = nodes[1 ..< nodes.count]
            list.append(contentsOf: a)
        } else {
            // insert at front of list
            let a = nodes[0 ..< nodes.count - 1]
            list.insert(contentsOf: a, at: 0)
        }
    }

    private static func IsPointInRect(_ pt: OSMPoint, rect: OSMRect) -> Bool {
        let delta = 0.0001
        if pt.x < rect.origin.x - delta {
            return false
        }
        if pt.x > rect.origin.x + rect.size.width + delta {
            return false
        }
        if pt.y < rect.origin.y - delta {
            return false
        }
        if pt.y > rect.origin.y + rect.size.height + delta {
            return false
        }
        return true
    }

    private enum SIDE {
        case LEFT, TOP, RIGHT, BOTTOM
    }

    private static func WallForPoint(_ pt: OSMPoint, rect: OSMRect) -> SIDE {
        let delta = 0.01
        if fabs(pt.x - rect.origin.x) < delta {
            return .LEFT
        }
        if fabs(pt.y - rect.origin.y) < delta {
            return .TOP
        }
        if fabs(pt.x - rect.origin.x - rect.size.width) < delta {
            return .RIGHT
        }
        if fabs(pt.y - rect.origin.y - rect.size.height) < delta {
            return .BOTTOM
        }
		fatalError()
    }

    private static func IsClockwisePolygon(_ points: [OSMPoint]) -> Bool {
        if points.count < 4 { // first and last repeat
            return false // invalid
        }
        if points[0] != points.last! {
            return false // invalid
        }
        var area = 0.0
        let offset = points[0]
        var previous = OSMPoint(x: 0, y: 0)

        for point in points[1 ..< points.count] {
            let current = OSMPoint(x: point.x - offset.x, y: point.y - offset.y)
            area += previous.x * current.y - previous.y * current.x
            previous = current
        }
        area *= 0.5
        return area >= 0
    }

    private static func RotateLoop(_ loop: inout [OSMPoint], viewRect: OSMRect) -> Bool {
        if loop.count < 4 {
            return false // bad loop
        }
        if loop[0] != loop.last! {
            return false // bad loop
        }
        loop.removeLast()
        var index = 0
        for point in loop {
			if !viewRect.containsPoint( point) {
                break
            }
            index += 1
            if index >= loop.count {
                index = -1
                break
            }
        }
        if index > 0 {
            let set = 0 ..< index
            let a = loop[set]
            loop.removeSubrange(set)
            loop.append(contentsOf: a)
        }
        loop.append(loop[0])
        return index >= 0
    }

    static func ClipLineToRect(p1: OSMPoint, p2: OSMPoint, rect: OSMRect) -> [OSMPoint] {
		if p1.x.isInfinite || p2.x.isInfinite {
            return []
		}

        let top = rect.origin.y
        let bottom = rect.origin.y + rect.size.height
        let left = rect.origin.x
        let right = rect.origin.x + rect.size.width

        let dx = p2.x - p1.x
        let dy = p2.y - p1.y

        // get distances in terms of 0..1
        // we compute crossings for not only the rectangles walls but also the projections of the walls outside the rectangle,
        // so 4 possible interesection points
        var cross = [Double]()
        if dx != 0 {
            let vLeft = (left - p1.x) / dx
            let vRight = (right - p1.x) / dx
            if vLeft >= 0, vLeft <= 1 {
                cross.append(vLeft)
            }
            if vRight >= 0, vRight <= 1 {
                cross.append(vRight)
            }
        }
        if dy != 0 {
            let vTop = (top - p1.y) / dy
            let vBottom = (bottom - p1.y) / dy
            if vTop >= 0, vTop <= 1 {
                cross.append(vTop)
            }
            if vBottom >= 0, vBottom <= 1 {
                cross.append(vBottom)
            }
        }

        // sort crossings according to distance from p1
        cross.sort()

        // get the points that are actually inside the rect (max 2)
        let pts = cross.map { OSMPoint(x: p1.x + $0 * dx, y: p1.y + $0 * dy) }.filter { IsPointInRect($0, rect: rect) }

        return pts
    }

    // input is an array of OsmWay
    // output is an array of arrays of OsmNode
    // take a list of ways and return a new list of ways with contiguous ways joined together.
    private static func joinConnectedWays(_ origList: inout [OsmWay]) -> [[OsmNode]] {
        // connect ways together forming congiguous runs
        var newList = [[OsmNode]]()
        while origList.count > 0 {
            // find all connected segments
            let way = origList.removeLast()

            var firstNode = way.nodes[0] // FIXME: remove these
            var lastNode = way.nodes.last
            var nodeList = [firstNode]
            EditorMapLayer.AppendNodes(&nodeList, way: way, addToBack: true, reverseNodes: false)
            while nodeList[0] != nodeList.last {
                // find a way adjacent to current list
                var found: OsmWay?
                for way in origList {
                    if lastNode == way.nodes[0] {
                        EditorMapLayer.AppendNodes(&nodeList, way: way, addToBack: true, reverseNodes: false)
                        lastNode = nodeList.last
                        found = way
                        break
                    }
                    if lastNode == way.nodes.last {
                        EditorMapLayer.AppendNodes(&nodeList, way: way, addToBack: true, reverseNodes: true)
                        lastNode = nodeList.last
                        found = way
                        break
                    }
                    if firstNode == way.nodes.last {
                        EditorMapLayer.AppendNodes(&nodeList, way: way, addToBack: false, reverseNodes: false)
                        firstNode = nodeList[0]
                        found = way
                        break
                    }
                    if firstNode == way.nodes[0] {
                        EditorMapLayer.AppendNodes(&nodeList, way: way, addToBack: false, reverseNodes: true)
                        firstNode = nodeList[0]
                        found = way
                        break
                    }
                }
                if found == nil {
                    break // didn't find anything to connect to
                }
                origList.removeAll(where: { $0 == found! })
            }
            newList.append(nodeList)
        }
        return newList
    }

    private func convertNodesToScreenPoints(_ nodeList: [OsmNode]) -> [OSMPoint] {
        if nodeList.count == 0 {
            return []
        }
        let pointlist = nodeList.map { (node) -> OSMPoint in
            let pt = self.mapView.screenPoint(forLatitude: node.lat, longitude: node.lon, birdsEye: false)
            return OSMPoint(pt)
        }
        return pointlist
    }

    private static func visibleSegmentsOfWay(_ way: inout [OSMPoint], inView viewRect: OSMRect) -> [[OSMPoint]] {
        // trim nodes in outlines to only internal paths
        var newWays = [[OSMPoint]]()

        var first = true
        var prevInside = false
        let isLoop = way[0] == way.last!
        var prevPoint = OSMPoint(x: 0, y: 0)
        var trimmedSegment: [OSMPoint]?

        if isLoop {
            // rotate loop to ensure start/end point is outside viewRect
            let ok = EditorMapLayer.RotateLoop(&way, viewRect: viewRect)
            if !ok {
                // entire loop is inside view
                return [way]
            }
        }

        for pt in way {
			let isInside = viewRect.containsPoint( pt)
            if first {
                first = false
            } else {
                var isEntry = false
                var isExit = false
                if prevInside {
                    if isInside {
                        // still inside
                    } else {
                        // moved to outside
                        isExit = true
                    }
                } else {
                    if isInside {
                        // moved inside
                        isEntry = true
                    } else {
                        // if previous and current are both outside maybe we intersected
                        if LineSegmentIntersectsRectangle(prevPoint, pt, viewRect),
                            !pt.x.isInfinite,
                            !prevPoint.x.isInfinite
                        {
                            isEntry = true
                            isExit = true
                        } else {
                            // still outside
                        }
                    }
                }

                let pts = (isEntry || isExit) ? EditorMapLayer.ClipLineToRect(p1: prevPoint, p2: pt, rect: viewRect) : nil
                if isEntry {
                    // start tracking trimmed segment
                    // assert( crossCnt >= 1 );
                    let v = pts![0]
                    trimmedSegment = [v]
                }
                if isExit {
                    // end of trimmed segment. If the way began inside the viewrect then trimmedSegment is nil and gets ignored
                    // assert( crossCnt >= 1 );
                    if trimmedSegment != nil {
                        let v = pts!.last!
                        trimmedSegment!.append(v)
                        newWays.append(trimmedSegment!)
                        trimmedSegment = nil
                    }
                } else if isInside {
                    // internal node for trimmed segment
                    if trimmedSegment != nil {
                        trimmedSegment!.append(pt)
                    }
                }
            }
            prevPoint = pt
            prevInside = isInside
        }
        return newWays
    }

    private static func addPointList(_ list: [OSMPoint], toPath path: CGMutablePath) {
        var first = true
        for p in list {
            if p.x.isInfinite {
                break
            }
            let pt = CGPoint(p)
            if first {
                first = false
                path.move(to: pt)
            } else {
                path.addLine(to: pt)
            }
        }
    }

	public func getOceanLayer(_ objectList: [OsmBaseObject]) -> CAShapeLayer? {
        // get all coastline ways
        var outerWays = [OsmWay]()
        var innerWays = [OsmWay]()

        for object in objectList {
            if object.isWay()?.isClosed() == true,
				let value = object.tags["natural"],
				value == "water"
            {
                continue // lakes are not a concern of this function
            }
            if object.isCoastline() {
                if let way = object.isWay() {
                    outerWays.append(way)
                } else if let relation = object.isRelation() {
                    for member in relation.members {
                        if let way = member.obj as? OsmWay {
							if member.role == "outer" {
                                outerWays.append(way)
                            } else if member.role == "inner" {
                                innerWays.append(way)
                            } else {
                                // skip
                            }
                        }
                    }
                }
            }
        }
        if outerWays.count == 0 {
            return nil
        }

        // connect ways together forming contiguous runs
        let outerNodes = EditorMapLayer.joinConnectedWays(&outerWays)
        let innerNodes = EditorMapLayer.joinConnectedWays(&innerWays)

        // convert lists of nodes to screen points
        var outerSegments = outerNodes.map { self.convertNodesToScreenPoints($0) }
        var innerSegments = innerNodes.map { self.convertNodesToScreenPoints($0) }

        // Delete loops with a degenerate number of nodes. These are typically data errors:
        outerSegments = outerSegments.filter { $0.count >= 4 || $0[0] != $0.last! }
        innerSegments = innerSegments.filter { $0.count >= 4 || $0[0] != $0.last! }

        // ensure that outer ways are clockwise and inner ways are counterclockwise
        for index in 0 ..< outerSegments.count {
            let way = outerSegments[index]
            if way[0] == way.last! {
                if !EditorMapLayer.IsClockwisePolygon(way) {
                    // reverse points
                    outerSegments[index].reverse()
                }
            }
        }
        for index in 0 ..< innerSegments.count {
            let way = innerSegments[index]
            if way[0] == way.last! {
                if EditorMapLayer.IsClockwisePolygon(way) {
                    // reverse points
                    innerSegments[index].reverse()
                }
            }
        }

        let cgViewRect = bounds
        let viewRect = OSMRect(cgViewRect)
		let viewCenter = OSMPoint(cgViewRect.center())

        // trim nodes in segments to only visible paths
        var visibleSegments = [[OSMPoint]]()
        for index in 0 ..< outerSegments.count {
            let a = EditorMapLayer.visibleSegmentsOfWay(&outerSegments[index], inView: viewRect)
            visibleSegments.append(contentsOf: a)
        }
        for index in 0 ..< innerSegments.count {
            let a = EditorMapLayer.visibleSegmentsOfWay(&innerSegments[index], inView: viewRect)
            visibleSegments.append(contentsOf: a)
        }

        if visibleSegments.count == 0 {
            // nothing is on screen
            return nil
        }

        // pull islands into a separate list
        var islands = [[OSMPoint]]()
        visibleSegments.removeAll(where: { (a) -> Bool in
            if a[0] == a.last! {
                islands.append(a)
                return true
            } else {
                return false
            }
        })

        // get list of all external points
        var pointSet = Set<OSMPoint>()
        var entryDict = [OSMPoint: [OSMPoint]]()
        for way in visibleSegments {
            pointSet.insert(way[0])
            pointSet.insert(way.last!)
            entryDict[way[0]] = way
        }

        // sort points clockwise
        let points = pointSet.sorted(by: { (pt1, pt2) -> Bool in
            let ang1 = atan2(pt1.y - viewCenter.y, pt1.x - viewCenter.x)
            let ang2 = atan2(pt2.y - viewCenter.y, pt2.x - viewCenter.x)
            let angle = ang1 - ang2
            return angle < 0
        })

        // now have a set of discontiguous arrays of coastline nodes. Draw segments adding points at screen corners to connect them
        var haveCoastline = false
        let path = CGMutablePath()
        while visibleSegments.count > 0 {
            let firstOutline = visibleSegments.removeLast()
            var exit = firstOutline.last!

            EditorMapLayer.addPointList(firstOutline, toPath: path)

            while true {
                // find next point following exit point
                var nextOutline: [OSMPoint]? = entryDict[exit] // check if exit point is also entry point
                if nextOutline == nil { // find next entry point following exit point
                    let exitIndex = points.firstIndex(of: exit)!
                    let entryIndex = (exitIndex + 1) % points.count
                    nextOutline = entryDict[points[entryIndex]]
                }
                if nextOutline == nil {
                    return nil
                }
                let entry = nextOutline![0]

                // connect exit point to entry point following clockwise borders
                if true {
                    var point1 = exit
                    let point2 = entry
                    var wall1 = EditorMapLayer.WallForPoint(point1, rect: viewRect)
                    let wall2 = EditorMapLayer.WallForPoint(point2, rect: viewRect)

                    wall_loop: while true {
                        switch wall1 {
                        case .LEFT:
                            if wall2 == .LEFT, point1.y > point2.y {
                                break wall_loop
                            }
							point1 = OSMPoint(x: viewRect.origin.x, y: viewRect.origin.y)
                            path.addLine(to: CGPoint(point1))
                            fallthrough
                        case .TOP:
                            if wall2 == .TOP, point1.x < point2.x {
                                break wall_loop
                            }
							point1 = OSMPoint(x: viewRect.origin.x + viewRect.size.width, y: viewRect.origin.y)
                            path.addLine(to: CGPoint(point1))
                            fallthrough
                        case .RIGHT:
                            if wall2 == .RIGHT, point1.y < point2.y {
                                break wall_loop
                            }
							point1 = OSMPoint(x: viewRect.origin.x + viewRect.size.width, y: viewRect.origin.y + viewRect.size.height)
                            path.addLine(to: CGPoint(point1))
                            fallthrough
                        case .BOTTOM:
                            if wall2 == .BOTTOM, point1.x > point2.x {
                                break wall_loop
                            }
							point1 = OSMPoint(x: viewRect.origin.x, y: viewRect.origin.y + viewRect.size.height)
                            path.addLine(to: CGPoint(point1))
                            wall1 = .LEFT
                        }
                    }
                }

                haveCoastline = true
                if nextOutline == firstOutline {
                    break
                }
                if !visibleSegments.contains(nextOutline!) {
                    return nil
                }
                for pt in nextOutline! {
                    path.addLine(to: CGPoint(pt))
                }

                exit = nextOutline!.last!
                visibleSegments.removeAll { $0 == nextOutline }
            }
        }

        // draw islands
        for island in islands {
            EditorMapLayer.addPointList(island, toPath: path)

            if !haveCoastline, EditorMapLayer.IsClockwisePolygon(island) {
                // this will still fail if we have an island with a lake in it
                haveCoastline = true
            }
        }

        // if no coastline then draw water everywhere
        if !haveCoastline {
            path.addRect(cgViewRect)
        }

        let layer = CAShapeLayer()
        layer.path = path
        layer.frame = bounds
        layer.bounds = bounds
        layer.fillColor = UIColor(red: 0, green: 0, blue: 1, alpha: 0.1).cgColor
        layer.strokeColor = UIColor.blue.cgColor
        //		layer.lineJoin		= DEFAULT_LINEJOIN
        //		layer.lineCap		= DEFAULT_LINECAP
        layer.lineWidth = 2.0
        //		layer.zPosition		= Z_OCEAN;	// FIXME

        return layer
    }
}
