//
//  QuadMap.swift
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 10/10/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

import Foundation

class QuadMap: NSObject, NSCoding {
    let rootQuad: QuadBox

    // MARK: Common

	override init() {
		rootQuad = QuadBox()
		super.init()
    }

    func countOfObjects() -> Int {
        return rootQuad.countOfObjects()
    }

	func isEmpty() -> Bool {
		return rootQuad.isEmpty()
	}

    func encode(with coder: NSCoder) {
        coder.encode(rootQuad, forKey: "rootQuad")
    }

    required init?(coder: NSCoder) {
		if let root = coder.decodeObject(forKey: "rootQuad") as? QuadBox {
			rootQuad = root
		} else {
			// we end up here when loading an old ObjC save that set the spatial rootQuad to nil
			// and then the undo manager has an action that references the spatial
			print("bad rootQuad")
			rootQuad = QuadBox()
		}
		super.init()
    }

    // MARK: Regions

    func mergeDerivedRegion(_ other: QuadMap, success: Bool) {
		DbgAssert(other.countOfObjects() == 1)
        makeWhole(other.rootQuad, success: success)
    }

    // Region
    func newQuads(forRect newRect: OSMRect) -> [QuadBox] {
		var newRect = newRect
		var quads: [QuadBox] = []

		assert(newRect.origin.x >= -180.0 && newRect.origin.x <= 180.0)
        if newRect.origin.x + newRect.size.width > 180 {
			let half = OSMRect( origin: OSMPoint(x: -180.0,
												 y: newRect.origin.y ),
								size: OSMSize(width: newRect.origin.x + newRect.size.width - 180.0,
											  height: newRect.size.height) )
			rootQuad.missingPieces(&quads, intersecting: half)
            newRect.size.width = 180 - newRect.origin.x
        }
		rootQuad.missingPieces(&quads, intersecting: newRect)
        return quads
    }

    func makeWhole(_ quad: QuadBox, success: Bool) {
		quad.makeWhole(success: success)
    }

    // MARK: Spatial

	@objc func addMember(_ member: OsmBaseObject, undo: MyUndoManager?) {
        if let undo = undo {
            undo.registerUndo(withTarget: self, selector: #selector(removeMember(_:undo:)), objects: [member, undo])
        }
        let boundingBox = member.boundingBox
		rootQuad.addMember(member, bbox: boundingBox)
    }

	@objc func removeMember(_ member: OsmBaseObject, undo: MyUndoManager?) -> Bool {
        let boundingBox = member.boundingBox
		let ok = rootQuad.removeMember(member, bbox: boundingBox)
        if ok && undo != nil {
            undo?.registerUndo(withTarget: self, selector: #selector(addMember(_:undo:)), objects: [member, undo as Any])
        }
        return ok
    }

    func updateMember(_ member: OsmBaseObject, toBox: OSMRect, fromBox: OSMRect, undo: MyUndoManager?) {
        var toBox = toBox
        var fromBox = fromBox
		if let fromQuad = rootQuad.getQuadBoxContaining(member, bbox: fromBox) {
			if fromQuad.rect.containsRect( toBox ) {
                // It fits in its current box. It might fit into a child, but this path is rare and not worth optimizing.
                return
            }
            fromQuad.removeMember(member, bbox: fromBox)
            rootQuad.addMember(member, bbox: toBox)
            if let undo = undo {
				let toData = Data(bytes: &toBox, count: MemoryLayout.size(ofValue: toBox))
				let fromData = Data(bytes: &fromBox, count: MemoryLayout.size(ofValue: fromBox))
                undo.registerUndo(withTarget: self, selector: #selector(updateMemberBoxed(_:toBox:fromBox:undo:)), objects: [member, fromData, toData, undo])
            }
        } else {
            rootQuad.addMember(member, bbox: toBox)
            if let undo = undo {
                undo.registerUndo(withTarget: self, selector: #selector(removeMember(_:undo:)), objects: [member, undo])
            }
        }
    }

    // This is just like updateMember but allows boxed arguments so the undo manager can call it
    @objc func updateMemberBoxed(_ member: OsmBaseObject, toBox: Data, fromBox: Data, undo: MyUndoManager?) {
		// FIXME: convert OSMRect to use Coder once OSMRect is a swift type
		let to: OSMRect = toBox.withUnsafeBytes( { return $0.load(as: OSMRect.self) } )
		let from: OSMRect = fromBox.withUnsafeBytes( { return $0.load(as: OSMRect.self) } )
		updateMember(member, toBox: to, fromBox: from, undo: undo)
    }

    // Spatial
    func updateMember(_ member: OsmBaseObject, fromBox bbox: OSMRect, undo: MyUndoManager?) {
        let boundingBox = member.boundingBox
		updateMember(member, toBox: boundingBox, fromBox: bbox, undo: undo)
    }

    func findObjects(inArea bbox: OSMRect, block: @escaping (OsmBaseObject) -> Void) {
        rootQuad.findObjects(inArea: bbox, block: block)
    }

	func enumerate( _ block: @escaping (OsmBaseObject,OSMRect) -> Void ) {
		rootQuad.enumerate( block )
	}

    // these are for purging old data:

    // MARK: Purge objects

    func discardQuadsOlderThanDate(_ date: Date) -> Bool {
        return rootQuad.discardQuadsOlderThanDate(date)
    }

    func discardOldestQuads(_ fraction: Double, oldest: Date) -> Date? {
		return rootQuad.discardOldestQuads(fraction: fraction, oldest: oldest)
    }

    func pointIsCovered(_ point: OSMPoint) -> Bool {
        return rootQuad.pointIsCovered(point)
    }

    func anyNodeIsCovered(_ nodeList: [OsmNode]) -> Bool {
		return rootQuad.anyNodeIsCovered(nodeList: nodeList)
    }

    func deleteObjects(withPredicate predicate: @escaping (_ obj: OsmBaseObject) -> Bool) {
		rootQuad.deleteObjects(withPredicate: predicate)
    }

    func consistencyCheck(nodes: [OsmNode], ways: [OsmWay], relations: [OsmRelation]) {
        // check that every object appears exactly once in the object tree
		var dict: [OsmExtendedIdentifier : Int] = [:]
		var nCount = 0
		var wCount = 0
		var rCount = 0
		rootQuad.enumerate { obj, rect in
			assert( !(rect == .zero))
			let id = obj.extendedIdentifier
			if let cnt = dict[id] {
				dict[id] = cnt + 1
			} else {
				dict[id] = 1
			}
			assert( rect.containsRect( obj.boundingBox ) )
			if obj is OsmNode { nCount += 1 }
			if obj is OsmWay { wCount += 1 }
			if obj is OsmRelation { rCount += 1 }
		}
		assert( dict.first(where: {$0.value != 1}) == nil )
		assert( nCount == nodes.lazy.filter({!$0.deleted}).count )
		assert( wCount == ways.lazy.filter({!$0.deleted}).count )
		assert( rCount == relations.lazy.filter({!$0.deleted}).count )
    }
}
