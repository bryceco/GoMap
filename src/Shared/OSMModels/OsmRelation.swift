//
//  OsmRelation.swift
//  Go Map!!
//
//  Created by Wolfgang Timme on 1/18/20.
//  Copyright © 2020 Bryce Cogswell. All rights reserved.
//

import UIKit

// This class is used as a temporary object while reading relations from Sqlite3 and building member lists
final class OsmRelationBuilder: NSObject {
	var relation: OsmRelation
	var members: [OsmMember?]
	init(with relation: OsmRelation, memberCount: Int ) {
		self.relation = relation
		self.members = Array<OsmMember?>(repeating: nil, count: memberCount)
	}
}

@objcMembers
final class OsmRelation: OsmBaseObject {
    private(set) var members: [OsmMember]

    override var description: String {
        return "OsmRelation \(super.description)"
    }

	func constructMember(_ member: OsmMember) {
		assert(!_constructed)
		assert(member.obj == nil)
		members.append( member )
	}
	func constructMembers(_ members: [OsmMember]) {
		assert(!_constructed)
		assert(members.first == nil || members.first!.obj == nil)	// things added here shouldn't be resolved yet
		self.members = members
	}

    override func isRelation() -> OsmRelation? {
		return self
    }

	private func forAllMemberObjectsRecurse(_ callback: @escaping (OsmBaseObject) -> Void, relations: inout Set<OsmRelation>) {
		for member in members {
			if let obj = member.obj {
				if let rel = obj.isRelation() {
					if relations.contains(rel) {
						// already processed
					} else {
						callback(obj)
						relations.insert(rel)
						rel.forAllMemberObjectsRecurse(callback, relations: &relations)
					}
                } else {
					callback(obj)
                }
            }
        }
    }

    func forAllMemberObjects(_ callback: @escaping (OsmBaseObject) -> Void) {
		var relations = Set<OsmRelation>( [self] )
		forAllMemberObjectsRecurse(callback, relations: &relations)
    }

    func allMemberObjects() -> Set<OsmBaseObject> {
		var objects: Set<OsmBaseObject> = []
		forAllMemberObjects({ obj in
			objects.insert(obj)
		})
        return objects
    }

    func resolveToMapData(_ mapData: OsmMapData) -> Bool {
        var needsRedraw = false
        for member in members {
			if member.obj != nil {
				// already resolved
				continue
			}

            if member.isWay() {
				if let way = mapData.ways[member.ref] {
					member.resolveRef(to: way)
					way.addParentRelation(self, undo: nil)
					needsRedraw = true
                } else {
                    // way is not in current view
                }
            } else if member.isNode() {
				if let node = mapData.nodes[member.ref] {
					member.resolveRef(to: node)
					node.addParentRelation(self, undo: nil)
					needsRedraw = true
                } else {
					// node is not in current view
                }
            } else if member.isRelation() {
				if let rel = mapData.relations[member.ref] {
					member.resolveRef(to: rel)
					rel.addParentRelation(self, undo: nil)
                    needsRedraw = true
                } else {
                    // relation is not in current view
                }
            } else {
                assert(false)
            }
        }
        if needsRedraw {
            clearCachedProperties()
        }
        return needsRedraw
    }

    // convert references to objects back to NSNumber
    func deresolveRefs() {
        for member in members {
			if let obj = member.obj {
				assert( member.ref == obj.ident )
				obj.removeParentRelation(self, undo: nil)
			}
        }
    }

    @objc func assignMembers(_ newMembers: [OsmMember], undo: MyUndoManager?) {
        if _constructed {
            assert(undo != nil)
			incrementModifyCount(undo!)
            undo!.registerUndo(withTarget: self, selector: #selector(assignMembers(_:undo:)), objects: [self.members, undo!])
		}

        // figure out which members changed and update their relation parents
		var old = Set<OsmBaseObject>( self.members.compactMap({ $0.obj }) )
		var new = Set<OsmBaseObject>( newMembers.compactMap({ $0.obj }) )
		let common = old.intersection(new)
		new.subtract(common)	// added items
		old.subtract(common)    // removed items
		for obj in old {
			obj.removeParentRelation(self, undo:nil)
		}
		for obj in new {
			obj.addParentRelation(self, undo:nil)
		}
        self.members = newMembers
    }

    @objc func removeMemberAtIndex(_ index: Int, undo: MyUndoManager) {
        let member = members[index]
        incrementModifyCount(undo)
        undo.registerUndo(withTarget: self, selector: #selector(addMember(_:atIndex:undo:)), objects: [member, NSNumber(value: index), undo])
        members.remove(at: index)
		if let obj = member.obj {
			obj.removeParentRelation(self, undo: nil)
		}
    }

	@objc func addMember(_ member: OsmMember, atIndex index: Int, undo: MyUndoManager?) {
		if _constructed {
            assert(undo != nil)
            incrementModifyCount(undo!)
            undo!.registerUndo(withTarget: self, selector: #selector(removeMemberAtIndex(_:undo:)), objects: [NSNumber(value: index), undo!])
		}
		members.insert(member, at: index)
		if let obj = member.obj {
			obj.addParentRelation(self, undo: nil)
		}
    }

    override func serverUpdate(inPlace newerVersion: OsmBaseObject) {
		let newerVersion = newerVersion as! OsmRelation
		super.serverUpdate(inPlace: newerVersion)
        members = newerVersion.members
    }

    override func computeBoundingBox() {
		let objects = allMemberObjects()
		let boxList: [OSMRect] = objects.compactMap({ obj in
			if obj is OsmRelation {
				return nil // child members have already been added to the set
			}
			let rc = obj.boundingBox
			if rc.origin.x == 0 && rc.origin.y == 0 && rc.size.height == 0 && rc.size.width == 0 {
				return nil
			}
			return rc
		})
		if var box = boxList.first {
			for rc in boxList.dropFirst() {
				box = box.union(rc)
			}
			_boundingBox = box
			assert( !(_boundingBox! == .zero) )
		} else {
			_boundingBox = OSMRect.zero
		}
	}

    override func nodeSet() -> Set<OsmNode> {
		var set: Set<OsmNode> = []
		for obj in allMemberObjects() {
			if let node = obj as? OsmNode {
				set.insert(node)
			} else if let way = obj as? OsmWay {
				set.formUnion(Set(way.nodes))
			} else {
				// relations have already been expanded into member nodes/ways
			}
		}
		return set
    }

    func member(byRole role: String?) -> OsmMember? {
        for member in members {
            if member.role == role {
                return member
            }
        }
        return nil
    }

    func members(byRole role: String) -> [OsmMember] {
		return members.filter { $0.role == role }
    }

    func member(byRef ref: OsmBaseObject) -> OsmMember? {
		return members.first(where: { $0.obj == ref } )
    }

    func isMultipolygon() -> Bool {
		let type = tags["type"]
		return type == "multipolygon" || type == "building"
    }

    func isBoundary() -> Bool {
		return tags["type"] == "boundary"
    }

    func isWaterway() -> Bool {
        return tags["type"] == "waterway"
    }

    func isRoute() -> Bool {
        return tags["type"] == "route"
    }

    func isRestriction() -> Bool {
		if let type = tags["type"] {
			return type == "restriction" || type.hasPrefix("restriction:")
		}
		return false
    }

    func waysInMultipolygon() -> [OsmWay] {
		if !isMultipolygon() {
			return []
		}
		return members.compactMap({ mem in
			if mem.role == "outer" || mem.role == "inner" {
				return mem.obj as? OsmWay
			}
			return nil
		})
    }

    static func buildMultipolygonFromMembers(_ memberList: [OsmMember],
											 repairing: Bool,
											 isComplete: UnsafeMutablePointer<ObjCBool>) -> [[OsmNode]]
	{
		var loopList: [[OsmNode]] = []
        var loop: [OsmNode] = []
        var members = memberList.filter({ ($0.obj is OsmWay) && ($0.role == "outer" || $0.role == "inner") })

		var isInner = false
        var foundAdjacent = false

		isComplete.pointee = ObjCBool( members.count == memberList.count )

		while !members.isEmpty {
			if loop.isEmpty {
				// add a member to loop
				let member = members.popLast()!
				isInner = member.role == "inner"
				let way = member.obj as! OsmWay
				loop = way.nodes
				foundAdjacent = true
            } else {
                // find adjacent way
                foundAdjacent = false
				for i in members.indices {
					let member = members[i]
                    if (member.role == "inner") != isInner {
						continue
					}
					let way = member.obj as! OsmWay
					let enumerator = (way.nodes[0] == loop.last!) ? way.nodes.makeIterator()
						: (way.nodes.last! == loop.last!) ? way.nodes.reversed().makeIterator()
						: nil
                    if let enumerator = enumerator {
                        foundAdjacent = true
                        var first = true
                        for n in enumerator {
							if first {
                                first = false
                            } else {
								loop.append(n)
                            }
                        }
                        members.remove(at: i)
						break
                    }
                }
                if !foundAdjacent && repairing {
                    // invalid, but we'll try to continue
					isComplete.pointee = false
					// force-close the loop
					loop.append( loop[0] )
                }
            }

            if loop.count != 0 && (loop.last! == loop[0] || !foundAdjacent) {
                // finished a loop. Outer goes clockwise, inner goes counterclockwise
				if OsmWay.isClockwiseArrayOfNodes(loop) == isInner {
					loopList.append( loop.reversed() )
				} else {
					loopList.append( loop )
				}
				loop = []
            }
        }
        return loopList
    }

    func buildMultipolygonRepairing(_ repairing: Bool) -> [[OsmNode]] {
		if !isMultipolygon() {
			return []
        }
		var isComplete: ObjCBool = true
        let a = OsmRelation.buildMultipolygonFromMembers( members,
														  repairing: repairing,
														  isComplete: &isComplete)
		return a
    }

    override func shapePathForObject(withRefPoint pRefPoint: UnsafeMutablePointer<OSMPoint>) -> CGPath? {
        let loopList = buildMultipolygonRepairing(true)
		if loopList.isEmpty {
            return nil
        }

        let path = CGMutablePath()
        var refPoint: OSMPoint? = nil

		for loop in loopList {
			var first = true
            for n in loop {
				let pt = MapTransform.mapPoint(forLatLon: n.latLon)
				if first {
                    first = false
					if refPoint == nil {
						refPoint = pt
                    }
                    path.move(to: CGPoint(x: CGFloat((pt.x - refPoint!.x) * PATH_SCALING),
										  y: CGFloat((pt.y - refPoint!.y) * PATH_SCALING)))
                } else {
                    path.addLine(to: CGPoint(x: CGFloat((pt.x - refPoint!.x) * PATH_SCALING),
											 y: CGFloat((pt.y - refPoint!.y) * PATH_SCALING)))
				}
            }
        }
		pRefPoint.pointee = refPoint!
		return path
    }

    func centerPoint() -> LatLon {
		let outerSet: [OsmWay] = members.compactMap({
			if $0.role == "outer" {
				return $0.obj as? OsmWay
			}
			return nil
		})
        if outerSet.count == 1 {
            return outerSet[0].centerPoint()
        } else {
			let rc = self.boundingBox
			return LatLon(x: rc.origin.x + rc.size.width / 2,
						  y: rc.origin.y + rc.size.height / 2)
        }
    }

    override func selectionPoint() -> LatLon {
		let bbox = self.boundingBox
		let center = LatLon(x: bbox.origin.x + bbox.size.width / 2,
							y: bbox.origin.y + bbox.size.height / 2)
		if isMultipolygon() {
            // pick a point on an outer polygon that is close to the center of the bbox
            for member in members {
                if member.role == "outer",
				   let way = member.obj as? OsmWay,
				   way.nodes.count > 0
				{
					return way.pointOnObjectForPoint( center )
                }
            }
        }
        if isRestriction() {
            // pick via node or way
            for member in members {
                if member.role == "via",
				   let object = member.obj
				{
					if object is OsmNode || object is OsmWay {
						return object.selectionPoint()
					}
                }
            }
        }
        // choose any node/way member
        let all = allMemberObjects() // might be a super relation, so need to recurse down
		if let object = all.first {
			return object.selectionPoint()
		}
		return center	// this is a failure condition
    }

    override func distance(toLineSegment point1: OSMPoint, point point2: OSMPoint) -> Double {
        var dist = 1000000.0
        for member in members {
			if let object = member.obj {
				if object.isRelation() == nil {
					let d = object.distance(toLineSegment: point1, point: point2)
					if d < dist {
						dist = d
					}
				}
			}
        }
        return dist
    }

	override func pointOnObjectForPoint(_ target: LatLon) -> LatLon {
		var bestPoint = target
        var bestDistance = 10000000.0
        for object in allMemberObjects() {
            let pt = object.pointOnObjectForPoint( target )
			let dist = OSMPoint(target).distanceToPoint( OSMPoint(pt) )
            if dist < bestDistance {
                bestDistance = dist
                bestPoint = pt
            }
        }
        return bestPoint
    }

    func containsObject(_ target: OsmBaseObject) -> Bool {
        let set = allMemberObjects()
        for obj in set {
			if obj == target {
                return true
            }
			if let way = obj as? OsmWay,
			   let node = target as? OsmNode,
			   way.nodes.contains(node)
			{
				return true
			}
		}
		return false
    }

    override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(members, forKey: "members")
    }

	override init(withVersion version: Int, changeset: Int64, user: String, uid: Int, ident: Int64, timestamp: String, tags: [String:String]) {
		self.members = []
		super.init(withVersion: version, changeset: changeset, user: user, uid: uid, ident: ident, timestamp: timestamp, tags: tags)
	}

	convenience init(asUserCreated userName: String) {
		let ident = OsmBaseObject.nextUnusedIdentifier()
		self.init(withVersion: 1, changeset: 0, user: userName, uid: 0, ident: ident, timestamp: "", tags: [:])
	}

	override init?(fromXmlDict attributeDict: [String : Any]) {
		self.members = []
		super.init(fromXmlDict: attributeDict)
	}

	required init?(coder: NSCoder) {
		members = coder.decodeObject(forKey: "members") as! [OsmMember]
		super.init(coder: coder)
		_constructed = true
    }
}
