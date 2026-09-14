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
		if let root = coder.decodeObject(of: QuadBox.self, forKey: "rootQuad") {
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

	func addMember(_ member: OsmBaseObject) {
		rootQuad.addMember(member, bbox: member.boundingBox)
	}

	@discardableResult
	func removeMember(_ member: OsmBaseObject) -> Bool {
		return rootQuad.removeMember(member, bbox: member.boundingBox)
	}

	func updateMember(_ member: OsmBaseObject, toBox: OSMRect, fromBox: OSMRect) {
		if fromBox == toBox { return }
		if let fromQuad = rootQuad.getQuadBoxContaining(member, bbox: fromBox) {
			fromQuad.removeMember(member, bbox: fromBox)
			rootQuad.addMember(member, bbox: toBox)
		} else {
			rootQuad.addMember(member, bbox: toBox)
		}
	}

	func updateMember(_ member: OsmBaseObject, fromBox bbox: OSMRect) {
		updateMember(member, toBox: member.boundingBox, fromBox: bbox)
	}

	func findObjects(inArea bbox: OSMRect, block: (OsmBaseObject) -> Void) {
		rootQuad.findObjects(inArea: bbox, block: block)
	}

	func enumerateObjects(_ block: (OsmBaseObject, OSMRect) -> Void) {
		rootQuad.enumerateObjects(block)
	}

	func consistencyCheck(nodes: [OsmIdentifier: OsmNode],
	                      ways: [OsmIdentifier: OsmWay],
	                      relations: [OsmIdentifier: OsmRelation])
	{
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
			if let obj = obj as? OsmNode {
				quadNodes.insert(obj.ident)
				assert(obj === nodes[obj.ident])
			}
			if let obj = obj as? OsmWay {
				quadWays.insert(obj.ident)
				assert(obj === ways[obj.ident])
			}
			if let obj = obj as? OsmRelation {
				quadRelations.insert(obj.ident)
				assert(obj === relations[obj.ident])
			}
		}
		// assert that no object appears multiple times in quad tree
		assert(countDict.first(where: { $0.value != 1 }) == nil)

		// check if there are any items that are missing from quad tree
		let allNodes = Set<OsmIdentifier>(nodes.values.filter({ !$0.deleted }).map { $0.ident })
		let allWays = Set<OsmIdentifier>(ways.values.filter({ !$0.deleted }).map { $0.ident })
		let allRelations = Set<OsmIdentifier>(relations.values.filter({ !$0.deleted }).map { $0.ident })
		let diffNodes = allNodes.subtracting(quadNodes)
		let diffWays = allWays.subtracting(quadWays)
		let diffRelations = allRelations.subtracting(quadRelations)
		for extra in diffNodes {
			print("* node \(extra) is missing from quadMap")
		}
		for extra in diffWays {
			print("* way \(extra) is missing from quadMap")
		}
		for extra in diffRelations {
			print("* relation \(extra) is missing from quadMap")
		}
		assert(diffNodes.isEmpty && diffWays.isEmpty && diffRelations.isEmpty)
	}
}

// MARK: - Discard stale data

extension QuadMap {
	private func discardQuadsOlderThanDate(_ date: Date) -> Bool {
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
}
