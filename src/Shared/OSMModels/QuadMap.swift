//
//  QuadMap.swift
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 10/10/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

import Foundation

class QuadMap: NSObject, NSSecureCoding {
	static let supportsSecureCoding = true

	let rootQuad: QuadBox
	let encodingContentsOnSave: Bool

	// MARK: Common

	init(encodingContentsOnSave: Bool) {
		rootQuad = QuadBox()
		self.encodingContentsOnSave = encodingContentsOnSave
		super.init()
	}

	func countOfObjects() -> Int {
		return rootQuad.countOfObjects()
	}

	func isEmpty() -> Bool {
		return rootQuad.isEmpty()
	}

	func encode(with coder: NSCoder) {
		if encodingContentsOnSave {
			coder.encode(rootQuad, forKey: "rootQuad")
		}
	}

	required init?(coder: NSCoder) {
		if let root = coder.decodeObject(forKey: "rootQuad") as? QuadBox {
			rootQuad = root
			encodingContentsOnSave = true
		} else {
			// we end up here when loading a spatial (which doesn't save it's rootQuad)
			rootQuad = QuadBox()
			encodingContentsOnSave = false
		}
		super.init()
	}

	// MARK: Regions

	func missingQuads(forRect newRect: OSMRect) -> [QuadBox] {
		var newRect = newRect
		var quads: [QuadBox] = []

		assert(newRect.origin.x >= -180.0 && newRect.origin.x <= 180.0)
		if newRect.origin.x + newRect.size.width > 180 {
			let half = OSMRect(origin: OSMPoint(x: -180.0,
			                                    y: newRect.origin.y),
			                   size: OSMSize(width: newRect.origin.x + newRect.size.width - 180.0,
			                                 height: newRect.size.height))
			rootQuad.missingPieces(&quads, intersecting: half)
			newRect.size.width = 180 - newRect.origin.x
		}
		rootQuad.missingPieces(&quads, intersecting: newRect)
		return quads
	}

	func updateDownloadStatus(_ quad: QuadBox, success: Bool) {
		quad.updateDownloadStatus(success: success)
	}

	func enumerate(_ block: (QuadBox) -> Void) {
		rootQuad.enumerate(block)
	}

	func downloadCount() -> Int {
		var c = 0
		enumerate({ if $0.isDownloaded { c += 1 } })
		return c
	}

	// MARK: Spatial

	@objc func addMember(_ member: OsmBaseObject, undo: MyUndoManager?) {
		if let undo = undo {
			undo.registerUndo(withTarget: self,
			                  selector: #selector(removeMember(_:undo:)),
			                  objects: [member, undo])
		}
		let boundingBox = member.boundingBox
		rootQuad.addMember(member, bbox: boundingBox)
	}

	@objc func removeMember(_ member: OsmBaseObject, undo: MyUndoManager?) -> Bool {
		let boundingBox = member.boundingBox
		let ok = rootQuad.removeMember(member, bbox: boundingBox)
		if ok, let undo = undo {
			undo.registerUndo(
				withTarget: self,
				selector: #selector(addMember(_:undo:)),
				objects: [member, undo as Any])
		}
		return ok
	}

	func updateMember(_ member: OsmBaseObject, toBox: OSMRect, fromBox: OSMRect, undo: MyUndoManager?) {
		if fromBox == toBox {
			return
		}
		if let fromQuad = rootQuad.getQuadBoxContaining(member, bbox: fromBox) {
			fromQuad.removeMember(member, bbox: fromBox)
			rootQuad.addMember(member, bbox: toBox)
			if let undo = undo {
				var toBox = toBox
				var fromBox = fromBox
				let toData = Data(bytes: &toBox, count: MemoryLayout.size(ofValue: toBox))
				let fromData = Data(bytes: &fromBox, count: MemoryLayout.size(ofValue: fromBox))
				undo.registerUndo(
					withTarget: self,
					selector: #selector(updateMemberBoxed(_:toBox:fromBox:undo:)),
					objects: [member, fromData, toData, undo])
			}
		} else {
			rootQuad.addMember(member, bbox: toBox)
			if let undo = undo {
				undo.registerUndo(withTarget: self,
				                  selector: #selector(removeMember(_:undo:)),
				                  objects: [member, undo])
			}
		}
	}

	// This is just like updateMember but allows boxed arguments so the undo manager can call it
	@objc func updateMemberBoxed(_ member: OsmBaseObject, toBox: Data, fromBox: Data, undo: MyUndoManager?) {
		let to: OSMRect = toBox.withUnsafeBytes({ $0.load(as: OSMRect.self) })
		let from: OSMRect = fromBox.withUnsafeBytes({ $0.load(as: OSMRect.self) })
		updateMember(member, toBox: to, fromBox: from, undo: undo)
	}

	// Spatial
	func updateMember(_ member: OsmBaseObject, fromBox bbox: OSMRect, undo: MyUndoManager?) {
		let boundingBox = member.boundingBox
		updateMember(member, toBox: boundingBox, fromBox: bbox, undo: undo)
	}

	func findObjects(inArea bbox: OSMRect, block: (OsmBaseObject) -> Void) {
		rootQuad.findObjects(inArea: bbox, block: block)
	}

	func enumerateObjects(_ block: (OsmBaseObject, OSMRect) -> Void) {
		rootQuad.enumerateObjects(block)
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
		var countDict: [OsmExtendedIdentifier: Int] = [:]
		var quadNodes: Set<OsmIdentifier> = []
		var quadWays: Set<OsmIdentifier> = []
		var quadRelations: Set<OsmIdentifier> = []
		rootQuad.enumerateObjects { obj, rect in
			assert(rect.containsRect(obj.boundingBox))
			assert(!obj.deleted)
			let id = obj.extendedIdentifier
			if let cnt = countDict[id] {
				countDict[id] = cnt + 1
			} else {
				countDict[id] = 1
			}
			if let obj = obj as? OsmNode { quadNodes.insert(obj.ident) }
			if let obj = obj as? OsmWay { quadWays.insert(obj.ident) }
			if let obj = obj as? OsmRelation { quadRelations.insert(obj.ident) }
		}
		// assert that no object appears multiple times in quad tree
		assert(countDict.first(where: { $0.value != 1 }) == nil)

		// check if there are any items that are missing from quad tree
		let allNodes = Set<OsmIdentifier>(nodes.lazy.filter({ !$0.deleted }).map { $0.ident })
		let allWays = Set<OsmIdentifier>(ways.lazy.filter({ !$0.deleted }).map { $0.ident })
		let allRelations = Set<OsmIdentifier>(relations.lazy.filter({ !$0.deleted }).map { $0.ident })
		let diffNodes = allNodes.subtracting(quadNodes)
		let diffWays = allWays.subtracting(quadWays)
		let diffRelations = allRelations.subtracting(quadRelations)
		for extra in diffNodes {
			print("node \(extra)")
		}
		for extra in diffWays {
			print("way \(extra)")
		}
		for extra in diffRelations {
			print("relation \(extra)")
		}
		assert(diffNodes.isEmpty && diffWays.isEmpty && diffRelations.isEmpty)
	}
}
