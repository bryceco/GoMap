//
//  QuadBox.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 6/14/21.
//  Copyright © 2021 Bryce. All rights reserved.
//

import Foundation

private let MinRectSize = 360.0 / Double(1 << 16)
private let MAP_RECT = OSMRect(x: -180.0, y: -90.0, width: 360.0, height: 180.0 )
private let MAX_MEMBERS_PER_LEVEL = 16
private let MAX_DEPTH = 26	// 2 feet wide

fileprivate
enum QUAD_ENUM: Int, CaseIterable {
	case SE = 0
	case SW = 1
	case NE = 2
	case NW = 3
}

class QuadBox: Codable {
	let rect: OSMRect
	var parent: QuadBox? = nil

	var children: [QuadBox?] = [nil,nil,nil,nil]
	var downloadDate = 0.0
	var whole = false				// this quad has already been processed
	var busy = false				// this quad is currently being processed
	var isSplit = false
	// member is used only for spatial
	var members: [OsmBaseObject] = []

	init(rect: OSMRect, parent: QuadBox?) {
		self.rect = rect
		self.parent = parent
	}

	func reset() {
		children = [nil,nil,nil,nil]
		whole = false
		busy = false
		isSplit = false
		downloadDate = 0.0
		members = []
	}

	enum CodingKeys: String, CodingKey {
		case whole = "whole"
		case rect = "rect"
		case isSplit = "split"
		case downloadDate = "date"
		case children = "children"
	}

/*
	func encode(to encoder: Encoder) {
		if let child0 = children[0] 	{ coder.encode( child0, forKey: "child0") }
		if let child1 = children[1] 	{ coder.encode( child1, forKey: "child1") }
		if let child2 = children[2] 	{ coder.encode( child2, forKey: "child2") }
		if let child3 = children[3] 	{ coder.encode( child3, forKey: "child3") }

		coder.encode(whole, forKey:@"whole")
		coder encodeObject:[NSData dataWithBytes:&_rect length:sizeof _rect]	forKey:@"rect"];
		[coder encodeBool:_isSplit												forKey:@"split"];
		[coder encodeDouble:_downloadDate 										forKey:@"date"];
	}
*/
	required init(from decoder: Decoder) throws {
		let values = try decoder.container(keyedBy: CodingKeys.self)
		children 		= try values.decode([QuadBox?].self, forKey: .children)
		whole			= try values.decode(Bool.self, forKey: .whole)
		isSplit			= try values.decode(Bool.self, forKey: .isSplit)
		rect			= try values.decode(OSMRect.self, forKey: .rect)
		downloadDate	= try values.decode(Double.self, forKey: .downloadDate)
		busy			= false
		for child in children {
			if let child = child {
				child.parent = self
			}
		}
	}


	func enumerateWithBlock(_ block:(QuadBox)->Void )
	{
		block(self)
		for child in children {
			if let child = child {
				child.enumerateWithBlock(block)
			}
		}
	}

	func count() -> Int {
		var count = 0
		enumerateWithBlock({ count += $0.members.count })
		return count
	}

	func isEmpty() -> Bool {
		return members.isEmpty && children.firstIndex(where: { $0 != nil } ) == nil
	}

	private static func ChildRect( _ child: QUAD_ENUM, _ parent: OSMRect ) -> OSMRect
	{
		switch child {
		case .NW:	return OSMRect(x: parent.origin.x, y: parent.origin.y, width: parent.size.width*0.5, height: parent.size.height*0.5)
		case .SW:	return OSMRect(x: parent.origin.x, y: parent.origin.y+parent.size.height*0.5, width: parent.size.width*0.5, height: parent.size.height*0.5)
		case .SE:	return OSMRect(x: parent.origin.x+parent.size.width*0.5, y: parent.origin.y+parent.size.height*0.5, width: parent.size.width*0.5, height: parent.size.height*0.5)
		case .NE:	return OSMRect(x: parent.origin.x+parent.size.width*0.5, y: parent.origin.y, width: parent.size.width*0.5, height: parent.size.height*0.5)
		}
	}
	// find a child member could fit into
	private func childForPoint(_ member: OSMPoint ) -> QUAD_ENUM
	{
		let west  = member.x < rect.origin.x + rect.size.width*0.5
		let north = member.y < rect.origin.y + rect.size.height*0.5
		let raw = (north ? 1 : 0) << 1 | (west ? 1 : 0)
		return QUAD_ENUM(rawValue: raw)!
	}
	private func childForRect(_ member: OSMRect ) -> QUAD_ENUM?
	{
		let midX = rect.origin.x + rect.size.width*0.5
		let midY = rect.origin.y + rect.size.height*0.5
		var west = false
		var north = false
		if member.origin.x < midX {
			// west
			if member.origin.x + member.size.width >= midX {
				return nil
			}
			west = true
		}
		if member.origin.y < midY {
			// north
			if member.origin.y + member.size.height >= midY {
				return nil
			}
			north = true
		}
		let raw = (north ? 1 : 0) << 1 | (west ? 1 : 0)
		return QUAD_ENUM(rawValue: raw)!
	}

	// spatial specific

	private func addMember(member: OsmBaseObject, bbox: OSMRect, depth: Int)
	{
		if !isSplit && (depth >= MAX_DEPTH || members.count < MAX_MEMBERS_PER_LEVEL) {
			members.append( member )
			return
		}
		if !isSplit {
			// split self
			isSplit = true
			let childList = members
			members = []
			for c in childList {
				addMember( member: c, bbox: c.boundingBox, depth: depth )
			}
		}
		// find a child member could fit into
		if let index = childForRect( bbox ) {
			// add to child quad
			if children[index.rawValue] == nil {
				let rc = QuadBox.ChildRect( index, rect )
				children[index.rawValue] = QuadBox( rect: rc, parent: self )
			}
			children[index.rawValue]!.addMember(member: member, bbox: bbox, depth: depth+1)
		} else {
			// add to self
			if members.contains( member ) {
#if DEBUG
				assert(false)	// duplicate entry
#endif
				return;
			}
			members.append( member )
		}
	}
	func addMember(_ member: OsmBaseObject, bbox: OSMRect) {
		self.addMember(member: member, bbox: bbox, depth: 0)
	}

	@discardableResult
	func removeMember( _ member: OsmBaseObject, bbox: OSMRect ) -> Bool
	{
		if let index = members.firstIndex(of: member) {
			members.remove(at: index)
			return true
		}
		// find a child member could fit into
		for child in QUAD_ENUM.allCases {
			guard let c = children[child.rawValue] else {
				continue;
			}
			let rc = QuadBox.ChildRect( child, rect )
			if bbox.intersectsRect( rc ) {
				if c.removeMember( member, bbox: bbox) {
					return true
				}
			}
		}
		return false
	}


	func getMember(_ member: OsmBaseObject, bbox: OSMRect) -> Self? {
		return nil
	}

	func findObjects(inArea bbox: OSMRect, block: @escaping (_ obj: OsmBaseObject) -> Void) {
	}

	func enumerate(_ block: (_ obj: OsmBaseObject, _ rect: OSMRect) -> Void) {
		for obj in members {
			block( obj, self.rect )
		}
		for child in children where child != nil {
			child!.enumerate( block )
		}
	}

	// region specific
	func missingPieces(_ pieces: inout [QuadBox], intersecting target: OSMRect) {
	}
	func makeWhole(_ success: Bool) {
	}

	// these are for discarding old data:
	func discardQuadsOlderThanDate(_ date: Date) -> Bool {
		return false
	}

	func discardOldestQuads(_ fraction: Double, oldest: Date) -> Date? {
		return nil
	}

	func pointIsCovered(_ point: OSMPoint) -> Bool {
		return false
	}

	func nodesAreCovered(_ nodeList: [AnyHashable]) -> Bool {
		return false
	}

	func deleteObjects(withPredicate predicate: @escaping (_ obj: OsmBaseObject) -> Bool) {
	}
}
