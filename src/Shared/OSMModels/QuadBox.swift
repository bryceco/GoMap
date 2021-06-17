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

final class QuadBox: NSObject, Codable, NSCoding {

	static let emptyChildren: [QuadBox?] = [nil,nil,nil,nil]

	let rect: OSMRect
	var parent: QuadBox? = nil

	var children: [QuadBox?] = QuadBox.emptyChildren
	var downloadDate = 0.0
	var whole = false				// this quad successfully downloaded all of its data, so we don't need to track children anymore
	var busy = false				// this quad is currently being downloaded
	var isSplit = false
	// member is used only for spatial
	var members: [OsmBaseObject] = []
	#if SHOW_DOWNLOAD_QUADS
	// for debugging purposes we abuse the Gpx code to draw squares representing quads
	var gpxTrack: GpxTrack? = nil
	#endif

	private init(rect: OSMRect, parent: QuadBox?) {
		self.rect = rect
		self.parent = parent
	}

	override convenience init() {
		self.init(rect:MAP_RECT, parent: nil)
	}

	func reset() {
		children = QuadBox.emptyChildren
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
		super.init()
		for child in children {
			if let child = child {
				child.parent = self
			}
		}
	}
	func encode(with coder: NSCoder) {
		if let child = children[0] { coder.encode(child, forKey: "child0") }
		if let child = children[1] { coder.encode(child, forKey: "child1") }
		if let child = children[2] { coder.encode(child, forKey: "child2") }
		if let child = children[3] { coder.encode(child, forKey: "child3") }
		coder.encode( whole, forKey: "whole")
		var rect = rect
		coder.encode( Data(bytes: &rect, count: MemoryLayout.size(ofValue: rect)), forKey: "rect")
		coder.encode( isSplit, forKey: "split")
		coder.encode( downloadDate, forKey: "date")
	}

	init?(coder: NSCoder) {
		children[0]	= coder.decodeObject( forKey: "child0" ) as? QuadBox
		children[1] = coder.decodeObject( forKey: "child1" ) as? QuadBox
		children[2] = coder.decodeObject( forKey: "child2" ) as? QuadBox
		children[3] = coder.decodeObject( forKey: "child3" ) as? QuadBox
		whole			= coder.decodeBool(forKey: "whole" )
		isSplit        	= coder.decodeBool(forKey: "split" )
		guard let rectData	= coder.decodeObject(forKey: "rect" ) as? Data else { return nil }
		rect           	= rectData.withUnsafeBytes( { $0.load(as: OSMRect.self) } )
		downloadDate   	= coder.decodeDouble(forKey: "date" )
		parent	   	    = nil
		busy            = false

		super.init()

		for child in children {
			if let child = child {
				child.parent = self
			}
		}

		// if we just upgraded from an older install then we may need to set a download date
		if whole && downloadDate == 0.0 {
			downloadDate = NSDate.timeIntervalSinceReferenceDate
		}
	}

	func hasChildren() -> Bool
	{
		return children[0] != nil ||
				children[1] != nil ||
				children[2] != nil ||
				children[3] != nil
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

	func quadForRect(_ target: OSMRect) -> QuadBox
	{
		for child in children where child != nil {
			if child!.rect.containsRect( target ) {
				// recurse down to find smallest quad
				return child!.quadForRect(target)
			}
		}
		return self
	}

	// MARK: Region

	func missingPieces(_ missing: inout [QuadBox], intersecting needed: OSMRect )
	{
		if whole || busy {
			return
		}
		if !needed.intersectsRect( rect ) {
			return
		}
		if rect.size.width <= MinRectSize ||
			rect.size.width <= needed.size.width/2 ||
			rect.size.height <= needed.size.height/2
		{
			busy = true
			missing.append( self )
			return
		}
		if needed.containsRect( rect ) {
			if !hasChildren() {
				busy = true
				missing.append( self )
				return
			}
		}

		for child in QUAD_ENUM.allCases {
			let rc = QuadBox.ChildRect( child, rect )
			if needed.intersectsRect( rc ) {

				if children[child.rawValue] == nil {
					children[child.rawValue] = QuadBox( rect: rc, parent: self )
				}

				children[child.rawValue]!.missingPieces( &missing, intersecting: needed )
			}
		}
	}

	// Delete ourself from the quad tree
	private func delete()
	{
		if let parent = parent {
			// remove parent's pointer to us
			if let index = parent.children.firstIndex(where: { $0 === self }) {
				parent.children[index] = nil
			}
			self.parent = nil
		}

		// delete any children
		children = []

#if SHOW_DOWNLOAD_QUADS
		if let gpxTrack = gpxTrack {
			AppDelegate.getAppDelegate.mapView.gpxLayer.deleteTrack( gpxTrack )
		}
#endif
	}

	// This runs after we attempted to download a quad.
	// If the download succeeded we can mark this region and its children as whole.
	func makeWhole( success: Bool )
	{
		if let parent = parent,
		   parent.whole
		{
			// parent was made whole (somehow) before we completed, so nothing to do
			if self.countBusy() == 0 {
				self.delete()	// remove parent reference so we don't have a retain cycle
			}
			return
		}

		busy = false

		if ( success ) {
			downloadDate = Date.timeIntervalSinceReferenceDate
			whole = true
#if SHOW_DOWNLOAD_QUADS	// Display query regions as GPX lines
			gpxTrack = AppDelegate.getAppDelegate.mapView.gpxLayer.createGpxRect( CGRectFromOSMRect(rect) )
#endif
			children = QuadBox.emptyChildren
			if let parent = parent {
				// if all children of parent exist and are whole then parent is whole as well
				let childrenComplete = parent.children.allSatisfy( { $0?.whole ?? false })
				if childrenComplete {
#if true
					// we want to have fine granularity during discard phase, so don't delete children by taking the makeWhole() path
					parent.whole = true
#else
					parent.makeWhole(success)
#endif
				}
			}
		}
	}

	func countOfObjects() -> Int {
		var count = 0
		enumerateWithBlock({ count += $0.members.count })
		return count
	}

	func isEmpty() -> Bool {
		return members.isEmpty && children.firstIndex(where: { $0 != nil } ) == nil
	}

	func countBusy() -> Int
	{
		var c = busy ? 1 : 0
		for child in children where child != nil {
			c += child!.countBusy()
		}
		return c;
	}

	func discardQuadsOlderThan(referenceDate date: Double ) -> Bool
	{
		if busy {
			return false
		}

		if downloadDate != 0.0 && downloadDate < date {
			parent?.whole = false
			self.delete()
			return true
		} else {
			var changed = false
			for c in QUAD_ENUM.allCases {
				if let child = children[c.rawValue] {
					let del = child.discardQuadsOlderThan(referenceDate: date )
					if del {
						changed = true
					}
				}
			}
			if changed && !whole && downloadDate == 0.0 && !hasChildren() && parent != nil {
				self.delete()
			}
			return changed
		}
	}

	func discardQuadsOlderThanDate(_ date: Date ) -> Bool {
		return discardQuadsOlderThan(referenceDate: date.timeIntervalSinceReferenceDate)
	}

	// discard the oldest "fraction" of quads, or oldestDate, whichever is more
	// return the cutoff date selected
	func discardOldestQuads( fraction: Double, oldest: Date ) -> Date?
	{
		var oldest = oldest

		if fraction > 0.0 {
			// get a list of all quads that have downloads
			var list: [QuadBox] = []
			enumerateWithBlock({
				if $0.downloadDate > 0.0 {
					list.append( $0 )
				}
			})
			// sort ascending by date
			list.sort(by: { $0.downloadDate < $1.downloadDate })

			let index = Int( Double(list.count) * fraction )
			let date2 = list[ index ].downloadDate
			if date2 > oldest.timeIntervalSinceReferenceDate {
				oldest = Date(timeIntervalSinceReferenceDate: date2)	// be more aggressive and prune even more
			}
		}
		return self.discardQuadsOlderThan(referenceDate: oldest.timeIntervalSinceReferenceDate) ? oldest : nil
	}

	func pointIsCovered(_ point: OSMPoint ) -> Bool {
		if downloadDate != 0.0 {
			return true
		} else {
			let c = childForPoint( point )
			if let child = children[c.rawValue],
			   child.pointIsCovered( point )
			{
				return true
			}
			return false
		}
	}
	// if any node is covered then return true (don't delete object)
	// should only be called on root quad
	func anyNodeIsCovered( nodeList: [OsmNode] ) -> Bool
	{
		// rather than searching the entire tree for each node we start the search at the location of the previous node
		var quad = self

		node_loop:
		for node in nodeList {
			let point = node.location()
			// move up until we find a quad containing the point
			while !quad.rect.containsPoint( point ) && quad.parent != nil {
				quad = quad.parent!
			}
			// recurse down until we find a quad with a download date
			while quad.downloadDate == 0.0 {
				let c = quad.childForPoint( point )
				guard let child = quad.children[c.rawValue] else {
					continue node_loop
				}
				quad = child
			}
			return true
		}
		return false
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

	func getQuadBoxContaining(_ member: OsmBaseObject, bbox: OSMRect) -> QuadBox? {
		if members.firstIndex(of: member) != nil {
			return self
		}
		// find a child member could fit into
		for child in QUAD_ENUM.allCases {
			let rc = Self.ChildRect( child, rect )
			if bbox.intersectsRect( rc ) {
				return children[child.rawValue]?.getQuadBoxContaining( member, bbox: bbox)
			}
		}
		return nil
	}

	func findObjects(inArea bbox: OSMRect, block: (OsmBaseObject)->Void )
	{
		var stack: [QuadBox] = []
		stack.reserveCapacity( 32 )
		stack.append( self )

		while let q = stack.popLast() {

			for obj in q.members {
				if obj.boundingBox.intersectsRect( bbox ) {
					block( obj )
				}
			}
			for child in q.children {
				if let child = child,
				   bbox.intersectsRect( child.rect )
				{
					stack.append( child )
				}
			}
		}
	}

	func findObjects2(inArea bbox: OSMRect, block: (OsmBaseObject)->Void )
	{
		for obj in members where obj.boundingBox.intersectsRect( bbox ) {
			block( obj );
		}
		for child in children {
			if let child = child,
			   bbox.intersectsRect( child.rect )
			{
				child.findObjects(inArea: bbox, block: block )
			}
		}
	}

	func enumerate(_ block: (_ obj: OsmBaseObject, _ rect: OSMRect) -> Void) {
		for obj in members {
			block( obj, self.rect )
		}
		for child in children where child != nil {
			child!.enumerate( block )
		}
	}

	func deleteObjects(withPredicate predicate: (_ obj: OsmBaseObject) -> Bool) {
		members.removeAll(where: { predicate($0) })
		for child in children {
			if let child = child {
				child.deleteObjects(withPredicate: predicate )
			}
		}
	}
}
