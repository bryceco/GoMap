//
//  OsmMapData.swift
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 9/1/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

import Compression
import CoreLocation
import Foundation
import UIKit

typealias EditAction = () -> Void
typealias EditActionWithNode = (OsmNode) -> Void
typealias EditActionReturnWay = () -> OsmWay
typealias EditActionReturnNode = () -> OsmNode

final class OsmUserStatistics {
	var user = ""
	var lastEdit: Date!
	var editCount = 0
	var changeSets: Set<Int64> = []
	var changeSetsCount = 0
}

private final class ServerQuery {
	var quadList: [QuadBox] = []
	var rect = OSMRect.zero
}

enum OsmMapDataError: LocalizedError {
	case unableToOpenDatabase
	case osmWayResolveToMapDataFoundNilNodeRefs
	case osmWayResolveToMapDataCouldntFindNodeRef
	case badURL(String)
	case otherError(String)
	case badServerUpdateValue
	case badXML

	public var errorDescription: String? {
		switch self {
		case .unableToOpenDatabase: return "OsmMapDataError.unableToOpenDatabase"
		case .osmWayResolveToMapDataFoundNilNodeRefs: return "OsmMapDataError.osmWayResolveToMapDataFoundNilNodeRefs"
		case .osmWayResolveToMapDataCouldntFindNodeRef: return "OsmMapDataError.osmWayResolveToMapDataCouldntFindNodeRef"
		case let .badURL(url): return "OsmMapDataError.badURL(\(url))"
		case let .otherError(message): return "OsmMapDataError.otherError(\(message))"
		case .badServerUpdateValue: return "badServerUpdateValue"
		case .badXML: return "OsmMapDataError:badXML"
		}
	}
}

final class OsmMapData: NSObject, NSSecureCoding {
	static let supportsSecureCoding = true

	// only used when saving/restoring undo manager
	public static var g_EditorMapLayerForArchive: EditorMapLayer?

	private(set) var nodes: [OsmIdentifier: OsmNode] = [:]
	private(set) var ways: [OsmIdentifier: OsmWay] = [:]
	private(set) var relations: [OsmIdentifier: OsmRelation] = [:]
	var periodicSaveTimer: Timer?

	let region: QuadMap
	let spatial: QuadMap
	let undoManager: MyUndoManager

	// undo comments
	var undoContextForComment: ((_ comment: String) -> [String: Any])?
	var undoCommentCallback: ((_ undo: Bool, _ context: [String: Any]) -> Void)?

	private var previousDiscardDate = Date.distantPast

	// MARK: Utility

	func resetServer(_ host: OsmServer) {
		if OSM_SERVER.apiURL.absoluteString.count != 0 {
			// get rid of old data before connecting to new server
			purgeSoft()
		}
	}

	func setupPeriodicSaveTimer() {
		NotificationCenter.default.addObserver(
			forName: NSNotification.Name(MyUndoManager.UndoManagerDidChangeNotification),
			object: undoManager,
			queue: nil,
			using: { [weak self] _ in
				guard let self else {
					return
				}
				if self.periodicSaveTimer == nil {
					self.periodicSaveTimer = Timer.scheduledTimer(
						timeInterval: 10.0,
						target: self,
						selector: #selector(periodicSave(_:)),
						userInfo: nil,
						repeats: false)
				}
			})
	}

	@objc func periodicSave(_ timer: Timer) {
		let appDelegate = AppDelegate.shared
		appDelegate.mainView.save() // this will also invalidate the timer
	}

	func setConstructed() {
		nodes.values.forEach { $0.setConstructed() }
		ways.values.forEach { $0.setConstructed() }
		relations.values.forEach { $0.setConstructed() }
	}

	func wayCount() -> Int {
		return ways.count
	}

	func nodeCount() -> Int {
		return nodes.count
	}

	func relationCount() -> Int {
		return relations.count
	}

	func object(withExtendedIdentifier ext: OsmExtendedIdentifier) -> OsmBaseObject? {
		let ident: OsmIdentifier = ext.ident
		let type: OSM_TYPE = ext.type
		switch type {
		case .NODE: return nodes[ident]
		case .WAY: return ways[ident]
		case .RELATION: return relations[ident]
		}
	}

	func waysContaining(_ node: OsmNode) -> [OsmWay] {
		return ways.values.filter({ $0.nodes.contains(node) })
	}

	func objectsContaining(_ object: OsmBaseObject) -> [OsmBaseObject] {
		var a: [OsmBaseObject] = []

		if let object = object as? OsmNode {
			// Don't scan everything: for performance reasons only consider visible objects
			let shownObjects = AppDelegate.shared.mapView.shownObjects
			for obj in shownObjects {
				if let way = obj as? OsmWay,
				   way.nodes.contains(object)
				{
					a.append(way)
				}
			}
		}

		for relation in relations.values {
			if relation.containsObject(object) {
				a.append(relation)
			}
		}

		return a
	}

	func enumerateObjects(usingBlock block: (_ obj: OsmBaseObject) -> Void) {
		for (_, node) in nodes {
			block(node)
		}
		for (_, way) in ways {
			block(way)
		}
		for (_, relation) in relations {
			block(relation)
		}
	}

	func enumerateObjects(inRegion bbox: OSMRect, block: (_ obj: OsmBaseObject) -> Void) {
		if bbox.origin.x < 180, bbox.origin.x + bbox.size.width > 180 {
			let left = OSMRect(
				origin: OSMPoint(x: bbox.origin.x, y: bbox.origin.y),
				size: OSMSize(width: 180 - bbox.origin.x, height: bbox.size.height))
			let right = OSMRect(
				origin: OSMPoint(x: -180, y: bbox.origin.y),
				size: OSMSize(width: bbox.origin.x + bbox.size.width - 180, height: bbox.size.height))
			enumerateObjects(inRegion: left, block: block)
			enumerateObjects(inRegion: right, block: block)
			return
		}

		spatial.findObjects(inArea: bbox, block: block)
	}

	func tagValues(forKey key: String) -> Set<String> {
		var set = Set<String>()

		for object in nodes.values {
			if let value = object.tags[key] {
				set.insert(value)
			}
		}
		for object in ways.values {
			if let value = object.tags[key] {
				set.insert(value)
			}
		}
		for object in relations.values {
			if let value = object.tags[key] {
				set.insert(value)
			}
		}

		// special case for street names
		if key == "addr:street" {
			for object in ways.values {
				if object.tags["highway"] != nil {
					if let nameValue = object.tags["name"] {
						set.insert(nameValue)
					}
				}
			}
		}
		return set
	}

	func userStatistics(forRegion rect: OSMRect) -> [OsmUserStatistics] {
		var dict: [String: OsmUserStatistics] = [:]
		enumerateObjects(inRegion: rect, block: { base in
			let date = base.dateForTimestamp()
			if base.user.isEmpty {
				DLog("Empty user name for object: object \(base), uid = \(base.uid)")
				return
			}
			if let stats = dict[base.user] {
				stats.editCount = stats.editCount + 1
				stats.changeSets.insert(base.changeset)
				if date.compare(stats.lastEdit).rawValue > 0 {
					stats.lastEdit = date
				}
				stats.changeSetsCount = stats.changeSets.count
			} else {
				let stats = OsmUserStatistics()
				stats.user = base.user
				stats.changeSets = Set<Int64>([base.changeset])
				stats.lastEdit = date
				stats.editCount = 1
				dict[base.user] = stats
				stats.changeSetsCount = stats.changeSets.count
			}
		})

		return Array(dict.values)
	}

	func clearCachedProperties() {
		enumerateObjects(usingBlock: { obj in
			obj.clearCachedProperties()
		})
	}

	func modificationCount() -> Int {
		var modifications = 0

		for (_, node) in nodes {
			modifications += (node.deleted ? node.ident > 0 : node.isModified()) ? 1 : 0
		}
		for (_, way) in ways {
			modifications += (way.deleted ? way.ident > 0 : way.isModified()) ? 1 : 0
		}
		for (_, relation) in relations {
			modifications += (relation.deleted ? relation.ident > 0 : relation.isModified()) ? 1 : 0
		}
		let undoCount = undoManager.countUndoGroups
		return min(modifications, undoCount) // different ways to count, but both can be inflated so take the minimum
	}

	// MARK: Editing

	@objc func incrementModifyCount(_ object: OsmBaseObject) {
		undoManager.registerUndo(withTarget: self, selector: #selector(incrementModifyCount(_:)), objects: [object])
		object.incrementModifyCount(undoManager)
	}

	@objc func clearCachedProperties(_ object: OsmBaseObject, undo: MyUndoManager) {
		undo.registerUndo(
			withTarget: self,
			selector: #selector(clearCachedProperties(_:undo:)),
			objects: [object, undo])
		object.clearCachedProperties()
	}

	@objc
	func setTags(_ dict: [String: String], for object: OsmBaseObject) {
		let localDict = OsmTags.DictWithTagsTruncatedTo255(dict)
		registerUndoCommentString(NSLocalizedString("set tags", comment: ""))
		object.setTags(localDict, undo: undoManager)
	}

	func createNode(atLocation loc: LatLon) -> OsmNode {
		let node = OsmNode(asUserCreated: AppDelegate.shared.userName ?? "")
		node.setLongitude(loc.lon, latitude: loc.lat, undo: nil)
		node.setDeleted(true, undo: nil)
		setConstructed(node)
		nodes[node.ident] = node

		registerUndoCommentString(NSLocalizedString("create node", comment: ""))
		node.setDeleted(false, undo: undoManager)
		spatial.addMember(node, undo: undoManager)
		return node
	}

	func createWay() -> OsmWay {
		let way = OsmWay(asUserCreated: AppDelegate.shared.userName ?? "")
		way.setDeleted(true, undo: nil)
		setConstructed(way)
		ways[way.ident] = way

		registerUndoCommentString(NSLocalizedString("create way", comment: ""))
		way.setDeleted(false, undo: undoManager)
		return way
	}

	func createRelation() -> OsmRelation {
		let relation = OsmRelation(asUserCreated: AppDelegate.shared.userName ?? "")
		relation.setDeleted(true, undo: nil)
		setConstructed(relation)
		relations[relation.ident] = relation

		registerUndoCommentString(NSLocalizedString("create relation", comment: ""))
		relation.setDeleted(false, undo: undoManager)
		return relation
	}

	func remove(fromParentRelationsUnsafe object: OsmBaseObject) {
		while object.parentRelations.count != 0 {
			if let relation = object.parentRelations.last {
				var memberIndex = 0
				while memberIndex < relation.members.count {
					let member = relation.members[memberIndex]
					if member.obj == object {
						deleteMember(inRelationUnsafe: relation, index: memberIndex, deletingRelationIfEmpty: true)
					} else {
						memberIndex += 1
					}
				}
			}
		}
	}

	func deleteNodeUnsafe(_ node: OsmNode) {
		assert(node.wayCount == 0)
		registerUndoCommentString(NSLocalizedString("delete node", comment: ""))
		remove(fromParentRelationsUnsafe: node)
		node.setDeleted(true, undo: undoManager)
		_ = spatial.removeMember(node, undo: undoManager)
	}

	func deleteWayUnsafe(_ way: OsmWay) {
		registerUndoCommentString(NSLocalizedString("delete way", comment: ""))

		remove(fromParentRelationsUnsafe: way)

		while way.nodes.count != 0 {
			let node = way.nodes.last!
			deleteNodeUnsafe(inWay: way, index: way.nodes.count - 1, preserveNode: node.hasInterestingTags())
		}
		way.setDeleted(true, undo: undoManager)
		_ = spatial.removeMember(way, undo: undoManager)
	}

	func deleteRelationUnsafe(_ relation: OsmRelation) {
		let message = relation.isRestriction()
			? NSLocalizedString("delete restriction", comment: "")
			: relation.isMultipolygon()
			? NSLocalizedString("delete multipolygon", comment: "")
			: relation.isRoute()
			? NSLocalizedString("delete route", comment: "")
			: NSLocalizedString("delete relation", comment: "")
		registerUndoCommentString(message)

		_ = spatial.removeMember(relation, undo: undoManager)

		remove(fromParentRelationsUnsafe: relation)

		while relation.members.count != 0 {
			relation.removeMemberAtIndex(relation.members.count - 1, undo: undoManager)
		}
		relation.setDeleted(true, undo: undoManager)
	}

	func addNodeUnsafe(_ node: OsmNode, to way: OsmWay, at index: Int) {
		registerUndoCommentString(NSLocalizedString("add node to way", comment: ""))
		let origBox = way.boundingBox
		way.addNode(node, atIndex: index, undo: undoManager)
		spatial.updateMember(way, fromBox: origBox, undo: undoManager)
	}

	func deleteNodeUnsafe(inWay way: OsmWay, index: Int, preserveNode: Bool) {
		registerUndoCommentString(NSLocalizedString("delete node from way", comment: ""))
		let node = way.nodes[index]
		DbgAssert(node.wayCount > 0)

		let bbox = way.boundingBox
		way.removeNodeAtIndex(index, undo: undoManager)
		// if removing the node leads to 2 identical nodes being consecutive delete one of them as well
		while index > 0,
		      index < way.nodes.count,
		      way.nodes[index - 1] == way.nodes[index]
		{
			way.removeNodeAtIndex(index, undo: undoManager)
		}
		spatial.updateMember(way, fromBox: bbox, undo: undoManager)

		if node.wayCount == 0, !preserveNode {
			deleteNodeUnsafe(node)
		}
	}

	// MARK: external editing commands

	func setLatLon(_ latLon: LatLon, forNode node: OsmNode) {
		registerUndoCommentString(NSLocalizedString("move", comment: ""))

		// need to update all ways/relation which contain the node
		let parents = objectsContaining(node).map({ ($0, $0.boundingBox) })
		let bboxNode = node.boundingBox
		node.setLongitude(latLon.lon, latitude: latLon.lat, undo: undoManager)
		spatial.updateMember(node, fromBox: bboxNode, undo: undoManager)

		for (parent, box) in parents {
			clearCachedProperties(parent, undo: undoManager)
			parent.computeBoundingBox()
			spatial.updateMember(parent, fromBox: box, undo: undoManager)
		}
	}

	func addMemberUnsafe(_ member: OsmMember?, to relation: OsmRelation?, at index: Int) {
		if let member = member, let relation = relation {
			registerUndoCommentString(NSLocalizedString("add object to relation", comment: ""))
			let bbox = relation.boundingBox
			relation.addMember(member, atIndex: index, undo: undoManager)
			spatial.updateMember(relation, fromBox: bbox, undo: undoManager)
			updateMultipolygonRelationRoles(relation)
		}
	}

	func deleteMember(inRelationUnsafe relation: OsmRelation, index: Int, deletingRelationIfEmpty: Bool) {
		if deletingRelationIfEmpty, relation.members.count == 1 {
			// deleting last member of relation, so delete relation
			deleteRelationUnsafe(relation)
		} else {
			AppDelegate.shared.mapView.mapData.consistencyCheck()

			registerUndoCommentString(NSLocalizedString("delete object from relation", comment: ""))
			let bbox = relation.boundingBox
			relation.removeMemberAtIndex(index, undo: undoManager)
			spatial.updateMember(relation, fromBox: bbox, undo: undoManager)
			AppDelegate.shared.mapView.mapData.consistencyCheck()

			updateMultipolygonRelationRoles(relation)
		}
	}

	func updateMembersUnsafe(_ memberList: [OsmMember]?, in relation: OsmRelation?) {
		if let memberList = memberList, let relation = relation {
			registerUndoCommentString(NSLocalizedString("update relation members", comment: ""))
			let bbox = relation.boundingBox
			relation.assignMembers(memberList, undo: undoManager)
			spatial.updateMember(relation, fromBox: bbox, undo: undoManager)
		}
	}

	// MARK: Undo manager interface

	@discardableResult
	func undo() -> [String: Any]? {
		let comment = undoManager.undo()
		if let undoCommentCallback = undoCommentCallback {
			undoCommentCallback(true, comment ?? [:])
		}
		return comment
	}

	@discardableResult
	func redo() -> [String: Any]? {
		let comment = undoManager.redo()
		if let undoCommentCallback = undoCommentCallback {
			undoCommentCallback(false, comment ?? [:])
		}
		consistencyCheck()
		return comment
	}

	func canUndo() -> Bool {
		return undoManager.canUndo
	}

	func canRedo() -> Bool {
		return undoManager.canRedo
	}

	func addChangeCallback(_ callback: @escaping () -> Void) {
		NotificationCenter.default.addObserver(
			forName: NSNotification.Name(MyUndoManager.UndoManagerDidChangeNotification),
			object: undoManager,
			queue: nil,
			using: { _ in
				callback()
			})
	}

	func beginUndoGrouping() {
		undoManager.beginUndoGrouping()
	}

	func endUndoGrouping() {
		undoManager.endUndoGrouping()
	}

	func removeMostRecentRedo() {
		undoManager.removeMostRecentRedo()
	}

	func clearUndoStack() {
		undoManager.removeAllActions()
	}

	func setConstructed(_ object: OsmBaseObject) {
		object.setConstructed()
	}

	func registerUndoCommentContext(_ context: [String: Any]) {
		undoManager.registerUndoComment(context)
	}

	func registerUndoCommentString(_ comment: String) {
		if let context = undoContextForComment?(comment) {
			registerUndoCommentContext(context)
		}
	}

	func undoManagerDescription() -> String {
		return undoManager.description
	}

	// MARK: Server query

	// returns a list of ServerQuery objects
	private class func coalesceQuadQueries(_ quadList: [QuadBox]) -> [ServerQuery] {
		// make a query for every quad
		var queries = quadList.map { quad -> ServerQuery in
			let query = ServerQuery()
			query.quadList = [quad]
			query.rect = quad.rect
			return query
		}
		loop: while true {
			for q in queries {
				if let index = queries.firstIndex(where: {
					if q.rect.size.width == $0.rect.size.width {
						// equal widths
						if q.rect.origin.x == $0.rect.origin.x {
							// matching left-right sides
							if q.rect.origin.y == $0.rect.origin.y + $0.rect.size.height ||
								q.rect.origin.y + q.rect.size.height == $0.rect.origin.y
							{
								// stacked vertically
								return true
							}
						}
					}
					if q.rect.size.height == $0.rect.size.height {
						// equal heights
						if q.rect.origin.y == $0.rect.origin.y {
							// matching top-bottom
							if q.rect.origin.x == $0.rect.origin.x + $0.rect.size.width ||
								q.rect.origin.x + q.rect.size.width == $0.rect.origin.x
							{
								// stacked horizontally
								return true
							}
						}
					}
					return false
				}) {
					// combine them
					let other = queries[index]
					let newRect = q.rect.union(other.rect)
#if DEBUG
					let areaDiff = newRect.size.width * newRect.size.height
						- (q.rect.size.width * q.rect.size.height + other.rect.size.width * other.rect.size.height)
					assert(areaDiff == 0.0)
#endif
					q.rect = newRect
					q.quadList += other.quadList
					queries.remove(at: index)
					continue loop
				}
			}
			break
		}
		return queries
	}

	/// Download any data not yet downloaded for the given region
	/// Because a single request may be converted to multiple server requests the completion callback
	/// may be called one or more times, indicating whether all requests have been satisfied, along with an error value
	///
	/// The process for performing a download is:
	/// - The user moves the screen, which creates a new viewable region
	///	- We ask QuadMap for a set of QuadBoxes that tile the region, less any quads that we already downloaded (missingQuads)
	///		- The returned quads are marked as "busy" by QuadMap, meaning it won't return them on a subsequent query
	///			before the current query completes. The quads must be marked non-busy via a call to updateDownloadStatus()
	///			once we're done with them. updateDownloadStatus() takes a success flag indicating that the quad now contains data.
	///	- We then combine (coalesceQuadQueries) adjacent quads into a single rectangle
	///	- We submit the rect to the server
	///	- Once we've successfully fetched the data for the rect we tell the QuadMap that it can mark the given QuadBoxes as downloaded
	func downloadMissingData(inRect rect: OSMRect,
	                         withProgress progress: MapViewProgress,
	                         didUpdate: @escaping (_ error: Error?) -> Void)
	{
		// get list of new quads to fetch
		let newQuads = region.missingQuads(forRect: rect)
		if newQuads.count == 0 {
			return
		}

#if DEBUG
		AppDelegate.shared.mainView.mapLayersView.quadDownloadLayer?.setNeedsLayout()
#endif

		// Convert the list of quads into server queries. We look for quads that are adjacent
		// and can be combined into larger rectangular queries. This usually results in
		// 1-2 queries even though there are many quads.
		let queryList = OsmMapData.coalesceQuadQueries(newQuads)

		// submit each query to the server and process the results
		for query in queryList {
			progress.progressIncrement(1)

			let rc = query.rect
			let url = OSM_SERVER.apiURL
				.appendingPathComponent("api/0.6/map")
				.appendingQueryItems([
					"bbox": "\(rc.origin.x),\(rc.origin.y),\(rc.origin.x + rc.size.width),\(rc.origin.y + rc.size.height)"
				])
			Task {
				let result: Result<OsmDownloadData, Error>
				do {
					let data = try await OsmDownloader.osmData(forUrl: url)
					result = .success(data)
				} catch {
					result = .failure(error)
				}
				await MainActor.run {
					let didGetData: Bool
					switch result {
					case let .success(data):
						// merge data
						print("Downloaded \(data.nodes.count + data.ways.count + data.relations.count) objects")
						try? self.merge(data, savingToDatabase: true)
						didGetData = true
						didUpdate(nil) // data was updated
					case let .failure(error):
						didGetData = false
						didUpdate(error) // error fetching data
					}

					for quadBox in query.quadList {
						self.region.updateDownloadStatus(quadBox, success: didGetData)
					}
					progress.progressDecrement()

#if DEBUG
					AppDelegate.shared.mainView.mapLayersView.quadDownloadLayer?.setNeedsLayout()
#endif
				}
			}
		}
	}

	func cancelCurrentDownloads() async {
		if DownloadThreadPool.osmPool.downloadsInProgress() > 0 {
			await DownloadThreadPool.osmPool.cancelAllDownloads()
		}
	}

	// MARK: Download

	func merge(_ newData: OsmDownloadData, savingToDatabase save: Bool) throws {
		if newData.nodes.count + newData.ways.count + newData.relations.count == 0 {
			return
		}
		var newNodes: [OsmNode] = []
		var newWays: [OsmWay] = []
		var newRelations: [OsmRelation] = []
		newNodes.reserveCapacity(newData.nodes.count)
		newWays.reserveCapacity(newData.ways.count)
		newRelations.reserveCapacity(newData.relations.count)

#if DEBUG
		consistencyCheck()
#endif

#if DEBUG
		for value in nodes.values {
			assert(value.constructed())
		}
		for value in ways.values {
			assert(value.constructed())
		}
		for value in relations.values {
			assert(value.constructed())
		}
#endif

		for newNode in newData.nodes {
			if let currentNode = nodes[newNode.ident] {
				if currentNode.version < newNode.version {
#if DEBUG
					print("update node \(newNode.ident): \(currentNode.version) -> \(newNode.version)")
#endif
					// already exists, so do an in-place update
					let bbox = currentNode.boundingBox
					currentNode.serverUpdate(with: newNode)
					spatial.updateMember(currentNode, fromBox: bbox, undo: nil)
					newNodes.append(currentNode)
				}
			} else {
				nodes[newNode.ident] = newNode
				spatial.addMember(newNode, undo: nil)
				newNodes.append(newNode)
			}
		}

		for newWay in newData.ways {
			if let currentWay = ways[newWay.ident] {
				if currentWay.version < newWay.version {
#if DEBUG
					print("update way \(newWay.ident): \(currentWay.version) -> \(newWay.version)")
#endif
					let bbox = currentWay.boundingBox
					currentWay.serverUpdate(with: newWay)
					try currentWay.resolveToMapData(self)
					spatial.updateMember(currentWay, fromBox: bbox, undo: nil)
					newWays.append(currentWay)
				}
			} else {
				ways[newWay.ident] = newWay
				try newWay.resolveToMapData(self)
				spatial.addMember(newWay, undo: nil)
				newWays.append(newWay)
			}
		}

		for newRelation in newData.relations {
			if let currentRelation = relations[newRelation.ident] {
				if currentRelation.version < newRelation.version {
#if DEBUG
					print("update relation \(newRelation.ident): \(currentRelation.version) -> \(newRelation.version)")
#endif
					let bbox = currentRelation.boundingBox
					currentRelation.serverUpdate(with: newRelation)
					spatial.updateMember(currentRelation, fromBox: bbox, undo: nil)
					newRelations.append(currentRelation)
				}
			} else {
				relations[newRelation.ident] = newRelation
				spatial.addMember(newRelation, undo: nil)
				newRelations.append(newRelation)
			}
		}

		// All relations, including old ones, need to be resolved against new objects
		// In addition we need to recompute bounding boxes of relations every time
		// in case a member is another relation that changed size.
		var didChange = true
		while didChange {
			didChange = false
			for relation in relations.values {
				let bbox = relation.boundingBox
				relation.clearCachedProperties()
				didChange = relation.resolveToMapData(self) || didChange
				spatial.updateMember(relation, fromBox: bbox, undo: nil)
			}
		}

		for node in newData.nodes {
			node.setConstructed()
		}
		for way in newData.ways {
			way.setConstructed()
		}
		for relation in newData.relations {
			relation.setConstructed()
		}

#if DEBUG
		for value in nodes.values {
			assert(value.constructed())
		}
		for value in ways.values {
			assert(value.constructed())
		}
		for value in relations.values {
			assert(value.constructed())
		}
#endif

		consistencyCheck()

		// store new nodes in database
		if save {
			sqlSave(
				saveNodes: newNodes,
				saveWays: newWays,
				saveRelations: newRelations,
				deleteNodes: [],
				deleteWays: [],
				deleteRelations: [],
				isUpdate: false)

			// purge old data
			MainActor.runAfter(nanoseconds: 1000_000000) {
				AppDelegate.shared.mapView.discardStaleData()
			}
		}
	}

	// MARK: Upload

	/// Adds a changeset=* value to each node/way/relation in the XML
	class func addChangesetId(_ changesetID: Int64, toXML xmlDoc: DDXMLDocument) {
		for changeType in xmlDoc.rootElement()?.children ?? [] {
			guard let changeType = changeType as? DDXMLElement else {
				continue
			}
			// create/modify/delete
			for osmObject in changeType.children ?? [] {
				guard let osmObject = osmObject as? DDXMLElement else {
					continue
				}
				// node/way/relation
				if let attribute = DDXMLNode.attribute(
					withName: "changeset",
					stringValue: String(changesetID)) as? DDXMLNode
				{
					osmObject.addAttribute(attribute)
				}
			}
		}
	}

	func uploadChangeset(xml xmlChanges: DDXMLDocument,
	                     changesetID: Int64,
	                     generator: String,
	                     retries: Int) async throws
	{
		let postData = try await OSM_SERVER.putRequest(relativeUrl: "api/0.6/changeset/\(changesetID)/upload",
		                                               queryItems: [:],
		                                               method: "POST",
		                                               xml: xmlChanges)

		let response = String(decoding: postData, as: UTF8.self)

		if retries > 0, response.hasPrefix("Version mismatch") {
			// update the bad element and retry
			DLog("Upload error: \(response)")
			// "Version mismatch: Provided %d, server had: %d of %[a-zA-Z] %lld"
			let scanner = Scanner(string: response)
			guard let _ = scanner.scanString("Version mismatch: Provided"),
			      let localVersion = scanner.scanInt(),
			      let _ = scanner.scanString(", server had:"),
			      let serverVersion = scanner.scanInt(),
			      let _ = scanner.scanString("of"),
			      let objType2 = scanner.scanCharacters(from: CharacterSet.alphanumerics),
			      let objId = scanner.scanInt64()
			else {
				throw OsmMapDataError.badServerUpdateValue
			}
			print("Updating object from version \(localVersion) to \(serverVersion)")
			let objType = objType2.lowercased()
			var url3 = OSM_SERVER.apiURL.appendingPathComponent("api/0.6/\(objType)/\(objId)")
			if objType == "way" || objType == "relation" {
				url3 = url3.appendingPathComponent("full")
			}

			let data = try await OsmDownloader.osmData(forUrl: url3)
			try await MainActor.run {
				// update the bad element
				try self.merge(data, savingToDatabase: true)
			}
			// try again:
			try await self.generateXMLandUploadChangeset(changesetID,
			                                             generator: generator,
			                                             retries: retries - 1)
			return
		}

		// we expect to receive an XML document with server updates
		if !response.hasPrefix("<?xml") {
			throw OsmMapDataError.otherError(response)
		}

		let diffDoc: DDXMLDocument = try DDXMLDocument(data: postData, options: 0)

		guard
			let diffResult = diffDoc.rootElement(),
			diffResult.name == "diffResult"
		else {
			throw OsmMapDataError.otherError("Upload failed: invalid server respsonse")
		}
		let timestamp = Date()

		var sqlUpdate: [OsmBaseObject: Bool] = [:]
		for element in diffResult.children ?? [] {
			guard let element = element as? DDXMLElement else {
				continue
			}
			let name = element.name
			let oldId = Int64(element.attribute(forName: "old_id")?.stringValue ?? "0")!
			let newId = Int64(element.attribute(forName: "new_id")?.stringValue ?? "0")!
			let newVersion = Int(element.attribute(forName: "new_version")?.stringValue ?? "0")!

			if name == "node" {
				OsmMapData.updateObjectDictionary(
					&nodes,
					oldId: oldId,
					newId: newId,
					version: newVersion,
					changeset: changesetID,
					timestamp: timestamp,
					sqlUpdate: &sqlUpdate)
			} else if name == "way" {
				OsmMapData.updateObjectDictionary(
					&ways,
					oldId: oldId,
					newId: newId,
					version: newVersion,
					changeset: changesetID,
					timestamp: timestamp,
					sqlUpdate: &sqlUpdate)
			} else if name == "relation" {
				OsmMapData.updateObjectDictionary(
					&relations,
					oldId: oldId,
					newId: newId,
					version: newVersion,
					changeset: changesetID,
					timestamp: timestamp,
					sqlUpdate: &sqlUpdate)
			} else {
				DLog("Bad upload diff document")
			}
		}

		updateSql(sqlUpdate)

		_ = try await OSM_SERVER.putRequest(relativeUrl: "api/0.6/changeset/\(changesetID)/close",
		                                    queryItems: [:],
		                                    method: "PUT",
		                                    xml: nil)

		// reset undo stack after upload so user can't accidently undo a commit (wouldn't work anyhow because we don't undo version numbers on objects)
		await MainActor.run {
			undoManager.removeAllActions()
		}
	}

	// upload xml generated by mapData
	func generateXMLandUploadChangeset(_ changesetID: Int64,
	                                   generator: String,
	                                   retries: Int) async throws
	{
		guard
			let xmlChanges = OsmXmlGenerator.createXmlFor(nodes: nodes.values,
			                                              ways: ways.values,
			                                              relations: relations.values,
			                                              generator: generator)
		else {
			throw OsmMapDataError.badXML
		}
		OsmMapData.addChangesetId(changesetID, toXML: xmlChanges)
		try await uploadChangeset(xml: xmlChanges,
		                          changesetID: changesetID,
		                          generator: generator,
		                          retries: retries)
	}

	static func updateObjectDictionary<T: OsmBaseObject>(
		_ dictionary: inout [OsmIdentifier: T],
		oldId: OsmIdentifier,
		newId: OsmIdentifier,
		version newVersion: Int,
		changeset: Int64,
		timestamp: Date,
		sqlUpdate: inout [OsmBaseObject: Bool])
	{
		let object = dictionary[oldId]!
		assert(object.ident == oldId)
		if newVersion == 0, newId == 0 {
			// Delete object for real
			// When a way is deleted we delete the nodes also, but they aren't marked as deleted in the graph.
			// If nodes are still in use by another way the newId and newVersion will be set and we won't take this path.
			assert(newId == 0 && newVersion == 0)
			dictionary.removeValue(forKey: object.ident)
			sqlUpdate[object] = false // mark for deletion
			return
		}

		assert(newVersion > 0)
		object.serverUpdate(ident: newId,
		                    version: newVersion,
		                    changeset: changeset,
		                    timestamp: timestamp)
		sqlUpdate[object] = true // mark for insertion

		if oldId != newId {
			// replace placeholder object with new server provided identity
			assert(oldId < 0 && newId > 0)
			dictionary.removeValue(forKey: oldId)
			dictionary[object.ident] = object
		} else {
			assert(oldId > 0)
		}
		object.resetModifyCount()
	}

	class func encodeBase64(_ plainText: String) -> String {
		let data = plainText.data(using: .utf8)!
		let output = data.base64EncodedString(options: [])
		return output
	}

	enum OsmServerError: LocalizedError {
		case changesetIdNotDecimal(String)

		public var errorDescription: String? {
			switch self {
			case let .changesetIdNotDecimal(text): return "OsmServerError.changesetIdNotDecimal(\(text)"
			}
		}
	}

	// create a new changeset to upload to
	func openNewChangeset(withComment comment: String,
	                      source: String,
	                      imagery: String,
	                      locale: String) async throws -> Int64
	{
		let creator = "\(await AppDelegate.appName) \(await AppDelegate.appVersion)"
		var tags = [
			"created_by": creator
		]
		if comment.count != 0 {
			tags["comment"] = comment
		}
		if imagery.count != 0 {
			tags["imagery_used"] = imagery
		}
		if source.count != 0 {
			tags["source"] = source
		}
		if locale.count != 0 {
			tags["locale"] = locale
		}
		guard
			let xmlCreate = OsmXmlGenerator.createXml(withType: "changeset", tags: tags)
		else {
			throw OsmMapDataError.otherError("Failed to create OSM XML for creating a new changeset.")
		}
		let putData = try await OSM_SERVER.putRequest(relativeUrl: "api/0.6/changeset/create",
		                                              queryItems: [:],
		                                              method: "PUT",
		                                              xml: xmlCreate)
		let responseString = String(decoding: putData, as: UTF8.self)
		if let changeset = Int64(responseString) {
			// The response string only contains the digits 0 through 9.
			// Assume that the request was successful and that the server responded with a changeset ID.
			return changeset
		} else {
			// The response did not only contain digits; treat this as an error.
			throw OsmServerError.changesetIdNotDecimal(responseString)
		}
	}

	/// Upload xml generated by mapData.
	/// The procedure is:
	///		- Ask the server to open a changeset and retrieve the changesetID
	///		- Loop (implemented via recursion since calls are async):
	///			- Generate XML for user modifications
	///			- Insert the changesetID into the XML
	///			- Upload the XML to the server
	///			- If success then break loop
	///			- Otherwise parse the result for version mismatch
	///			- Download the server's version of the object that doesn't match
	///			- Integrate the server version into our data
	///			- Repeat until either there is no mismatch, or retry count is reached
	///		- Ask the server to close the changeset
	func uploadChangeset(withComment comment: String,
	                     source: String,
	                     imagery: String,
	                     generator: String,
	                     locale: String) async throws
	{
		let changesetID = try await openNewChangeset(withComment: comment,
		                                             source: source,
		                                             imagery: imagery,
		                                             locale: locale)
		try await generateXMLandUploadChangeset(changesetID,
		                                        generator: generator,
		                                        retries: 20)
	}

	// upload xml edited by user
	func openChangesetAndUpload(xml xmlChanges: DDXMLDocument,
	                            comment: String,
	                            source: String,
	                            imagery: String,
	                            generator: String,
	                            locale: String) async throws
	{
		consistencyCheck()

		let changesetID = try await openNewChangeset(
			withComment: comment,
			source: source,
			imagery: imagery,
			locale: locale)
		OsmMapData.addChangesetId(changesetID, toXML: xmlChanges)
		try await uploadChangeset(xml: xmlChanges,
		                          changesetID: changesetID,
		                          generator: generator,
		                          retries: 0)
	}

	func changesetAsAttributedString() -> NSAttributedString? {
		guard let doc = OsmXmlGenerator.createXmlFor(nodes: nodes.values,
		                                             ways: ways.values,
		                                             relations: relations.values,
		                                             generator: AppDelegate.shared.generator)
		else {
			return nil
		}
		return OsmXmlGenerator.attributedStringForXML(doc)
	}

	func changesetAsXml() -> String? {
		guard let xml = OsmXmlGenerator.createXmlFor(nodes: nodes.values,
		                                             ways: ways.values,
		                                             relations: relations.values,
		                                             generator: AppDelegate.shared.generator)
		else {
			return nil
		}
		return xml.xmlString(withOptions: UInt(XMLNodePrettyPrint))
	}

	// MARK: Init/Save/Restore

	func initCommon() {
		setupPeriodicSaveTimer()
	}

	deinit {
		NotificationCenter.default.removeObserver(
			self,
			name: NSNotification.Name(MyUndoManager.UndoManagerDidChangeNotification),
			object: undoManager)
		periodicSaveTimer?.invalidate()
	}

	override init() {
		nodes = [:]
		ways = [:]
		relations = [:]
		undoContextForComment = nil
		region = QuadMap(encodingContentsOnSave: true)
		spatial = QuadMap(encodingContentsOnSave: false)
		undoManager = MyUndoManager()

		super.init()

		initCommon()
	}

	func encode(with coder: NSCoder) {
		coder.encode(nodes, forKey: "nodes")
		coder.encode(ways, forKey: "ways")
		coder.encode(relations, forKey: "relations")
		coder.encode(region, forKey: "region")
		coder.encode(spatial, forKey: "spatial")
		coder.encode(undoManager, forKey: "undoManager")
	}

	required init?(coder: NSCoder) {
		guard
			let nodes = coder.decodeObject(forKey: "nodes") as? [OsmIdentifier: OsmNode],
			let ways = coder.decodeObject(forKey: "ways") as? [OsmIdentifier: OsmWay],
			let relations = coder.decodeObject(forKey: "relations") as? [OsmIdentifier: OsmRelation],
			let region = coder.decodeObject(forKey: "region") as? QuadMap,
			let spatial = coder.decodeObject(forKey: "spatial") as? QuadMap,
			let undoManager = coder.decodeObject(forKey: "undoManager") as? MyUndoManager
		else { return nil }

		self.nodes = nodes
		self.ways = ways
		self.relations = relations
		self.region = region
		self.spatial = spatial
		self.undoManager = undoManager

		super.init()

		initCommon()

		if region.isEmpty() {
			// This path taken if we came from a quick-save
			// didn't save spatial, so add everything back into it
			enumerateObjects(usingBlock: { object in
				self.spatial.addMember(object, undo: nil)
			})
		}
	}

	func modifiedObjects() -> OsmDownloadData {
		var undoObjects = undoManager.objectRefs()
		let modWays = undoObjects.compactMap({ $0 as? OsmWay })
		for way in modWays {
			undoObjects.formUnion(way.nodes)
		}
		let modNodes = undoObjects.compactMap({ $0 as? OsmNode })
		let modRelations = undoObjects.compactMap({ $0 as? OsmRelation })

#if DEBUG
		// Verify that every modified object exists in the UndoManager.
		let n = Set<OsmNode>(nodes.values.filter({ $0.isModified() }))
		let w = Set<OsmWay>(ways.values.filter({ $0.isModified() }))
		let r = Set<OsmRelation>(relations.values.filter({ $0.isModified() }))
		assert(n.isSubset(of: modNodes))
		assert(w.isSubset(of: modWays))
		assert(r.isSubset(of: modRelations))
#endif

		let modified = OsmDownloadData(nodes: modNodes,
		                               ways: modWays,
		                               relations: modRelations)
		return modified
	}

	func purgeExceptUndo() {
		// deresolve relations to get rid of retain cycles via parentRelations property
		for rel in relations.values {
			rel.deresolveRefs()
		}

		nodes.removeAll()
		ways.removeAll()
		relations.removeAll()
		region.rootQuad.reset()
		spatial.rootQuad.reset()

		Database.dispatchQueue.async(execute: {
			try? Database.delete(withName: "")
		})
	}

	func purgeHard() {
		purgeExceptUndo()
		undoManager.removeAllActions()
	}

	func purgeSoft() {
		// get a list of all dirty objects
		var dirty: Set<OsmBaseObject> = []
		dirty.formUnion(nodes.values.compactMap({ $0.isModified() ? $0 : nil }))
		dirty.formUnion(ways.values.compactMap({ $0.isModified() ? $0 : nil }))
		dirty.formUnion(relations.values.compactMap({ $0.isModified() ? $0 : nil }))

		// get objects referenced by undo manager
		let undoRefs = undoManager.objectRefs()
		dirty = dirty.union(undoRefs)

		// add nodes in ways to dirty set, because we must preserve them to maintain consistency
		dirty.formUnion(dirty.flatMap({ ($0 as? OsmWay)?.nodes ?? [] }))

		// purge everything
		purgeExceptUndo()

		// put dirty stuff back in
		for object in dirty {
			if let obj = object as? OsmNode {
				nodes[object.ident] = obj
			} else if let obj = object as? OsmWay {
				ways[object.ident] = obj
			} else if let obj = object as? OsmRelation {
				relations[object.ident] = obj
			} else {
				assertionFailure()
			}
		}

		// reset way counts in nodes
		for node in nodes.values {
			node.setWayCount(0, undo: nil)
		}
		for way in ways.values {
			for node in way.nodes {
				node.setWayCount(node.wayCount + 1, undo: nil)
			}
		}

		// restore relation references
		for rel in dirty {
			guard let rel = rel as? OsmRelation else {
				continue
			}
			_ = rel.resolveToMapData(self)
		}

		// rebuild spatial
		for obj in dirty {
			if !obj.deleted {
				spatial.addMember(obj, undo: nil)
			}
		}

		consistencyCheck()
	}

	static func pathToArchiveFile() -> URL {
		return ArchivePath.osmDataArchive.url()
	}

	func sqlSave(
		saveNodes: [OsmNode],
		saveWays: [OsmWay],
		saveRelations: [OsmRelation],
		deleteNodes: [OsmNode],
		deleteWays: [OsmWay],
		deleteRelations: [OsmRelation],
		isUpdate: Bool)
	{
		if (saveNodes.count + saveWays.count + saveRelations.count +
			deleteNodes.count + deleteWays.count + deleteRelations.count) == 0
		{
			return
		}
		Database.dispatchQueue.async(execute: { [self] in
			var t = CACurrentMediaTime()
			let ok: Bool
			do {
				let db = try Database(name: "")
				try db.createTables()
				try db.save(saveNodes: saveNodes, saveWays: saveWays, saveRelations: saveRelations,
				            deleteNodes: deleteNodes, deleteWays: deleteWays, deleteRelations: deleteRelations,
				            isUpdate: isUpdate)
				ok = true
			} catch {
				try? Database.delete(withName: "")
				ok = false
			}
			t = CACurrentMediaTime() - t

			DispatchQueue.main.async(execute: { [self] in
				DLog(
					"\(t > 1.0 ? "*** " : "")sql save \(saveNodes.count + saveWays.count + saveRelations.count) objects, time = \(t) (\(Int(nodeCount()) + Int(wayCount()) + Int(relationCount()))) objects total)")
				if !ok {
					// database failure
					region.rootQuad.reset()
				}
				archiveModifiedData()
			})
		})
	}

	// Returns true if any objects were discarded
	func discardStaleData(maxObjects: Int = 100000, maxAge: Int = 24 * 60 * 60) -> Bool {
#if DEBUG
		let minTimeBetweenDiscards = 5.0 // seconds
#else
		let minTimeBetweenDiscards = 60.0 // seconds
#endif
		if modificationCount() > 0 {
			return false
		}
		let undoObjects = undoManager.objectRefs()

		// don't discard too frequently
		let now = Date()
		if now.timeIntervalSince(previousDiscardDate) < minTimeBetweenDiscards {
			return false
		}

		// remove objects if they are too old, or we have too many:
		var oldest = Date(timeIntervalSinceNow: -Double(maxAge))

		// figure out what fraction of objects we should trim to get under the threshold.
		var fraction = Double(nodes.count + ways.count + relations.count) / Double(maxObjects)
		if fraction <= 1.0 {
			// The number of objects is acceptable. We can still trim based on age.
			fraction = 0.0
		} else {
			fraction = 1.0 - 1.0 / fraction
			if fraction < 0.3 {
				fraction = 0.3 // don't waste resources trimming tiny quantities
			}
		}

		defer {
			consistencyCheck()
		}

		var t = CACurrentMediaTime()

		func deresolveRelations() {
			// deresolve relation references before starting, because if we delete a relation
			// we don't want a reference to be left dangling in parentRelations:
			for relation in relations.values {
				relation.deresolveRefs()
			}
		}

		var didDeresolveRelations = false

		var didExpand = false
		while true {
			guard
				// get rid of old quads marked as downloaded
				let newOldest = region.discardOldestQuads(fraction, oldest: oldest)
			else {
				if !didExpand {
					return false // nothing to discard
				}
				break // nothing more to drop
			}
			oldest = newOldest

#if DEBUG
			let interval = now.timeIntervalSince(oldest)
			if interval < 2 * 60 {
				print(String(format: "Discarding %f%% stale data %ld seconds old\n", 100 * fraction,
				             Int(ceil(interval))))
			} else if interval < 60 * 60 {
				print(String(format: "Discarding %f%% stale data %ld minutes old\n", 100 * fraction,
				             Int(interval) / 60))
			} else {
				print(String(format: "Discarding %f%% stale data %ld hours old\n", 100 * fraction,
				             Int(interval) / 60 / 60))
			}
#endif

			previousDiscardDate = Date.distantFuture // mark as distant future until we're done discarding

			// now go through all objects and determine which are no longer in a downloaded region
			var removeRelations: [OsmIdentifier] = []
			var removeWays: [OsmIdentifier] = []
			var removeNodes: [OsmIdentifier] = []

			// only remove relation if no members are covered by region
			for (ident, relation) in relations
				where !relation.isModified() && !undoObjects.contains(relation)
			{
				let memberObjects = relation.allMemberObjects()
				var covered = false
				for obj in memberObjects {
					if let node = obj as? OsmNode {
						if region.pointIsCovered(node.location()) {
							covered = true
							break
						}
					} else if let way = obj as? OsmWay {
						if region.anyNodeIsCovered(way.nodes) {
							covered = true
							break
						}
					}
				}
				if !covered {
					removeRelations.append(ident)
				}
			}

			// only remove way if no nodes are covered by region
			for (ident, way) in ways
				where !way.isModified() && !undoObjects.contains(way)
			{
				if !region.anyNodeIsCovered(way.nodes) {
					removeWays.append(ident)
					for node in way.nodes {
						DbgAssert(node.wayCount > 0)
						node.setWayCount(node.wayCount - 1, undo: nil)
					}
				}
			}

			// only remove nodes if they are not covered and they don't belong to a way
			for (ident, node) in nodes
				where !node.isModified() && !undoObjects.contains(node)
			{
				if node.wayCount == 0 {
					if !region.pointIsCovered(node.location()) {
						removeNodes.append(ident)
					}
				}
			}

			if !didDeresolveRelations,
			   removeNodes.count + removeWays.count + removeRelations.count > 0
			{
				deresolveRelations()
				didDeresolveRelations = true
			}

			// remove from dictionaries
			for k in removeNodes {
				nodes.removeValue(forKey: k)
			}
			for k in removeWays {
				ways.removeValue(forKey: k)
			}
			for k in removeRelations {
				relations.removeValue(forKey: k)
			}

			print(String(format: "remove %ld objects", removeNodes.count + removeWays.count + removeRelations.count))

			// If after deleting some objects we aren't much larger than the maximum then we're done
			if Double(nodes.count + ways.count + relations.count) < (Double(maxObjects) * 1.3) {
				// good enough
				if !didExpand,
				   !didDeresolveRelations,
				   removeNodes.count + removeWays.count + removeRelations.count == 0
				{
					previousDiscardDate = now
					return false
				}
				break
			}

			// we still have way too much stuff, need to be more aggressive
			didExpand = true
			fraction = 0.3
		}

		// remove objects from spatial that are no longer in a dictionary
		spatial.deleteObjects(withPredicate: { [self] obj in
			switch obj {
			case is OsmNode:
				return nodes[obj.ident] == nil
			case is OsmWay:
				return ways[obj.ident] == nil
			case is OsmRelation:
				return relations[obj.ident] == nil
			default:
				return true
			}
		})

		// fixup relation references
		for relation in relations.values {
			_ = relation.resolveToMapData(self)
		}

		t = CACurrentMediaTime() - t
		print("Discard sweep time = \(t)")

		// make a copy of items to save because the dictionary might get updated by the time the Database block runs
		let saveNodes = nodes.values
		let saveWays = ways.values
		let saveRelations = relations.values

		Database.dispatchQueue.async(execute: { [self] in
			var t2 = CACurrentMediaTime()
			let tmpPath: String
			do {
				// its faster to create a brand new database than to update the existing one, because SQLite deletes are slow
				try? Database.delete(withName: "tmp")
				let db2 = try Database(name: "tmp")
				tmpPath = db2.path
				try db2.createTables()
				try db2.save(saveNodes: saveNodes, saveWays: saveWays, saveRelations: saveRelations,
				             deleteNodes: [], deleteWays: [], deleteRelations: [],
				             isUpdate: false)
				// need to let db2 go out of scope here so file is no longer in use
			} catch {
				// we couldn't create the new database, so abort the discard
				print("failed to recreate SQL database")
				return
			}
			let realPath = Database.databasePath(withName: "")
			let error = rename(tmpPath, realPath)
			if error != 0 {
				print("failed to rename SQL database")
			}
			t2 = CACurrentMediaTime() - t2

			if isUnderDebugger() {
				// calling nodeCount() etc here isn't thread safe
				print(String(
					format: "%@Discard save time = %f, saved %ld objects",
					t2 > 1.0 ? "*** " : "",
					t2,
					Int(nodeCount()) + Int(wayCount()) + Int(relationCount())))
			}

			DispatchQueue.main.async(execute: {
				self.previousDiscardDate = Date()
			})
		})

		return true
	}

	// after uploading a changeset we have to update the SQL database to reflect the changes the server replied with
	func updateSql(_ sqlUpdate: [OsmBaseObject: Bool]) {
		var insertNode: [OsmNode] = []
		var insertWay: [OsmWay] = []
		var insertRelation: [OsmRelation] = []
		var deleteNode: [OsmNode] = []
		var deleteWay: [OsmWay] = []
		var deleteRelation: [OsmRelation] = []

		for (object, insert) in sqlUpdate {
			if let obj = object.isNode() {
				if insert {
					insertNode.append(obj)
				} else {
					deleteNode.append(obj)
				}
			} else if let obj = object.isWay() {
				if insert {
					insertWay.append(obj)
				} else {
					deleteWay.append(obj)
				}
			} else if let obj = object.isRelation() {
				if insert {
					insertRelation.append(obj)
				} else {
					deleteRelation.append(obj)
				}
			} else {
				assertionFailure()
			}
		}

		sqlSave(
			saveNodes: insertNode,
			saveWays: insertWay,
			saveRelations: insertRelation,
			deleteNodes: deleteNode,
			deleteWays: deleteWay,
			deleteRelations: deleteRelation,
			isUpdate: true)
	}

	func archiveModifiedData() {
		var t = CACurrentMediaTime()
		// save dirty data and relations
		DbgAssert(OsmMapData.g_EditorMapLayerForArchive != nil)

		// save our original data
		let origNodes = nodes
		let origWays = ways
		let origRelations = relations

		// update self with minimized versions appropriate for saving
		let modified = modifiedObjects()
		// FIXME: if an object gets duplicated in the undo manager somehow then
		// this code will crash because the ident key is duplicated. This requires
		// tracking down the cause of the duplication, not fixing it here.
		nodes = Dictionary(uniqueKeysWithValues: modified.nodes.map({ ($0.ident, $0) }))
		ways = Dictionary(uniqueKeysWithValues: modified.ways.map({ ($0.ident, $0) }))
		relations = Dictionary(uniqueKeysWithValues: modified.relations.map({ ($0.ident, $0) }))
		// the spatial used to be handled here as well, but now it simply never saves it's contents

		// Do the save.
		let archiver = OsmMapDataArchiver()
		_ = archiver.saveArchive(mapData: self)

		t = CACurrentMediaTime() - t
		DLog("""
		Archive save \(nodeCount()),\(wayCount()),\(relationCount()),\
		 \(undoManager.countUndoGroups),\(region.countOfObjects()) = \(t)
		""")

		// restore originals
		nodes = origNodes
		ways = origWays
		relations = origRelations

		periodicSaveTimer?.invalidate()
		periodicSaveTimer = nil
	}

	static func withArchivedData() throws -> OsmMapData {
		let archiver = OsmMapDataArchiver()
		let mapData = try archiver.loadArchive()
		if mapData.spatial.countOfObjects() > 0 {
			print("spatial accidentally saved, please fix")
			mapData.spatial.rootQuad.reset()
		}

		// rebuild spatial database
		mapData.enumerateObjects(usingBlock: { obj in
			if !obj.deleted {
				mapData.spatial.addMember(obj, undo: nil)
			}
		})

		// do this after spatial is built
		mapData.consistencyCheck()

		// merge info from SQL database
		do {
			let db = try Database(name: "")
			var newData = OsmDownloadData()
			newData.nodes = try db.queryNodes()
			newData.ways = try db.queryWays()
			newData.relations = try db.queryRelations()
			try mapData.merge(newData, savingToDatabase: false)

			mapData.consistencyCheck()
		} catch {
			// database couldn't be read
			print("Error: \(error.localizedDescription)")
			print("Unable to read database: recreating from scratch")
			try? Database.delete(withName: "")
			// need to download all regions
			mapData.region.rootQuad.reset()
		}

		return mapData
	}
}

// MARK: Consistency checking

extension OsmMapData {
	func consistencyCheckRelationMembers() {
		// make sure that parentRelations is correct for every relation member
		var allMembers = Set<OsmBaseObject>()
		for relation in relations.values {
			for member in relation.members {
				if let object = member.obj {
					switch member.type {
					case .NODE:
						assert(nodes[object.ident] === object)
					case .WAY:
						assert(ways[object.ident] === object)
					case .RELATION:
						assert(relations[object.ident] === object)
					}
					assert(object.parentRelations.contains(relation))
					allMembers.insert(object)
				}
			}
		}
		// ensure there is no object with parentRelations that isn't actually a member
		for obj in nodes.values {
			obj.parentRelations.forEach({ assert($0.members.map({ $0.obj }).contains(obj)) })
		}
		for obj in ways.values {
			obj.parentRelations.forEach({ assert($0.members.map({ $0.obj }).contains(obj)) })
		}
		for obj in relations.values {
			obj.parentRelations.forEach({ assert($0.members.map({ $0.obj }).contains(obj)) })
		}
	}

	func consistencyCheckDebugOnly() {
		// This is extremely expensive: DEBUG only!
		consistencyCheckRelationMembers()
		spatial.consistencyCheck(nodes: nodes,
		                         ways: ways,
		                         relations: relations)

		// make sure all objects are marked as constructed
		for node in nodes.values {
			assert(node.constructed())
		}
		for way in ways.values {
			assert(way.constructed())
		}
		for relation in relations.values {
			assert(relation.constructed())
		}

		// make sure that if the undo manager is holding an object that it's consistent with mapData
		let undoObjects = undoManager.objectRefs()
		for obj in undoObjects {
			if let node = obj as? OsmNode {
				assert(nodes[node.ident] === node)
			} else if let way = obj as? OsmWay {
				assert(ways[way.ident] === way)
			} else if let relation = obj as? OsmRelation {
				assert(relations[relation.ident] === relation)
			}
		}

#if false
		// check for overlappying nodes
		var locSet = [OSMPoint: OsmNode]()
		for (ident, node) in nodes {
			assert(ident == node.ident)
			let loc = node.location()
			if let dup = locSet[loc] {
				print("Duplicate nodes: \(dup.ident), \(node.ident)")
				// print("Duplicate node(s): \n    \(dup)\n    \(node)")
			} else {
				locSet[loc] = node
			}
		}
#endif

		// check for duplicate consecutive nodes in a way
		for way in ways.values {
			let nodes = way.nodes
			for index in nodes.indices.dropLast() {
				if nodes[index].ident == nodes[index + 1].ident {
					print(
						"Duplicate nodes: node \(nodes[index].ident) in way \(nodes[index].ident) (\(index),\(index + 1) of \(nodes.count))")
				}
			}
		}

		// check if node wayCount is accurate
		var wayCountDict = Dictionary(uniqueKeysWithValues: nodes.values.map({ ($0.ident, $0.wayCount) }))
		for way in ways.values {
			for node in way.nodes {
				wayCountDict[node.ident]! -= 1
			}
		}
		if let index = wayCountDict.first(where: { $0.value != 0 }) {
			let node = nodes[index.key]!
			print("node \(node.ident) has bad wayCount: \(index.value)")
			print("starting wayCount = \(node.wayCount)")
			for way in ways.values {
				if way.nodes.contains(node) {
					print("way \(way.ident) contains node \(node.ident)")
				}
			}
			assertionFailure()
		}
	}

	func consistencyCheck() {
#if DEBUG
		if isUnderDebugger() {
			consistencyCheckDebugOnly()
		}
#endif
	}
}
