//
//  OsmWay.swift
//  Go Map!!
//
//  Created by Wolfgang Timme on 1/18/20.
//  Copyright © 2020 Bryce Cogswell. All rights reserved.
//

import UIKit

final class OsmWay: OsmBaseObject {
	var nodeRefs: [OsmIdentifier]? // only used during construction
	private(set) var nodes: [OsmNode]

	override var description: String {
		return "OsmWay \(super.description)"
	}

	func nodeRefCount() -> Int {
		return nodeRefs?.count ?? 0
	}

	func constructNode(_ node: Int64) {
		assert(!_constructed && nodes.isEmpty)
		let ref = OsmIdentifier(node)
		assert(ref > 0)
		if nodeRefs == nil {
			nodeRefs = [ref]
		} else {
			nodeRefs!.append(ref)
		}
	}

	func constructNodeList(_ nodes: [OsmIdentifier]) {
		assert(!_constructed)
		nodeRefs = nodes
	}

	override func isWay() -> OsmWay? {
		return self
	}

	func resolveToMapData(_ mapData: OsmMapData) throws {
		guard let nodeRefs = nodeRefs else { throw NSError() }
		assert(nodes.count == 0)
		nodes.reserveCapacity(nodeRefs.count)
		for ref in nodeRefs {
			guard let node = mapData.nodes[ref] else { throw NSError() }
			nodes.append(node)
			node.setWayCount(node.wayCount + 1, undo: nil)
		}
		self.nodeRefs = nil
	}

	@objc func removeNodeAtIndex(_ index: Int, undo: MyUndoManager) {
		let node = nodes[index]
		incrementModifyCount(undo)
		undo.registerUndo(
			withTarget: self,
			selector: #selector(addNode(_:atIndex:undo:)),
			objects: [node, NSNumber(value: index), undo])
		nodes.remove(at: index)
		node.setWayCount(node.wayCount - 1, undo: nil)
		computeBoundingBox()
	}

	@objc func addNode(_ node: OsmNode, atIndex index: Int, undo: MyUndoManager?) {
		if _constructed {
			assert(undo != nil)
			incrementModifyCount(undo)
			undo!.registerUndo(
				withTarget: self,
				selector: #selector(removeNodeAtIndex(_:undo:)),
				objects: [NSNumber(value: index), undo!])
		}
		nodes.insert(node, at: index)
		node.setWayCount(node.wayCount + 1, undo: nil)
		computeBoundingBox()
	}

	override func serverUpdate(inPlace newerVersion: OsmBaseObject) {
		super.serverUpdate(inPlace: newerVersion)
		nodeRefs = (newerVersion as! OsmWay).nodeRefs
		nodes = (newerVersion as! OsmWay).nodes
	}

	func isArea() -> Bool {
		return PresetsDatabase.shared.isArea(self)
	}

	func isClosed() -> Bool {
		return nodes.count > 2 && nodes[0] == nodes.last
	}

	static let computeIsOneWayOneWayTags: [String: [String: Bool]] = [
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
		]
	]

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
		for (tag, value) in tags {
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
			if parent.isMultipolygon(), !parent.tags.isEmpty {
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
		      first + 1 < nodes.count
		else { return false }

		if nodes[(first + 1)...].contains(node) {
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

	private var _isOneWay: ONEWAY?
	var isOneWay: ONEWAY {
		if _isOneWay == nil {
			_isOneWay = self.computeIsOneWay()
		}
		return _isOneWay!
	}

	// return the point on the way closest to the supplied point
	override func latLonOnObject(forLatLon target: LatLon) -> LatLon {
		switch nodes.count {
		case 0:
			return target
		case 1:
			return nodes.last!.latLon
		default:
			break
		}
		let target = OSMPoint(target)
		var bestPoint = OSMPoint(x: 0, y: 0)
		var bestDist = Double.greatestFiniteMagnitude
		for i in 1..<nodes.count {
			let p1 = nodes[i - 1].location()
			let p2 = nodes[i].location()
			let linePoint = target.nearestPointOnLineSegment(lineA: p1, lineB: p2)
			let dist = MagSquared(Sub(linePoint, target))
			if dist < bestDist {
				bestDist = dist
				bestPoint = linePoint
			}
		}
		return LatLon(bestPoint)
	}

	override func distance(toLineSegment point1: OSMPoint, point point2: OSMPoint) -> Double {
		if nodes.count == 1 {
			return nodes.last!.distance(toLineSegment: point1, point: point2)
		}
		var dist = 1000000.0
		var prevNode: OsmNode?
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
		return Set<OsmNode>(nodes)
	}

	override func computeBoundingBox() {
		guard let firstLatLon = nodes.first?.location() else {
			_boundingBox = OSMRect.zero
			return
		}
		let first = firstLatLon

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

	func centerPointWithArea(_ pArea: inout Double) -> LatLon {
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
					let current = OSMPoint(x: node.latLon.lon - offset.x,
					                       y: node.latLon.lat - offset.y)
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
				return LatLon(point)
			} else {
				// compute average
				var sumX: Double = 0
				var sumY: Double = 0
				for node in nodes {
					sumX += node.latLon.lon
					sumY += node.latLon.lat
				}
				let point = OSMPoint(x: sumX / Double(nodeCount), y: sumY / Double(nodeCount))
				return LatLon(point)
			}
		} else if nodeCount == 2 {
			pArea = 0.0
			let n1 = nodes[0]
			let n2 = nodes[1]
			return LatLon(x: (n1.latLon.lon + n2.latLon.lon) / 2,
			              y: (n1.latLon.lat + n2.latLon.lat) / 2)
		} else if nodeCount == 1 {
			pArea = 0.0
			let node = nodes.last!
			return node.latLon
		} else {
			pArea = 0.0
			let pt = LatLon.zero
			return pt
		}
	}

	func centerPoint() -> LatLon {
		var area: Double = 0.0
		return centerPointWithArea(&area)
	}

	func lengthInMeters() -> Double {
		var first = true
		var len: Double = 0
		var prev = LatLon.zero
		for node in nodes {
			let pt = node.latLon
			if !first {
				len += GreatCircleDistance(pt, prev)
			}
			first = false
			prev = pt
		}
		return len
	}

	// pick a point close to the center of the way
	override func selectionPoint() -> LatLon {
		var dist = lengthInMeters() / 2
		var first = true
		var prev = OSMPoint.zero
		for node in nodes {
			let pt = node.location()
			if !first {
				let segment = GreatCircleDistance(LatLon(pt), LatLon(prev))
				if segment >= dist {
					let pos = Add(prev, Mult(Sub(pt, prev), dist / segment))
					return LatLon(pos)
				}
				dist -= segment
			}
			first = false
			prev = pt
		}
		return LatLon(prev) // dummy value, shouldn't ever happen
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
			let current = Sub(point, offset)
			sum += previous.x * current.y - previous.y * current.x
			previous = current
		}
		return sum >= 0
	}

	func isClockwise() -> Bool {
		return OsmWay.isClockwiseArrayOfNodes(nodes)
	}

	class func shapePath(
		forNodes nodes: [OsmNode],
		forward: Bool,
		withRefPoint pRefPoint: UnsafeMutablePointer<OSMPoint>) -> CGPath?
	{
		if nodes.count == 0 || nodes[0] != nodes.last {
			return nil
		}
		let path = CGMutablePath()
		var first = true
		// want loops to run clockwise
		for n in forward ? nodes : nodes.reversed() {
			let pt = MapTransform.mapPoint(forLatLon: n.latLon)
			if first {
				first = false
				pRefPoint.pointee = pt
				path.move(to: CGPoint(x: 0, y: 0))
			} else {
				path.addLine(to: CGPoint(x: CGFloat((pt.x - pRefPoint.pointee.x) * PATH_SCALING),
				                         y: CGFloat((pt.y - pRefPoint.pointee.y) * PATH_SCALING)))
			}
		}
		return path
	}

	override func shapePathForObject(withRefPoint pRefPoint: UnsafeMutablePointer<OSMPoint>) -> CGPath? {
		return OsmWay.shapePath(forNodes: nodes, forward: isClockwise(), withRefPoint: pRefPoint)
	}

	func hasDuplicatedNode() -> Bool {
		var prev: OsmNode?
		for node in nodes {
			if node == prev {
				return true
			}
			prev = node
		}
		return false
	}

	func connectsTo(way: OsmWay) -> OsmNode? {
		if nodes.count > 0, way.nodes.count > 0 {
			if nodes[0] == way.nodes[0] || nodes[0] == way.nodes.last! {
				return nodes[0]
			}
			if nodes.last! == way.nodes[0] || nodes.last == way.nodes.last! {
				return nodes.last
			}
		}
		return nil
	}

	func segmentClosestToPoint(_ point: LatLon) -> Int {
		let point = OSMPoint(point)
		var best = -1
		var bestDist: Double = 100000000.0
		for index in nodes.indices.dropLast() {
			let this = nodes[index]
			let next = nodes[index + 1]
			let dist = point.distanceToLineSegment(this.location(), next.location())
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

	override init(
		withVersion version: Int,
		changeset: Int64,
		user: String,
		uid: Int,
		ident: Int64,
		timestamp: String,
		tags: [String: String])
	{
		nodes = []
		super.init(
			withVersion: version,
			changeset: changeset,
			user: user,
			uid: uid,
			ident: ident,
			timestamp: timestamp,
			tags: tags)
	}

	convenience init(asUserCreated userName: String) {
		let ident = OsmBaseObject.nextUnusedIdentifier()
		self.init(withVersion: 1, changeset: 0, user: userName, uid: 0, ident: ident, timestamp: "", tags: [:])
	}

	override init?(fromXmlDict attributeDict: [String: Any]) {
		nodes = []
		super.init(fromXmlDict: attributeDict)
	}

	override func encode(with coder: NSCoder) {
#if DEBUG
		for node in nodes {
			if node.wayCount == 0 {
				print("way \(ident) @ \(address()) nodes = \(nodes.count)")
				print("node \(node.ident) @ \(node.address()) waycount = \(node.wayCount)")
				assert(node.wayCount > 0)
			}
		}
#endif
		super.encode(with: coder)
		coder.encode(nodes, forKey: "nodes")
	}
}
