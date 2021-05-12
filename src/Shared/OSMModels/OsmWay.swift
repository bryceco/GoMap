//  Converted to Swift 5.4 by Swiftify v5.4.27034 - https://swiftify.com/
//
//  OsmWay.swift
//  Go Map!!
//
//  Created by Wolfgang Timme on 1/18/20.
//  Copyright © 2020 Bryce. All rights reserved.
//

class OsmWay: OsmBaseObject {
    private(set) var nodes: [OsmNode]?

    override var description: String {
        return "OsmWay \(super.description)"
    }

    func constructNode(_ node: NSNumber?) {
        assert(!constructed)
        if nodes == nil {
            nodes = [node].compactMap { $0 }
        } else {
            if let node = node {
                nodes?.append(node)
            }
        }
    }

    func constructNodeList(_ nodes: inout [AnyHashable]) {
        assert(!constructed)
        self.nodes = nodes
    }

    override func `is`() -> OsmWay? {
        return self
    }

    func resolve(to mapData: OsmMapData?) {
        var i = 0, e = (nodes?.count ?? 0)
        while i < e {
            let ref = nodes?[i] as? NSNumber
            if !(ref is NSNumber) {
                continue
            }
            let node = mapData?.node(forRef: ref)
            assert(node != nil, nil)
            nodes?[i] = node
            node?.setWayCount((node?.wayCount ?? 0) + 1, undo: nil)
            i += 1
        }
    }

    @objc func removeNode(at index: Int, undo: UndoManager?) {
        assert(undo)
        let node = nodes?[index]
        incrementModifyCount(undo)
        undo?.registerUndo(withTarget: self, selector: #selector(add(_:at:undo:)), objects: [node, NSNumber(value: index), undo])
        nodes?.remove(at: index)
        node?.setWayCount((node?.wayCount ?? 0) - 1, undo: nil)
        computeBoundingBox()
    }

    @objc func add(_ node: OsmNode?, at index: Int, undo: UndoManager?) {
        if constructed {
            assert(undo)
            incrementModifyCount(undo)
            undo?.registerUndo(withTarget: self, selector: #selector(removeNode(at:undo:)), objects: [NSNumber(value: index), undo])
        }
        if nodes == nil {
            nodes = []
        }
        if let node = node {
            nodes?.insert(node, at: index)
        }
        node?.setWayCount((node?.wayCount ?? 0) + 1, undo: nil)
        computeBoundingBox()
    }

    override func serverUpdate(inPlace newerVersion: OsmWay?) {
        super.serverUpdate(inPlace: newerVersion)
        nodes = newerVersion?.nodes
    }

    func isArea() -> Bool {
        return PresetsDatabase.shared.isArea(self)
    }

    func isClosed() -> Bool {
        return (nodes?.count ?? 0) > 2 && nodes?[0] == nodes?.last
    }

    static var computeIsOneWayOneWayTags: [AnyHashable : Any]? = nil

    func computeIsOneWay() -> ONEWAY {
        if OsmWay.computeIsOneWayOneWayTags == nil {
            OsmWay.computeIsOneWayOneWayTags = [
                "aerialway": [
                "chair_lift": NSNumber(value: true),
                "mixed_lift": NSNumber(value: true),
                "t-bar": NSNumber(value: true),
                "j-bar": NSNumber(value: true),
                "platter": NSNumber(value: true),
                "rope_tow": NSNumber(value: true),
                "magic_carpet": NSNumber(value: true),
                "yes": NSNumber(value: true)
            ],
                "highway": [
                "motorway": NSNumber(value: true),
                "motorway_link": NSNumber(value: true),
                "steps": NSNumber(value: true)
            ],
                "junction": [
                "roundabout": NSNumber(value: true)
            ],
                "man_made": [
                "piste:halfpipe": NSNumber(value: true),
                "embankment": NSNumber(value: true)
            ],
                "natural": [
                "cliff": NSNumber(value: true),
                "coastline": NSNumber(value: true)
            ],
                "piste:type": [
                "downhill": NSNumber(value: true),
                "sled": NSNumber(value: true),
                "yes": NSNumber(value: true)
            ],
                "waterway": [
                "brook": NSNumber(value: true),
                "canal": NSNumber(value: true),
                "ditch": NSNumber(value: true),
                "drain": NSNumber(value: true),
                "fairway": NSNumber(value: true),
                "river": NSNumber(value: true),
                "stream": NSNumber(value: true),
                "weir": NSNumber(value: true)
            ]
            ]
        }

        let oneWayVal = tags?["oneway"]
        if let oneWayVal = oneWayVal {
            if (oneWayVal == "yes") || (oneWayVal == "1") {
                return ._FORWARD
            }
            if (oneWayVal == "no") || (oneWayVal == "0") {
                return ._NONE
            }
            if oneWayVal == "-1" {
                return ._BACKWARD
            }
        }

        var oneWay: ONEWAY = ._NONE
        (tags as NSDictionary?)?.enumerateKeysAndObjects({ tag, value, stop in
            let valueDict = OsmWay.computeIsOneWayOneWayTags[tag ?? ""] as? [AnyHashable : Any]
            if let valueDict = valueDict {
                if valueDict[value ?? ""] != nil {
                    oneWay = ._FORWARD
                    stop = UnsafeMutablePointer<ObjCBool>(mutating: &true)
                }
            }
        })
        return oneWay
    }

    func sharesNodes(with way: OsmWay?) -> Bool {
        if (nodes?.count ?? 0) * (way?.nodes?.count ?? 0) < 100 {
            for n in way?.nodes ?? [] {
                if nodes?.contains(n) ?? false {
                    return true
                }
            }
            return false
        } else {
            let set1 = Set<AnyHashable>(way?.nodes)
            let set2 = Set<AnyHashable>(nodes)
            return set1.intersect(set2)
        }
    }

    func isMultipolygonMember() -> Bool {
        for parent in parentRelations ?? [] {
            guard let parent = parent as? OsmRelation else {
                continue
            }
            if parent.isMultipolygon() && (parent.tags?.count ?? 0) > 0 {
                return true
            }
        }
        return false
    }

    func isSimpleMultipolygonOuterMember() -> Bool {
        let parents = parentRelations
        if (parents?.count ?? 0) != 1 {
            return false
        }

        let parent = parents?[0] as? OsmRelation
        if !(parent?.isMultipolygon() ?? false) || (parent?.tags?.count ?? 0) > 1 {
            return false
        }

        for member in parent?.members ?? [] {
            if (member.ref as? OsmWay) == self {
                if member.role != "outer" {
                    return false // Not outer member
                }
            } else {
                if member.role == nil || (member.role == "outer") {
                    return false // Not a simple multipolygon
                }
            }
        }
        return true
    }

    func isSelfIntersection(_ node: OsmNode?) -> Bool {
        if (nodes?.count ?? 0) < 3 {
            return false
        }
        var first: Int? = nil
        if let node = node {
            first = nodes?.firstIndex(of: node) ?? NSNotFound
        }
        if first == NSNotFound {
            return false
        }
        let next = (first ?? 0) + 1
        if next >= (nodes?.count ?? 0) {
            return false
        }
        var second: Int? = nil
        if let node = node {
            second = (nodes as NSArray?)?.index(of: node, in: NSRange(location: next, length: (nodes?.count ?? 0) - next)) ?? 0
        }
        if second == NSNotFound {
            return false
        }
        return true
    }

    func needsNoNameHighlight() -> Bool {
        let highway = tags?["highway"]
        if highway == nil {
            return false
        }
        if highway == "service" {
            return false
        }
        if givenName() != nil {
            return false
        }
        if tags?["noname"] == "yes" {
            return false
        }
        return true
    }

    func wayArea() -> Double {
        assert(false)
        return 0
    }

    // return the point on the way closest to the supplied point
    override func pointOnObject(for target: OSMPoint) -> OSMPoint {
        switch (nodes?.count ?? 0) {
            case 0:
                return target
            case 1:
                return ((nodes?.last)?.location())!
            default:
                break
        }
        var bestPoint = OSMPoint(0, 0)
        var bestDist: Double = 360 * 360
        for i in 1..<(nodes?.count ?? 0) {
            let p1 = (nodes?[i - 1])?.location()
            let p2 = (nodes?[i])?.location()
            let linePoint = ClosestPointOnLineToPoint(p1, p2, target)
            let dist = MagSquared(Sub(linePoint, target))
            if dist < bestDist {
                bestDist = dist
                bestPoint = linePoint
            }
        }
        return bestPoint
    }

    override func distance(toLineSegment point1: OSMPoint, point point2: OSMPoint) -> Double {
        if (nodes?.count ?? 0) == 1 {
            return nodes?.last?.distance(toLineSegment: point1, point: point2) ?? 0.0
        }
        var dist = 1000000.0
        var prevNode: OsmNode? = nil
        for node in nodes ?? [] {
            if prevNode != nil && LineSegmentsIntersect(prevNode?.location(), node.location(), point1, point2) {
                return 0.0
            }
            let d = node.distance(toLineSegment: point1, point: point2)
            if d < dist {
                dist = d
            }
            prevNode = node
        }
        return dist
    }

    override func nodeSet() -> Set<AnyHashable>? {
        return Set<AnyHashable>(nodes)
    }

    override func computeBoundingBox() {
        var minX: Double
        var maxX: Double
        var minY: Double
        var maxY: Double
        var first = true
        for node in nodes ?? [] {
            let loc = node.location()
            if first {
                first = false
                maxX = loc.x
                minX = maxX
                maxY = loc.y
                minY = maxY
            } else {
                if loc.y < minY {
                    minY = loc.y
                }
                if loc.x < minX {
                    minX = loc.x
                }
                if loc.y > maxY {
                    maxY = loc.y
                }
                if loc.x > maxX {
                    maxX = loc.x
                }
            }
        }
        if first {
            boundingBox = OSMRectMake(0, 0, 0, 0)
        } else {
            boundingBox = OSMRectMake(minX, minY, maxX - minX, maxY - minY)
        }
    }

    func centerPoint(withArea pArea: UnsafeMutablePointer<Double>?) -> OSMPoint {
        var pArea = pArea
        var dummy: Double
        if pArea == nil {
            pArea = UnsafeMutablePointer<Double>(mutating: &dummy)
        }

        let isClosed = self.isClosed()

        let nodeCount = isClosed ? (nodes?.count ?? 0) - 1 : (nodes?.count ?? 0)

        if nodeCount > 2 {
            if isClosed {
                // compute centroid
                var sum: Double = 0
                var sumX: Double = 0
                var sumY: Double = 0
                var first = true
                var offset = OSMPoint(0, 0)
                var previous: OSMPoint
                for node in nodes ?? [] {
                    if first {
                        offset.x = node.lon
                        offset.y = node.lat
                        previous.x = 0
                        previous.y = 0
                        first = false
                    } else {
                        let current = OSMPoint(node.lon - offset.x, node.lat - offset.y)
                        let partialSum: CGFloat = previous.x * current.y - previous.y * current.x
                        sum += Double(partialSum)
                        sumX += Double((previous.x + current.x) * partialSum)
                        sumY += Double((previous.y + current.y) * partialSum)
                        previous = current
                    }
                }
                pArea = UnsafeMutablePointer<Double>(mutating: sum / 2)
                var point = OSMPoint(sumX / 6 / Double(pArea ?? 0.0), sumY / 6 / Double(pArea ?? 0.0))
                point.x += offset.x
                point.y += offset.y
                return point
            } else {
                // compute average
                var sumX: Double = 0
                var sumY: Double = 0
                for node in nodes ?? [] {
                    sumX += node.lon
                    sumY += node.lat
                }
                var point = OSMPoint(sumX / Double(nodeCount), sumY / Double(nodeCount))
                return point
            }
        } else if nodeCount == 2 {
            pArea = nil
            let n1 = nodes?[0]
            let n2 = nodes?[1]
            return OSMPointMake(((n1?.lon ?? 0.0) + (n2?.lon ?? 0.0)) / 2, ((n1?.lat ?? 0.0) + (n2?.lat ?? 0.0)) / 2)
        } else if nodeCount == 1 {
            pArea = nil
            let node = nodes?.last
            return OSMPointMake(node?.lon, node?.lat)
        } else {
            pArea = nil
            let pt = OSMPoint(0, 0)
            return pt
        }
    }

    func centerPoint() -> OSMPoint {
        return centerPoint(withArea: nil)
    }

    func lengthInMeters() -> Double {
        var first = true
        var len: Double = 0
        var prev = OSMPoint(0, 0)
        for node in nodes ?? [] {
            let pt = node.location()
            if !first {
                len += GreatCircleDistance(pt, prev)
            }
            first = false
            prev = pt
        }
        return len
    }

    // pick a point close to the center of the way
    override func selectionPoint() -> OSMPoint {
        var dist = lengthInMeters() / 2
        var first = true
        var prev = OSMPoint(0, 0)
        for node in nodes ?? [] {
            let pt = node.location()
            if !first {
                let segment = GreatCircleDistance(pt, prev)
                if segment >= dist {
                    let pos = Add(prev, Mult(Sub(pt, prev), dist / segment))
                    return pos
                }
                dist -= segment
            }
            first = false
            prev = pt
        }
        return prev // dummy value, shouldn't ever happen
    }

    class func isClockwiseArrayOfNodes(_ nodes: [AnyHashable]?) -> Bool {
        if (nodes?.count ?? 0) < 4 || nodes?[0] != nodes?.last {
            return false
        }
        var sum: CGFloat = 0
        var first = true
        var offset: OSMPoint
        var previous: OSMPoint
        for node in nodes ?? [] {
            guard let node = node as? OsmNode else {
                continue
            }
            let point = node.location()
            if first {
                offset = point
                previous.y = 0
                previous.x = previous.y
                first = false
            } else {
                let current = OSMPoint(point.x - offset.x, point.y - offset.y)
                sum += previous.x * current.y - previous.y * current.x
                previous = current
            }
        }
        return sum >= 0
    }

    func isClockwise() -> Bool {
        return OsmWay.isClockwiseArrayOfNodes(nodes)
    }

    class func shapePath(forNodes nodes: [AnyHashable]?, forward: Bool, withRefPoint pRefPoint: OSMPoint?) -> CGPath? {
        var pRefPoint = pRefPoint
        if (nodes?.count ?? 0) == 0 || nodes?[0] != nodes?.last {
            return nil
        }
        let path = CGMutablePath()
        var first = true
        // want loops to run clockwise
        let enumerator = forward ? (nodes as NSArray?)?.objectEnumerator() : (nodes as NSArray?)?.reverseObjectEnumerator()
        if let enumerator = enumerator {
            for n in enumerator {
                guard let n = n as? OsmNode else {
                    continue
                }
                let pt = MapPointForLatitudeLongitude(n.lat, n.lon)
                if first {
                    first = false
                    pRefPoint = pt
                    path.move(to: CGPoint(x: 0, y: 0), transform: .identity)
                } else {
                    path.addLine(to: CGPoint(x: CGFloat((pt.x - pRefPoint?.x) * PATH_SCALING), y: CGFloat((pt.y - pRefPoint?.y) * PATH_SCALING)), transform: .identity)
                }
            }
        }
        return path
    }

    override func shapePathForObject(withRefPoint pRefPoint: OSMPoint?) -> CGPath? {
        return OsmWay.shapePath(forNodes: nodes, forward: isClockwise(), withRefPoint: pRefPoint)
    }

    func hasDuplicatedNode() -> Bool {
        var prev: OsmNode? = nil
        for node in nodes ?? [] {
            if node == prev {
                return true
            }
            prev = node
        }
        return false
    }

    func connects(to way: OsmWay?) -> OsmNode? {
        if (nodes?.count ?? 0) > 0 && (way?.nodes?.count ?? 0) > 0 {
            if nodes?[0] == way?.nodes?[0] || nodes?[0] == way?.nodes?.last {
                return nodes?[0]
            }
            if nodes?.last == way?.nodes?[0] || nodes?.last == way?.nodes?.last {
                return nodes?.last
            }
        }
        return nil
    }

    func segmentClosest(to point: OSMPoint) -> Int {
        var best = -1
        var bestDist = 100000000.0
        for index in 0..<(nodes?.count ?? 0) {
            let this = nodes?[index]
            let next = nodes?[index + 1]
            let dist = DistanceFromPointToLineSegment(point, this?.location(), next?.location())
            if dist < bestDist {
                bestDist = dist
                best = index
            }
        }
        return best
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        nodes = coder.decodeObject(forKey: "nodes") as? [OsmNode]
        constructed = true
        if DEBUG {
        for node in nodes ?? [] {
            assert(node.wayCount > 0)
        }
        }
    }

    override func encode(with coder: NSCoder) {
        if DEBUG {
        for node in nodes ?? [] {
            assert(node.wayCount > 0)
        }
        }

        super.encode(with: coder)
        coder.encode(nodes, forKey: "nodes")
    }
}