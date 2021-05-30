//
//  OsmWay.swift
//  Go Map!!
//
//  Created by Wolfgang Timme on 1/18/20.
//  Copyright © 2020 Bryce. All rights reserved.
//

final class OsmWay: OsmBaseObject {
	var nodeRefs: [OsmIdentifier]?	// only used during construction
	private(set) var nodes: [OsmNode]

	override var description: String {
        return "OsmWay \(super.description)"
    }

	func nodeRefCount() -> Int {
		return nodeRefs?.count ?? 0
	}

	func constructNode(_ node: NSNumber) {
		assert(!self._constructed && nodes.isEmpty)
		let ref = OsmIdentifier( node.int64Value )
		assert( ref > 0 )
		if nodeRefs == nil {
			self.nodeRefs = [ref]
		} else {
			self.nodeRefs!.append(ref)
		}
    }

    func constructNodeList(_ nodes: [NSNumber]) {
		assert(!self._constructed)
		self.nodeRefs = nodes.map({ OsmIdentifier($0.int64Value) })
	}

    override func isWay() -> OsmWay? {
		return self
    }

    func resolveToMapData(_ mapData: OsmMapData) {
		guard let nodeRefs = nodeRefs else { fatalError() }
		assert( nodes.count == 0 )
		nodes.reserveCapacity(nodeRefs.count)
		for ref in nodeRefs {
			guard let node = mapData.node(forRef: ref) else { fatalError() }
			nodes.append( node )
			node.setWayCount(node.wayCount + 1, undo: nil)
		}
		self.nodeRefs = nil
	}

	@objc func removeNodeAtIndex(_ index: Int, undo: MyUndoManager) {
        let node = nodes[index]
        incrementModifyCount(undo)
        undo.registerUndo(withTarget: self, selector: #selector(addNode(_:atIndex:undo:)), objects: [node, NSNumber(value: index), undo])
        nodes.remove(at: index)
        node.setWayCount(node.wayCount - 1, undo: nil)
		computeBoundingBox()
    }

    @objc func addNode(_ node: OsmNode, atIndex index: Int, undo: MyUndoManager?) {
        if _constructed {
            assert(undo != nil)
            incrementModifyCount(undo)
			undo!.registerUndo(withTarget: self, selector: #selector(removeNodeAtIndex(_:undo:)), objects: [NSNumber(value: index), undo!])
		}
		nodes.insert(node, at: index)
        node.setWayCount(node.wayCount + 1, undo: nil)
		computeBoundingBox()
    }

    override func serverUpdate(inPlace newerVersion: OsmBaseObject) {
        super.serverUpdate(inPlace: newerVersion)
        nodes = (newerVersion as! OsmWay).nodes
    }

    func isArea() -> Bool {
        return PresetsDatabase.shared.isArea(self)
    }

    func isClosed() -> Bool {
        return nodes.count > 2 && nodes[0] == nodes.last
	}

	static let computeIsOneWayOneWayTags: [String : [String:Bool]] = [
		"aerialway": [
			"chair_lift": true,
			"mixed_lift": true,
			"t-bar": true,
			"j-bar": true,
			"platter": true,
			"rope_tow": true,
			"magic_carpet": true,
			"yes": true
		],
		"highway": [
			"motorway": true,
			"motorway_link": true,
			"steps": true
		],
		"junction": [
			"roundabout": true
		],
		"man_made": [
			"piste:halfpipe": true,
			"embankment": true
		],
		"natural": [
			"cliff": true,
			"coastline": true
		],
		"piste:type": [
			"downhill": true,
			"sled": true,
			"yes": true
		],
		"waterway": [
			"brook": true,
			"canal": true,
			"ditch": true,
			"drain": true,
			"fairway": true,
			"river": true,
			"stream": true,
			"weir": true
		]]

    func computeIsOneWay() -> ONEWAY {
		if let oneWayVal = tags["oneway"] {
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
		for (tag,value) in tags {
			if let valueDict = OsmWay.computeIsOneWayOneWayTags[tag],
				valueDict[value] != nil
			{
				return ._FORWARD
            }
        }
		return ._NONE
    }

    func sharesNodes(with way: OsmWay) -> Bool {
        if nodes.count * way.nodes.count < 100 {
			for n in way.nodes {
                if nodes.contains(n) {
                    return true
                }
            }
            return false
        } else {
			let set1 = Set<NSObject>(way.nodes)
            let set2 = Set<NSObject>(nodes)
			return !set1.isDisjoint(with: set2)
		}
	}

    func isMultipolygonMember() -> Bool {
        for parent in parentRelations {
			if parent.isMultipolygon() && !parent.tags.isEmpty {
				return true
            }
        }
        return false
    }

    func isSimpleMultipolygonOuterMember() -> Bool {
        if parentRelations.count != 1 {
            return false
        }

        let parent = parentRelations[0]
        if !parent.isMultipolygon() {
			return false
        }

        for member in parent.members {
            if member.obj === self {
                if member.role != "outer" {
					return false // Not outer member
                }
            } else {
                if member.role == nil || member.role == "outer" {
					return false // Not a simple multipolygon
                }
            }
        }
        return true
    }

    func isSelfIntersection(_ node: OsmNode) -> Bool {
		if nodes.count < 3 {
            return false
        }
		guard let first = nodes.firstIndex(of: node),
			  first+1 < nodes.count
		else { return false }

		if nodes[(first+1)...].contains(node) {
			return true
        }
		return false
	}

    func needsNoNameHighlight() -> Bool {
		guard let highway = tags["highway"] else { return false }
		if highway == "service" {
			return false
        }
		if givenName() != nil {
            return false
        }
		if tags["noname"] == "yes" {
			return false
        }
        return true
    }

    func wayArea() -> Double {
        assert(false)
        return 0
    }

    // return the point on the way closest to the supplied point
	override func pointOnObjectForPoint(_ target: OSMPoint) -> OSMPoint {
        switch nodes.count {
            case 0:
                return target
            case 1:
                return nodes.last!.location()
            default:
                break
        }
		var bestPoint = OSMPoint(x: 0, y: 0)
        var bestDist: Double = 360 * 360
        for i in 1..<nodes.count {
            let p1 = nodes[i-1].location()
            let p2 = nodes[i].location()
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
        if nodes.count == 1 {
			return nodes.last!.distance(toLineSegment: point1, point: point2)
		}
        var dist = 1000000.0
        var prevNode: OsmNode? = nil
        for node in nodes {
            if let prevNode = prevNode,
			   LineSegmentsIntersect(prevNode.location(), node.location(), point1, point2)
			{
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

    override func nodeSet() -> Set<OsmNode> {
        return Set<OsmNode>( nodes )
    }

    override func computeBoundingBox() {
		guard let first = nodes.first?.location() else {
			_boundingBox = OSMRect.zero
			return
		}

		var minX = first.x
		var maxX = first.x
		var minY = first.y
		var maxY = first.y
		for node in nodes.dropFirst() {
			let loc = node.location()
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
		_boundingBox = OSMRect(origin: OSMPoint(x: minX, y: minY),
							   size: OSMSize(width: maxX - minX, height: maxY - minY))
    }

    func centerPointWithArea(_ pArea: inout Double) -> OSMPoint {
        let isClosed = self.isClosed()

        let nodeCount = isClosed ? nodes.count - 1 : nodes.count

		if nodeCount > 2 {
            if isClosed {
                // compute centroid
                var sum: Double = 0
                var sumX: Double = 0
                var sumY: Double = 0
				let offset = nodes.first!.location()
				var previous = OSMPoint(x: 0.0, y: 0.0)
				for node in nodes.dropFirst() {
					let current = OSMPoint(x: node.lon - offset.x,
										   y: node.lat - offset.y)
					let partialSum = previous.x * current.y - previous.y * current.x
					sum += partialSum
					sumX += (previous.x + current.x) * partialSum
					sumY += (previous.y + current.y) * partialSum
					previous = current
                }
				pArea = sum / 2
				var point = OSMPoint(x: sumX / 6 / pArea, y: sumY / 6 / pArea)
                point.x += offset.x
				point.y += offset.y
                return point
            } else {
                // compute average
                var sumX: Double = 0
                var sumY: Double = 0
                for node in nodes {
                    sumX += node.lon
                    sumY += node.lat
                }
				let point = OSMPoint(x: sumX / Double(nodeCount), y: sumY / Double(nodeCount))
                return point
            }
        } else if nodeCount == 2 {
			pArea = 0.0
			let n1 = nodes[0]
            let n2 = nodes[1]
			return OSMPoint(x: (n1.lon + n2.lon) / 2, y: (n1.lat + n2.lat) / 2)
        } else if nodeCount == 1 {
			pArea = 0.0
			let node = nodes.last!
			return OSMPoint(x: node.lon, y: node.lat)
        } else {
			pArea = 0.0
			let pt = OSMPoint(x: 0, y: 0)
            return pt
        }
    }

    func centerPoint() -> OSMPoint {
		var area: Double = 0.0
        return centerPointWithArea( &area )
	}

    func lengthInMeters() -> Double {
        var first = true
        var len: Double = 0
		var prev = OSMPoint(x: 0, y: 0)
        for node in nodes {
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
		var prev = OSMPoint(x: 0, y: 0)
        for node in nodes {
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

    class func isClockwiseArrayOfNodes(_ nodes: [OsmNode]) -> Bool {
        if nodes.count < 4 || nodes[0] != nodes.last {
			return false
        }
        var sum: Double = 0
		let offset = nodes.first!.location()
		var previous = OSMPoint(x: 0.0, y: 0.0)
		for node in nodes.dropFirst() {
			let point = node.location()
			let current = OSMPoint(x: point.x - offset.x, y: point.y - offset.y)
			sum += previous.x * current.y - previous.y * current.x
			previous = current
        }
        return sum >= 0
    }

    func isClockwise() -> Bool {
        return OsmWay.isClockwiseArrayOfNodes(nodes)
    }

    class func shapePath(forNodes nodes: [OsmNode], forward: Bool, withRefPoint pRefPoint: UnsafeMutablePointer<OSMPoint>) -> CGPath? {
		if nodes.count == 0 || nodes[0] != nodes.last {
			return nil
		}
        let path = CGMutablePath()
        var first = true
        // want loops to run clockwise
		for n in forward ? nodes : nodes.reversed() {
			let pt = MapPointForLatitudeLongitude(n.lat, n.lon)
			if first {
				first = false
				pRefPoint.pointee = pt
				path.move(to: CGPoint(x: 0, y: 0), transform: .identity)
			} else {
				path.addLine(to: CGPoint(x: CGFloat((pt.x - pRefPoint.pointee.x) * PATH_SCALING), y: CGFloat((pt.y - pRefPoint.pointee.y) * PATH_SCALING)), transform: .identity)
			}
		}
        return path
    }

    override func shapePathForObject( withRefPoint pRefPoint: UnsafeMutablePointer<OSMPoint> ) -> CGPath? {
		return OsmWay.shapePath(forNodes: nodes, forward: isClockwise(), withRefPoint: pRefPoint)
    }

    func hasDuplicatedNode() -> Bool {
        var prev: OsmNode? = nil
        for node in nodes {
            if node == prev {
                return true
            }
            prev = node
        }
        return false
    }

    func connectsTo(way: OsmWay) -> OsmNode? {
		if nodes.count > 0 && way.nodes.count > 0 {
            if nodes[0] == way.nodes[0] || nodes[0] == way.nodes.last! {
                return nodes[0]
            }
            if nodes.last! == way.nodes[0] || nodes.last == way.nodes.last! {
				return nodes.last
            }
        }
        return nil
    }

    func segmentClosestToPoint(_ point: OSMPoint) -> Int {
        var best = -1
		var bestDist: CGFloat = 100000000.0
		for index in nodes.indices.dropFirst() {
			let this = nodes[index]
            let next = nodes[index+1]
			let dist = DistanceFromPointToLineSegment(point, this.location(), next.location())
            if dist < bestDist {
                bestDist = dist
                best = index
            }
        }
        return best
    }

	required init?(coder: NSCoder) {
		nodes = coder.decodeObject(forKey: "nodes") as! [OsmNode]
        super.init(coder: coder)
		_constructed = true
		#if DEBUG
		for node in nodes {
			if node.wayCount == 0 {
				print("node \(node.ident) @ \(Unmanaged.passUnretained(node).toOpaque()) waycount = \(node.wayCount)")
				assert(node.wayCount > 0)
			}
		}
		#endif
    }

	override init(withVersion version: Int, changeset: Int64, user: String, uid: Int, ident: Int64, timestamp: String, tags: [String:String]) {
		self.nodes = []
		super.init(withVersion: version, changeset: changeset, user: user, uid: uid, ident: ident, timestamp: timestamp, tags: tags)
	}

	convenience init(asUserCreated userName: String) {
		let ident = OsmBaseObject.nextUnusedIdentifier()
		self.init(withVersion: 1, changeset: 0, user: userName, uid: 0, ident: ident, timestamp: "", tags: [:])
	}

	override init?(fromXmlDict attributeDict: [String : Any]) {
		self.nodes = []
		super.init(fromXmlDict: attributeDict)
	}

    override func encode(with coder: NSCoder) {
		#if DEBUG
		for node in nodes {
			if node.wayCount == 0 {
				print("way \(self.ident) @ \(self.address()) nodes = \(self.nodes.count)")
				print("node \(node.ident) @ \(node.address()) waycount = \(node.wayCount)")
				assert(node.wayCount > 0)
			}
		}
		#endif
		super.encode(with: coder)
		coder.encode(nodes, forKey: "nodes")
    }
}
