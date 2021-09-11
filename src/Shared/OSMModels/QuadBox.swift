//
//  QuadBox.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 6/14/21.
//  Copyright © 2021 Bryce. All rights reserved.
//

import Foundation

private let MinRectSize = 360.0 / Double(1 << 18) // FIXME: This should vary between spatial and region
private let MAP_RECT = OSMRect(x: -180.0, y: -90.0, width: 360.0, height: 180.0)
private let MAX_MEMBERS_PER_LEVEL = 40
private let MAX_DEPTH = 26 // 2 feet wide

private
enum QUAD_ENUM: Int, CaseIterable {
	case SE = 0
	case SW = 1
	case NE = 2
	case NW = 3
}

struct ViewRegion {
	let encloses: (OSMRect) -> Bool
	let intersects: (OSMRect) -> Bool
}

final class QuadBox: NSObject, NSCoding {
	static let emptyChildren: [QuadBox?] = [nil, nil, nil, nil]

	let rect: OSMRect
	var parent: QuadBox?

	var children: [QuadBox?] = QuadBox.emptyChildren
	// this quad successfully downloaded all of its data, so we don't need to track children anymore
	var isDownloaded = false
	var downloadDate = 0.0
	var busy = false // this quad is currently being downloaded

	var isSplit = false

	// member is used only for spatial
	var members: [OsmBaseObject] = []

	private init(rect: OSMRect, parent: QuadBox?) {
		self.rect = rect
		self.parent = parent
	}

	override convenience init() {
		self.init(rect: MAP_RECT, parent: nil)
	}

	func reset() {
		children = QuadBox.emptyChildren
		isDownloaded = false
		busy = false
		isSplit = false
		downloadDate = 0.0
		members = []
	}

	func encode(with coder: NSCoder) {
		if let child = children[0] { coder.encode(child, forKey: "child0") }
		if let child = children[1] { coder.encode(child, forKey: "child1") }
		if let child = children[2] { coder.encode(child, forKey: "child2") }
		if let child = children[3] { coder.encode(child, forKey: "child3") }
		coder.encode(isDownloaded, forKey: "whole")
		var rect = rect
		coder.encode(Data(bytes: &rect, count: MemoryLayout.size(ofValue: rect)), forKey: "rect")
		coder.encode(isSplit, forKey: "split")
		coder.encode(downloadDate, forKey: "date")
	}

	init?(coder: NSCoder) {
		children[0] = coder.decodeObject(forKey: "child0") as? QuadBox
		children[1] = coder.decodeObject(forKey: "child1") as? QuadBox
		children[2] = coder.decodeObject(forKey: "child2") as? QuadBox
		children[3] = coder.decodeObject(forKey: "child3") as? QuadBox
		isDownloaded = coder.decodeBool(forKey: "whole")
		isSplit = coder.decodeBool(forKey: "split")
		guard let rectData = coder.decodeObject(forKey: "rect") as? Data else { return nil }
		rect = rectData.withUnsafeBytes({ $0.load(as: OSMRect.self) })
		downloadDate = coder.decodeDouble(forKey: "date")
		parent = nil
		busy = false

		super.init()

		for child in children {
			if let child = child {
				child.parent = self
			}
		}

		// if we just upgraded from an older install then we may need to set a download date
		if isDownloaded, downloadDate == 0.0 {
			downloadDate = NSDate.timeIntervalSinceReferenceDate
		}
	}

	func hasChildren() -> Bool {
		return children[0] != nil ||
			children[1] != nil ||
			children[2] != nil ||
			children[3] != nil
	}

	func enumerateWithBlock(_ block: (QuadBox) -> Void) {
		block(self)
		for child in children {
			if let child = child {
				child.enumerateWithBlock(block)
			}
		}
	}

	func quadForRect(_ target: OSMRect) -> QuadBox {
		for child in children where child != nil {
			if child!.rect.containsRect(target) {
				// recurse down to find smallest quad
				return child!.quadForRect(target)
			}
		}
		return self
	}

	// MARK: Region

	func missingPieces(_ missing: inout [QuadBox], intersecting needed: ViewRegion) {
		assert(needed.intersects(rect))

		if isDownloaded || busy {
			// previously downloaded, or in the process of being downloaded
			return
		}
		if rect.size.width <= MinRectSize {
			// smallest allowed size
			busy = true
			missing.append(self)
//			print("depth \(Int(round(log2(360.0/rect.size.width))))")
			return
		}
		if needed.encloses(rect), !hasChildren() {
			// no part of us has been downloaded, and we're completely covered by the needed area
			busy = true
			missing.append(self)
//			print("depth \(Int(round(log2(360.0/rect.size.width))))")
			return
		}

		// find the child pieces that are partially covered and recurse
		for child in QUAD_ENUM.allCases {
			let rc = QuadBox.ChildRect(child, rect)
			if needed.intersects(rc) {
				if children[child.rawValue] == nil {
					children[child.rawValue] = QuadBox(rect: rc, parent: self)
				}

				children[child.rawValue]!.missingPieces(&missing, intersecting: needed)
			}
		}
	}

	// This runs after we attempted to download a quad.
	// If the download succeeded we can mark this region and its children as whole.
	func updateDownloadStatus(success: Bool) {
		if let parent = parent,
		   parent.isDownloaded
		{
			// parent was made whole (somehow) before we completed, so nothing to do
			if countBusy() == 0 {
				delete()
			}
			return
		}

		busy = false

		if success {
			downloadDate = Date.timeIntervalSinceReferenceDate
			isDownloaded = true
			children = QuadBox.emptyChildren
			if let parent = parent {
				// if all children of parent exist and are whole then parent is whole as well
				let childrenComplete = parent.children.allSatisfy({ $0?.isDownloaded ?? false })
				if childrenComplete {
#if true
					// we want to have fine granularity during discard phase, so don't delete children by taking the updateDownloadStatus() path
					parent.isDownloaded = true
#else
					parent.updateDownloadStatus(success)
#endif
				}
			}
		}
	}

	// Delete ourself from the quad tree
	private func delete() {
		if let parent = parent {
			// remove parent's pointer to us
			if let index = parent.children.firstIndex(where: { $0 === self }) {
				parent.children[index] = nil
			}
			self.parent = nil
		}

		// delete any children
		children = []
	}

	func enumerate(_ block: (QuadBox) -> Void) {
		block(self)
		for child in children {
			if let child = child {
				child.enumerate(block)
			}
		}
	}

	func countOfObjects() -> Int {
		var count = 0
		enumerateWithBlock({ count += $0.members.count })
		return count
	}

	func isEmpty() -> Bool {
		return members.isEmpty && children.firstIndex(where: { $0 != nil }) == nil
	}

	func countBusy() -> Int {
		var c = busy ? 1 : 0
		for child in children where child != nil {
			c += child!.countBusy()
		}
		return c
	}

	/// Discard any quads older than the given date (assuming they aren't busy).
	/// Returns a bool whether anything was discarded.
	func discardQuadsOlderThan(referenceDate date: Double) -> Bool {
		if busy {
			return false
		}

		if downloadDate != 0.0,
		   downloadDate < date
		{
			parent?.isDownloaded = false
			delete()
			return true
		} else {
			var childRemoved = false
			for child in children {
				if let child = child {
					if child.discardQuadsOlderThan(referenceDate: date) {
						childRemoved = true
					}
				}
			}
			// Delete ourself if all our children are gone, and we haven't downloaded anything
			if childRemoved,
			   !isDownloaded,
			   downloadDate == 0.0,
			   !hasChildren(),
			   parent != nil
			{
				delete()
			}
			return childRemoved
		}
	}

	func discardQuadsOlderThanDate(_ date: Date) -> Bool {
		return discardQuadsOlderThan(referenceDate: date.timeIntervalSinceReferenceDate)
	}

	// Discard the oldest "fraction" of quads, or quads older than oldestDate, whichever is more
	// Return the cutoff date selected, or nil if nothing to discard
	func discardOldestQuads(fraction: Double, oldest: Date) -> Date? {
		var oldest = oldest

		if fraction > 0.0 {
			// get a list of all quads that have downloads
			var list: [QuadBox] = []
			enumerateWithBlock({
				if $0.downloadDate > 0.0 {
					list.append($0)
				}
			})
			if list.isEmpty {
				return nil
			}
			// sort ascending by date (oldest first)
			list.sort(by: { $0.downloadDate < $1.downloadDate })

			let index = Int(Double(list.count) * fraction)
			if index < list.count {
				let fractionDate = list[index].downloadDate
				if fractionDate > oldest.timeIntervalSinceReferenceDate {
					// Cutoff date based on fraction is higher (more recent)
					// so prune based on the fraction instead
					oldest = Date(timeIntervalSinceReferenceDate: fractionDate)
				}
			}
		}
		return discardQuadsOlderThan(referenceDate: oldest.timeIntervalSinceReferenceDate) ? oldest : nil
	}

	func pointIsCovered(_ point: OSMPoint) -> Bool {
		if downloadDate != 0.0 {
			return true
		} else {
			let c = childForPoint(point)
			if let child = children[c.rawValue],
			   child.pointIsCovered(point)
			{
				return true
			}
			return false
		}
	}

	// if any node is covered then return true (don't delete object)
	// should only be called on root quad
	func anyNodeIsCovered(nodeList: [OsmNode]) -> Bool {
		// rather than searching the entire tree for each node we start the search at the location of the previous node
		var quad = self

		node_loop: for node in nodeList {
			let point = node.location()
			// move up until we find a quad containing the point
			while !quad.rect.containsPoint(point), quad.parent != nil {
				quad = quad.parent!
			}
			// recurse down until we find a quad with a download date
			while quad.downloadDate == 0.0 {
				let c = quad.childForPoint(point)
				guard let child = quad.children[c.rawValue] else {
					continue node_loop
				}
				quad = child
			}
			return true
		}
		return false
	}

	private static func ChildRect(_ child: QUAD_ENUM, _ parent: OSMRect) -> OSMRect {
		switch child {
		case .NW: return OSMRect(
				x: parent.origin.x,
				y: parent.origin.y,
				width: parent.size.width * 0.5,
				height: parent.size.height * 0.5)
		case .SW: return OSMRect(
				x: parent.origin.x,
				y: parent.origin.y + parent.size.height * 0.5,
				width: parent.size.width * 0.5,
				height: parent.size.height * 0.5)
		case .SE: return OSMRect(
				x: parent.origin.x + parent.size.width * 0.5,
				y: parent.origin.y + parent.size.height * 0.5,
				width: parent.size.width * 0.5,
				height: parent.size.height * 0.5)
		case .NE: return OSMRect(
				x: parent.origin.x + parent.size.width * 0.5,
				y: parent.origin.y,
				width: parent.size.width * 0.5,
				height: parent.size.height * 0.5)
		}
	}

	// find a child member could fit into
	private func childForPoint(_ member: OSMPoint) -> QUAD_ENUM {
		let west = member.x < rect.origin.x + rect.size.width * 0.5
		let north = member.y < rect.origin.y + rect.size.height * 0.5
		let raw = (north ? 1 : 0) << 1 | (west ? 1 : 0)
		return QUAD_ENUM(rawValue: raw)!
	}

	private func childForRect(_ member: OSMRect) -> QUAD_ENUM? {
		let midX = rect.origin.x + rect.size.width * 0.5
		let midY = rect.origin.y + rect.size.height * 0.5
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

	private func addMember(member: OsmBaseObject, bbox: OSMRect, depth: Int) {
		if !isSplit,
		   depth >= MAX_DEPTH || members.count < MAX_MEMBERS_PER_LEVEL
		{
			members.append(member)
			return
		}
		if !isSplit {
			// split self
			isSplit = true
			let childList = members
			members = []
			for c in childList {
				addMember(member: c, bbox: c.boundingBox, depth: depth)
			}
		}
		// find a child member could fit into
		if let index = childForRect(bbox) {
			// add to child quad
			if children[index.rawValue] == nil {
				let rc = QuadBox.ChildRect(index, rect)
				children[index.rawValue] = QuadBox(rect: rc, parent: self)
			}
			children[index.rawValue]!.addMember(member: member, bbox: bbox, depth: depth + 1)
		} else {
			// add to self
			if members.contains(member) {
#if DEBUG
				assert(false) // duplicate entry
#endif
				return
			}
			members.append(member)
		}
	}

	func addMember(_ member: OsmBaseObject, bbox: OSMRect) {
		addMember(member: member, bbox: bbox, depth: 0)
	}

	@discardableResult
	func removeMember(_ member: OsmBaseObject, bbox: OSMRect) -> Bool {
		if let index = members.firstIndex(of: member) {
			members.remove(at: index)
			return true
		}
		// find a child member could fit into
		for child in QUAD_ENUM.allCases {
			guard let c = children[child.rawValue] else {
				continue
			}
			let rc = QuadBox.ChildRect(child, rect)
			if bbox.intersectsRect(rc) {
				if c.removeMember(member, bbox: bbox) {
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
			let rc = Self.ChildRect(child, rect)
			if bbox.intersectsRect(rc) {
				return children[child.rawValue]?.getQuadBoxContaining(member, bbox: bbox)
			}
		}
		return nil
	}

	func findObjects(inArea bbox: OSMRect, block: (OsmBaseObject) -> Void) {
		var stack: [QuadBox] = []
		stack.reserveCapacity(32)
		stack.append(self)

		while let q = stack.popLast() {
			for obj in q.members {
				if obj.boundingBox.intersectsRect(bbox) {
					block(obj)
				}
			}
			for child in q.children {
				if let child = child,
				   bbox.intersectsRect(child.rect)
				{
					stack.append(child)
				}
			}
		}
	}

	func findObjects2(inArea bbox: OSMRect, block: (OsmBaseObject) -> Void) {
		for obj in members where obj.boundingBox.intersectsRect(bbox) {
			block(obj)
		}
		for child in children {
			if let child = child,
			   bbox.intersectsRect(child.rect)
			{
				child.findObjects(inArea: bbox, block: block)
			}
		}
	}

	func enumerateObjects(_ block: (_ obj: OsmBaseObject, _ rect: OSMRect) -> Void) {
		for obj in members {
			block(obj, rect)
		}
		for child in children where child != nil {
			child!.enumerateObjects(block)
		}
	}

	func deleteObjects(withPredicate predicate: (_ obj: OsmBaseObject) -> Bool) {
		members.removeAll(where: { predicate($0) })
		for child in children {
			if let child = child {
				child.deleteObjects(withPredicate: predicate)
			}
		}
	}
}
