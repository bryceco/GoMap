//
//  QuadMap.swift
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 10/10/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

import Foundation


private let MAP_RECT = OSMRect(origin: OSMPoint(x:-180.0, y:-90.0),
							   size: OSMSize(width: 360.0, height: 180.0))

@objcMembers
class QuadMap: NSObject, NSCoding {
    var rootQuad: QuadBox

    // MARK: Common

    init(rect: OSMRect) {
		rootQuad = QuadBox(rect: rect)
        super.init()
    }

	override convenience init() {
        self.init(rect: MAP_RECT)
    }

    deinit {
        rootQuad.deleteCpp() // cpp has a strong reference to this so we need to reset it manually
    }

    func count() -> Int {
        return rootQuad.count()
    }

    func encode(with coder: NSCoder) {
        coder.encode(rootQuad, forKey: "rootQuad")
    }

    required init?(coder: NSCoder) {
		let ok = coder.containsValue(forKey: "rootQuad")
		assert(ok)
		guard let root = coder.decodeObject(forKey: "rootQuad") else {
			print("bad rootQuad")
			let _ = coder.decodeObject(forKey: "rootQuad")
			return nil
		}
		guard let root2 = root as? QuadBox else {
			print("bad rootQuad")
			return nil
		}
		rootQuad = root2
        super.init()
    }

    // MARK: Regions

    func mergeDerivedRegion(_ other: QuadMap, success: Bool) {
        assert(other.count() == 1)
        makeWhole(other.rootQuad, success: success)
    }

    // Region
    func newQuads(forRect newRect: OSMRect) -> [QuadBox] {
		var newRect = newRect
        let quads = NSMutableArray()

        assert(newRect.origin.x >= -180.0 && newRect.origin.x <= 180.0)
        if newRect.origin.x + newRect.size.width > 180 {
			let half = OSMRect( origin: OSMPoint(x: -180.0,
												 y: newRect.origin.y ),
								size: OSMSize(width: newRect.origin.x + newRect.size.width - 180.0,
											  height: newRect.size.height) )
			rootQuad.missingPieces(quads, intersecting: half)
            newRect.size.width = 180 - newRect.origin.x
        }
		rootQuad.missingPieces(quads, intersecting: newRect)
        return quads as! [QuadBox]
    }

    func makeWhole(_ quad: QuadBox, success: Bool) {
        quad.makeWhole(success)
    }

    // MARK: Spatial

	@objc func addMember(_ member: OsmBaseObject, undo: MyUndoManager?) {
        if let undo = undo {
            undo.registerUndo(withTarget: self, selector: #selector(removeMember(_:undo:)), objects: [member, undo])
        }
        let boundingBox = member.boundingBox
		rootQuad.addMember(member, bbox: boundingBox)
    }

	func removeMember(_ member: OsmBaseObject, undo: MyUndoManager?) -> Bool {
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
        let fromQuad = rootQuad.getMember(member, bbox: fromBox)
        if let fromQuad = fromQuad {
            if OSMRectContainsRect(fromQuad.rect, toBox) {
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

    // these are for purging old data:

    // MARK: Purge objects

    func discardQuadsOlderThanDate(_ date: Date) -> Bool {
        return rootQuad.discardQuadsOlderThanDate(date)
    }

    func discardOldestQuads(_ fraction: Double, oldest: Date) -> Date? {
		return rootQuad.discardOldestQuads(fraction, oldest: oldest)
    }

    func pointIsCovered(_ point: OSMPoint) -> Bool {
        return rootQuad.pointIsCovered(point)
    }

    func nodesAreCovered(_ nodeList: [OsmNode]) -> Bool {
        return rootQuad.nodesAreCovered(nodeList)
    }

    func deleteObjects(withPredicate predicate: @escaping (_ obj: OsmBaseObject) -> Bool) {
        rootQuad.deleteObjects(predicate: predicate)
    }

    func consistencyCheckNodes(_ nodes: [OsmNode], ways: [OsmWay], relations: [OsmRelation]) {
        // check that every object appears exactly one in the object tree
        for object in nodes {
            rootQuad.consistencyCheck(object)
        }
        for object in ways {
            rootQuad.consistencyCheck(object)
        }
        for object in relations {
            rootQuad.consistencyCheck(object)
        }
		assert(rootQuad.count() == nodes.count + ways.count + relations.count)
    }
}
