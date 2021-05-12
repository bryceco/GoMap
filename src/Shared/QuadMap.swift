//  Converted to Swift 5.4 by Swiftify v5.4.27034 - https://swiftify.com/
//
//  QuadMap.swift
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 10/10/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

import Foundation

enum QUAD_ENUM : Int {
    case quad_SE = 0
    case quad_SW = 1
    case quad_NE = 2
    case quad_NW = 3
    case quad_LAST = 3
}


private let MAP_RECT = OSMRect(-180, -90, 360, 180)

class QuadBox: NSObject, NSCoding {
    private(set) var rect: OSMRect?
    private(set) var cpp: QuadBoxCC?

    init(rect: OSMRect) {
    }

    init(this cpp: QuadBoxCC?) {
    }

    func reset() {
    }

    func nullifyCpp() {
    }

    func deleteCpp() {
    }

    func count() -> Int {
    }

    // spatial specific
    func addMember(_ member: OsmBaseObject?, bbox: OSMRect) {
    }

    func removeMember(_ member: OsmBaseObject?, bbox: OSMRect) -> Bool {
    }

    func getMember(_ member: OsmBaseObject?, bbox: OSMRect) -> Self {
    }

    func findObjects(inArea bbox: OSMRect, block: @escaping (_ obj: OsmBaseObject?) -> Void) {
    }

    // region specific
    func missingPieces(_ pieces: inout [AnyHashable], intersecting target: OSMRect) {
    }

    func makeWhole(_ success: Bool) {
    }

    // these are for discarding old data:
    func discardQuadsOlderThanDate(_ date: Date?) -> Bool {
    }

    func discardOldestQuads(_ fraction: Double, oldest: Date?) -> Date? {
    }

    func pointIsCovered(_ point: OSMPoint) -> Bool {
    }

    func nodesAreCovered(_ nodeList: [AnyHashable]?) -> Bool {
    }

    func deleteObjects(withPredicate predicate: @escaping (_ obj: OsmBaseObject?) -> Bool) {
    }

    func consistencyCheck(_ object: OsmBaseObject?) {
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
}

class QuadMap: NSObject, NSCoding {
    var rootQuad: QuadBox?

    // MARK: Common

    init(rect: OSMRect) {
        super.init()
        rootQuad = QuadBox(rect: rect)
    }

    convenience init() {
        self.init(rect: MAP_RECT)
    }

    deinit {
        rootQuad?.deleteCpp() // cpp has a strong reference to this so we need to reset it manually
    }

    func count() -> Int {
        return rootQuad?.count() ?? 0
    }

    func encode(with coder: NSCoder) {
        coder.encode(rootQuad, forKey: "rootQuad")
    }

    required init?(coder: NSCoder) {
        super.init()
        rootQuad = coder.decodeObject(forKey: "rootQuad") as? QuadBox
    }

    // MARK: Regions

    func mergeDerivedRegion(_ other: QuadMap?, success: Bool) {
        assert(other?.count() == 1)
        makeWhole(other?.rootQuad, success: success)
    }

    // Region
    func newQuads(for newRect: OSMRect) -> [AnyHashable]? {
        var quads: [AnyHashable] = []

        assert(newRect.origin.x >= -180.0 && newRect.origin.x <= 180.0)
        if newRect.origin.x + newRect.size.width > 180 {
            let half: OSMRect
            half.origin.x = -180
            half.size.width = newRect.origin.x + newRect.size.width - 180
            half.origin.y = newRect.origin.y
            half.size.height = newRect.size.height
            rootQuad?.missingPieces(&quads, intersecting: half)
            newRect.size.width = 180 - newRect.origin.x
        }
        rootQuad?.missingPieces(&quads, intersecting: newRect)
        return quads
    }

    func makeWhole(_ quad: QuadBox?, success: Bool) {
        quad?.makeWhole(success)
    }

    // MARK: Spatial

    @objc func addMember(_ member: OsmBaseObject?, undo: UndoManager?) {
        if let undo = undo {
            undo.registerUndo(withTarget: self, selector: #selector(removeMember(_:undo:)), objects: [member, undo])
        }
        if let boundingBox = member?.boundingBox {
            rootQuad?.addMember(member, bbox: boundingBox)
        }
    }

    @objc func removeMember(_ member: OsmBaseObject?, undo: UndoManager?) -> Bool {
        var ok: Bool? = nil
        if let boundingBox = member?.boundingBox {
            ok = rootQuad?.removeMember(member, bbox: boundingBox) ?? false
        }
        if ok ?? false && undo != nil {
            undo?.registerUndo(withTarget: self, selector: #selector(addMember(_:undo:)), objects: [member, undo])
        }
        return ok ?? false
    }

    func updateMember(_ member: OsmBaseObject?, toBox: OSMRect, fromBox: OSMRect, undo: UndoManager?) {
        var toBox = toBox
        var fromBox = fromBox
        let fromQuad = rootQuad?.getMember(member, bbox: fromBox)
        if let fromQuad = fromQuad {
            if OSMRectContainsRect(fromQuad.rect, toBox) {
                // It fits in its current box. It might fit into a child, but this path is rare and not worth optimizing.
                return
            }
            fromQuad.removeMember(member, bbox: fromBox)
            rootQuad?.addMember(member, bbox: toBox)
            if let undo = undo {
                let toData = Data(bytes: &toBox, length: MemoryLayout.size(ofValue: toBox))
                let fromData = Data(bytes: &fromBox, length: MemoryLayout.size(ofValue: fromBox))
                undo.registerUndo(withTarget: self, selector: #selector(updateMemberBoxed(_:toBox:fromBox:undo:)), objects: [member, fromData, toData, undo])
            }
        } else {
            rootQuad?.addMember(member, bbox: toBox)
            if let undo = undo {
                undo.registerUndo(withTarget: self, selector: #selector(removeMember(_:undo:)), objects: [member, undo])
            }
        }
    }

    // This is just like updateMember but allows boxed arguments so the undo manager can call it
    @objc func updateMemberBoxed(_ member: OsmBaseObject?, toBox: Data?, fromBox: Data?, undo: UndoManager?) {
        let to = toBox?.bytes as? OSMRect
        let from = fromBox?.bytes as? OSMRect
        if let to = to, let from = from {
            updateMember(member, toBox: to, fromBox: from, undo: undo)
        }
    }

    // Spatial
    func updateMember(_ member: OsmBaseObject?, fromBox bbox: OSMRect, undo: UndoManager?) {
        if let boundingBox = member?.boundingBox {
            updateMember(member, toBox: boundingBox, fromBox: bbox, undo: undo)
        }
    }

    func findObjects(inArea bbox: OSMRect, block: @escaping (OsmBaseObject?) -> Void) {
        rootQuad?.findObjects(inArea: bbox, block: block)
    }

    // these are for purging old data:

    // MARK: Purge objects

    func discardQuadsOlderThanDate(_ date: Date?) -> Bool {
        return rootQuad?.discardQuadsOlderThanDate(date) ?? false
    }

    func discardOldestQuads(_ fraction: Double, oldest: Date?) -> Date? {
        return rootQuad?.discardOldestQuads(fraction, oldest: oldest)
    }

    func pointIsCovered(_ point: OSMPoint) -> Bool {
        return rootQuad?.pointIsCovered(point) ?? false
    }

    func nodesAreCovered(_ nodeList: [AnyHashable]?) -> Bool {
        return rootQuad?.nodesAreCovered(nodeList) ?? false
    }

    func deleteObjects(withPredicate predicate: @escaping (_ obj: OsmBaseObject?) -> Bool) {
        rootQuad?.deleteObjects(withPredicate: predicate)
    }

    func consistencyCheckNodes(_ nodes: [AnyHashable]?, ways: [AnyHashable]?, relations: [AnyHashable]?) {
        // check that every object appears exactly one in the object tree
        for object in nodes ?? [] {
            guard let object = object as? OsmBaseObject else {
                continue
            }
            rootQuad?.consistencyCheck(object)
        }
        for object in ways ?? [] {
            guard let object = object as? OsmBaseObject else {
                continue
            }
            rootQuad?.consistencyCheck(object)
        }
        for object in relations ?? [] {
            guard let object = object as? OsmBaseObject else {
                continue
            }
            rootQuad?.consistencyCheck(object)
        }
        assert(rootQuad?.count() == (nodes?.count ?? 0) + (ways?.count ?? 0) + (relations?.count ?? 0))
    }
}