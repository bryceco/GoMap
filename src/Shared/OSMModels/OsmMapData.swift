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

// "https://api.openstreetmap.org/"
let OSM_SERVER_KEY = "OSM Server"
var OSM_API_URL: String = ""

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

enum OsmMapDataError: Error {
	case unableToOpenDatabase
	case osmWayResolveToMapDataFoundNilNodeRefs
	case osmWayResolveToMapDataCouldntFindNodeRef
}

final class OsmMapData: NSObject, NSCoding {
	fileprivate static var g_EditorMapLayerForArchive: EditorMapLayer?

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

	// only used when saving/restoring undo manager
	class func setEditorMapLayerForArchive(_ editorLayer: EditorMapLayer) {
		g_EditorMapLayerForArchive = editorLayer
	}

	// only used when saving/restoring undo manager
	class func editorMapLayerForArchive() -> EditorMapLayer {
		return g_EditorMapLayerForArchive!
	}

	func initCommon() {
		UserDefaults.standard.register(defaults: [OSM_SERVER_KEY: "https://api.openstreetmap.org/"])
		let server = UserDefaults.standard.object(forKey: OSM_SERVER_KEY) as! String
		setServer(server)
		setupPeriodicSaveTimer()
	}

	init(region: QuadMap, spatial: QuadMap, undoManager: MyUndoManager) {
		nodes = [:]
		ways = [:]
		relations = [:]
		undoContextForComment = nil

		self.region = region
		self.spatial = spatial
		self.undoManager = undoManager

		super.init()

		initCommon()
	}

	override convenience init() {
		self.init(region: QuadMap(encodingContentsOnSave: true),
		          spatial: QuadMap(encodingContentsOnSave: false),
		          undoManager: MyUndoManager())
	}

	deinit {
		NotificationCenter.default.removeObserver(
			self,
			name: NSNotification.Name(MyUndoManager.UndoManagerDidChangeNotification),
			object: undoManager)
		periodicSaveTimer?.invalidate()
	}

	func setServer(_ hostname: String) {
		var hostname = hostname
		hostname = hostname.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

		if hostname.count == 0 {
			hostname = "api.openstreetmap.org"
		}

		if hostname.hasPrefix("http://") || hostname.hasPrefix("https://") {
			// great
		} else {
			hostname = "https://" + hostname
		}

		while hostname.hasSuffix("//") {
			// fix for previous releases that may have accidently set an extra slash
			hostname = (hostname as NSString?)?.substring(to: hostname.count - 1) ?? ""
		}
		if hostname.hasSuffix("/") {
			// great
		} else {
			hostname = hostname + "/"
		}

		if OSM_API_URL == hostname {
			// no change
			return
		}

		if OSM_API_URL.count != 0 {
			// get rid of old data before connecting to new server
			purgeSoft()
		}

		UserDefaults.standard.set(hostname, forKey: OSM_SERVER_KEY)
		OSM_API_URL = hostname
	}

	func getServer() -> String {
		return OSM_API_URL
	}

	func setupPeriodicSaveTimer() {
		weak var weakSelf = self
		NotificationCenter.default.addObserver(
			forName: NSNotification.Name(MyUndoManager.UndoManagerDidChangeNotification),
			object: undoManager,
			queue: nil,
			using: { _ in
				let myself = weakSelf
				if myself == nil {
					return
				}
				if myself?.periodicSaveTimer == nil {
					if let myself = myself {
						myself.periodicSaveTimer = Timer.scheduledTimer(
							timeInterval: 10.0,
							target: myself,
							selector: #selector(self.periodicSave(_:)),
							userInfo: nil,
							repeats: false)
					}
				}
			})
	}

	@objc func periodicSave(_ timer: Timer) {
		let appDelegate = AppDelegate.shared
		appDelegate.mapView.save() // this will also invalidate the timer
	}

	func setConstructed() {
		(nodes as NSDictionary?)?.enumerateKeysAndObjects({ _, node, _ in
			(node as? OsmNode)?.setConstructed()
		})
		(ways as NSDictionary?)?.enumerateKeysAndObjects({ _, way, _ in
			(way as? OsmWay)?.setConstructed()
		})
		(relations as NSDictionary?)?.enumerateKeysAndObjects({ _, relation, _ in
			(relation as? OsmRelation)?.setConstructed()
		})
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

	// FIXME: use OsmExtendedIdentifier
	func object(withExtendedIdentifier extendedIdentifier: Int64) -> OsmBaseObject? {
		let ext = OsmExtendedIdentifier(extendedIdentifier)
		let ident: OsmIdentifier = ext.ident
		let type: OSM_TYPE = ext.type
		switch type {
		case OSM_TYPE._NODE:
			return nodes[ident]
		case OSM_TYPE._WAY:
			return ways[ident]
		case OSM_TYPE._RELATION:
			return relations[ident]
		default:
			return nil
		}
	}

	func waysContaining(_ node: OsmNode) -> [OsmWay] {
		var a: [OsmWay] = []
		for (_, way) in ways {
			if way.nodes.contains(node) {
				a.append(way)
			}
		}
		return a
	}

	func objectsContaining(_ object: OsmBaseObject) -> [OsmBaseObject] {
		var a: [OsmBaseObject] = []

		if let object = object as? OsmNode {
			for (_, way) in ways {
				if way.nodes.contains(object) {
					a.append(way)
				}
			}
		}

		for (_, relation) in relations {
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
#if false && DEBUG
		print("box = \(NSCoder.string(for: CGRectFromOSMRect(bbox)))")
#endif
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

		for (_, object) in nodes {
			if let value = object.tags[key] {
				set.insert(value)
			}
		}
		for (_, object) in nodes {
			if let value = object.tags[key] {
				set.insert(value)
			}
		}
		for (_, object) in relations {
			if let value = object.tags[key] {
				set.insert(value)
			}
		}

		// special case for street names
		if key == "addr:street" {
			for (_, object) in ways {
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
		let node = OsmNode(asUserCreated: AppDelegate.shared.userName)
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
		let way = OsmWay(asUserCreated: AppDelegate.shared.userName)
		way.setDeleted(true, undo: nil)
		setConstructed(way)
		ways[way.ident] = way

		registerUndoCommentString(NSLocalizedString("create way", comment: ""))
		way.setDeleted(false, undo: undoManager)
		return way
	}

	func createRelation() -> OsmRelation {
		let relation = OsmRelation(asUserCreated: AppDelegate.shared.userName)
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
						deleteMember(inRelationUnsafe: relation, index: memberIndex)
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
		_ = spatial.removeMember(way, undo: undoManager)

		remove(fromParentRelationsUnsafe: way)

		while way.nodes.count != 0 {
			let node = way.nodes.last
			deleteNode(inWayUnsafe: way, index: way.nodes.count - 1, preserveNode: node?.hasInterestingTags() ?? false)
		}
		way.setDeleted(true, undo: undoManager)
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

	func deleteNode(inWayUnsafe way: OsmWay, index: Int, preserveNode: Bool) {
		registerUndoCommentString(NSLocalizedString("delete node from way", comment: ""))
		let node = way.nodes[index]
		DbgAssert(node.wayCount > 0)

		let bbox = way.boundingBox
		way.removeNodeAtIndex(index, undo: undoManager)
		// if removing the node leads to 2 identical nodes being consecutive delete one of them as well
		while index > 0, index < way.nodes.count, way.nodes[index - 1] == way.nodes[index] {
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

		for i in 0..<parents.count {
			let (parent, box) = parents[i]
#if false
			// mark parent as modified when child node changes
			incrementModifyCount(parent)
#else
			clearCachedProperties(parent, undo: undoManager)
#endif
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

	func deleteMember(inRelationUnsafe relation: OsmRelation, index: Int) {
		if relation.members.count == 1 {
			// deleting last member of relation, so delete relation
			deleteRelationUnsafe(relation)
		} else {
			registerUndoCommentString(NSLocalizedString("delete object from relation", comment: ""))
			let bbox = relation.boundingBox
			relation.removeMemberAtIndex(index, undo: undoManager)
			spatial.updateMember(relation, fromBox: bbox, undo: undoManager)
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

	// undo manager interface

	// MARK: Undo manager

	@discardableResult
	func undo() -> [String: Any]? {
		consistencyCheck()
		let comment = undoManager.undo()
		if let undoCommentCallback = undoCommentCallback {
			undoCommentCallback(true, comment ?? [:])
		}
		consistencyCheck()
		return comment
	}

	@discardableResult
	func redo() -> [String: Any]? {
		consistencyCheck()
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
		// sort by row
		var quadList = quadList
		quadList.sort(by: { q1, q2 in
			var diff = q1.rect.origin.y - q2.rect.origin.y
			if diff == 0 {
				diff = q1.rect.origin.x - q2.rect.origin.x
			}
			return diff < 0
		})

		var queries: [ServerQuery] = []
		var prevQuery: ServerQuery?
		for q in quadList {
			if let prevQuery = prevQuery,
			   q.rect.origin.y == prevQuery.rect.origin.y,
			   q.rect.origin.x == prevQuery.rect.origin.x + prevQuery.rect.size.width,
			   q.rect.size.height == prevQuery.rect.size.height
			{
				// combine with previous quad(s)
				prevQuery.quadList.append(q)
				prevQuery.rect.size.width += q.rect.size.width
			} else {
				// create new query for quad
				prevQuery = ServerQuery()
				prevQuery!.quadList = [q]
				prevQuery!.rect = q.rect
				queries.append(prevQuery!)
			}
		}

		// any items that didn't get grouped get put back on the list
		quadList = queries.compactMap({ query in
			query.quadList.count == 1 ? query.quadList[0] : nil
		})

		// sort by column
		quadList.sort(by: { q1, q2 in
			var diff = q1.rect.origin.x - q2.rect.origin.x
			if diff == 0 {
				diff = q1.rect.origin.y - q2.rect.origin.y
			}
			return diff < 0
		})
		prevQuery = nil
		for q in quadList {
			if let prevQuery = prevQuery,
			   q.rect.origin.x == prevQuery.rect.origin.x,
			   q.rect.origin.y == prevQuery.rect.origin.y + prevQuery.rect.size.height,
			   q.rect.size.width == prevQuery.rect.size.width
			{
				prevQuery.quadList.append(q)
				prevQuery.rect.size.height += q.rect.size.height
			} else {
				prevQuery = ServerQuery()
				prevQuery!.quadList = [q]
				prevQuery!.rect = q.rect
				queries.append(prevQuery!)
			}
		}

#if false
		DLog("\nquery list:")
		for q in queries {
			DLog("  %@", NSCoder.string(for: CGRectFromOSMRect(q.rect)))
		}
#endif

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
	///			before the current query completes. The quads must be marked non-busy via a call to makeWhole()
	///			once we're done with them. makeWhole() takes a success flag indicating that the quad now contains data.
	///	- We then combine (coalesceQuadQueries) adjacent quads into a single rectangle
	///	- We submit the rect to the server
	///	- Once we've successfully fetched the data for the rect we tell the QuadMap that it can mark the given QuadBoxes as downloaded
	func downloadMissingData(inRect rect: OSMRect,
	                         withProgress progress: NSObjectProtocol & MapViewProgress,
	                         didChange: @escaping (_ error: Error?) -> Void)
	{
		// get list of new quads to fetch
		let newQuads = region.missingQuads(forRect: rect)
		if newQuads.count == 0 {
			return
		}

		// Convert the list of quads into server queries
		let queryList = OsmMapData.coalesceQuadQueries(newQuads)

		// submit each query to the server and process the results
		for query in queryList {
			progress.progressIncrement()

			let rc = query.rect
			let url = OSM_API_URL +
				"api/0.6/map?bbox=\(rc.origin.x),\(rc.origin.y),\(rc.origin.x + rc.size.width),\(rc.origin.y + rc.size.height)"

			OsmDownloader.osmData(forUrl: url, completion: { result in
				let didGetData: Bool
				switch result {
				case let .success(data):
					// merge data
					try? self.merge(data, savingToDatabase: true)
					didGetData = true
					didChange(nil) // data was updated
				case let .failure(error):
					didGetData = false
					didChange(error) // error fetching data
				}
				for quadBox in query.quadList {
					self.region.makeWhole(quadBox, success: didGetData)
				}
				progress.progressDecrement()
			})
		}
	}

	func cancelCurrentDownloads() {
		if DownloadThreadPool.osmPool.downloadsInProgress() > 0 {
			DownloadThreadPool.osmPool.cancelAllDownloads()
		}
	}

	// MARK: Download

	func merge(_ newData: OsmDownloadData, savingToDatabase save: Bool) throws {
		var newNodes: [OsmNode] = []
		var newWays: [OsmWay] = []
		var newRelations: [OsmRelation] = []

		for node in newData.nodes {
			let current = nodes[node.ident]
			if current == nil {
				nodes[node.ident] = node
				spatial.addMember(node, undo: nil)
				newNodes.append(node)
			} else if current!.version < node.version {
				// already exists, so do an in-place update
				let bbox = current!.boundingBox
				current!.serverUpdate(inPlace: node)
				spatial.updateMember(current!, fromBox: bbox, undo: nil)
				newNodes.append(current!)
			}
		}

		for way in newData.ways {
			let current = ways[way.ident]
			if current == nil {
				ways[way.ident] = way
				try way.resolveToMapData(self)
				spatial.addMember(way, undo: nil)
				newWays.append(way)
			} else if current!.version < way.version {
				let bbox = current!.boundingBox
				current!.serverUpdate(inPlace: way)
				try current!.resolveToMapData(self)
				spatial.updateMember(current!, fromBox: bbox, undo: nil)
				newWays.append(current!)
			}
		}

		for relation in newData.relations {
			let current = relations[relation.ident]
			if current == nil {
				relations[relation.ident] = relation
				spatial.addMember(relation, undo: nil)
				newRelations.append(relation)
			} else if current!.version < relation.version {
				let bbox = current!.boundingBox
				current!.serverUpdate(inPlace: relation)
				spatial.updateMember(current!, fromBox: bbox, undo: nil)
				newRelations.append(current!)
			}
		}

		// all relations, including old ones, need to be resolved against new objects
		var didChange: Bool = true
		while didChange {
			didChange = false
			for (_, relation) in relations {
				let bbox = relation.boundingBox
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

		// store new nodes in database
		if save {
			sqlSaveNodes(
				newNodes,
				saveWays: newWays,
				saveRelations: newRelations,
				deleteNodes: [],
				deleteWays: [],
				deleteRelations: [],
				isUpdate: false)

			// purge old data
			DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 1.0, execute: {
				AppDelegate.shared.mapView.discardStaleData()
			})
		}
	}

	class func updateChangesetXml(_ xmlDoc: DDXMLDocument, withChangesetID changesetID: Int64) {
		let osmChange = xmlDoc.rootElement()
		for changeType in osmChange?.children ?? [] {
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

	func uploadChangesetXML(
		_ xmlChanges: DDXMLDocument,
		changesetID: Int64,
		retries: Int,
		completion: @escaping (_ errorMessage: String?) -> Void)
	{
		let url2 = OSM_API_URL + "api/0.6/changeset/\(changesetID)/upload"
		putRequest(url2, method: "POST", xml: xmlChanges) { [self] postData, postErrorMessage in
			guard let postData = postData else {
				completion(postErrorMessage)
				return
			}
			let response = String(decoding: postData, as: UTF8.self)

			if retries > 0 && response.hasPrefix("Version mismatch") {
				// update the bad element and retry
				DLog("Upload error: \(response)")
				var localVersion = 0
				var serverVersion = 0
				var objType: NSString? = ""
				var objId: OsmIdentifier = 0
				// "Version mismatch: Provided %d, server had: %d of %[a-zA-Z] %lld"
				let scanner = Scanner(string: response)
				if scanner.scanString("Version mismatch: Provided", into: nil),
				   scanner.scanInt(&localVersion),
				   scanner.scanString(", server had:", into: nil),
				   scanner.scanInt(&serverVersion),
				   scanner.scanString("of", into: nil),
				   scanner.scanCharacters(from: CharacterSet.alphanumerics, into: &objType),
				   scanner.scanInt64(&objId),
				   let objType = objType
				{
					let objType = (objType as String).lowercased()
					var url3 = OSM_API_URL + "api/0.6/\(objType)/\(objId)"
					if objType == "way" || objType == "relation" {
						url3 = url3 + "/full"
					}
					OsmDownloader.osmData(forUrl: url3, completion: { result in
						switch result {
						case let .success(data):
							// update the bad element
							try? merge(data, savingToDatabase: true)
							// try again:
							uploadChangeset(changesetID, retries: retries - 1, completion: completion)
						case let .failure(error):
							completion("\(error)")
						}
					})
					return
				}
			}

			if !response.hasPrefix("<?xml") {
				completion(postErrorMessage ?? response)
				return
			}

			let diffDoc: DDXMLDocument
			do {
				diffDoc = try DDXMLDocument(data: postData, options: 0)
			} catch let error as NSError {
				completion(error.localizedDescription)
				return
			} catch {
				completion("XML conversion error")
				return
			}

			if diffDoc.rootElement()?.name != "diffResult" {
				completion("Upload failed: invalid server respsonse")
				return
			}

			var sqlUpdate: [OsmBaseObject: Bool] = [:]
			for element in diffDoc.rootElement()?.children ?? [] {
				guard let element = element as? DDXMLElement else {
					continue
				}
				let name = element.name
				let oldId = Int64(element.attribute(forName: "old_id")?.stringValue ?? "0")!
				let newId = Int64(element.attribute(forName: "new_id")?.stringValue ?? "0")!
				let newVersion = Int(element.attribute(forName: "new_version")?.stringValue ?? "0")!

				if name == "node" {
					updateObjectDictionary(
						&nodes,
						oldId: oldId,
						newId: newId,
						version: newVersion,
						changeset: changesetID,
						sqlUpdate: &sqlUpdate)
				} else if name == "way" {
					updateObjectDictionary(
						&ways,
						oldId: oldId,
						newId: newId,
						version: newVersion,
						changeset: changesetID,
						sqlUpdate: &sqlUpdate)
				} else if name == "relation" {
					updateObjectDictionary(
						&relations,
						oldId: oldId,
						newId: newId,
						version: newVersion,
						changeset: changesetID,
						sqlUpdate: &sqlUpdate)
				} else {
					DLog("Bad upload diff document")
				}
			}

			updateSql(sqlUpdate)

			let url3 = OSM_API_URL + "api/0.6/changeset/\(changesetID)/close"
			putRequest(url3, method: "PUT", xml: nil) { _, errorMessage in
				var errorMsg = errorMessage
				if errorMsg != nil {
					errorMsg = (errorMsg!) + " (ignored, changes already committed)"
				}
				completion(errorMsg)
				// DLog(@"changeset closed");
			}

			// reset undo stack after upload so user can't accidently undo a commit (wouldn't work anyhow because we don't undo version numbers on objects)
			undoManager.removeAllActions()
		}
	}

	// upload xml generated by mapData
	func uploadChangeset(_ changesetID: Int64, retries: Int, completion: @escaping (_ errorMessage: String?) -> Void) {
		guard let xmlChanges = OsmXmlGenerator.createXmlFor(nodes: nodes.values,
		                                                    ways: ways.values,
		                                                    relations: relations.values)
		else {
			completion("Failure generating XML")
			return
		}
		OsmMapData.updateChangesetXml(xmlChanges, withChangesetID: changesetID)
		uploadChangesetXML(xmlChanges, changesetID: changesetID, retries: retries, completion: completion)
	}

	// MARK: Upload

	func updateObjectDictionary<T: OsmBaseObject>(
		_ dictionary: inout [OsmIdentifier: T],
		oldId: OsmIdentifier,
		newId: OsmIdentifier,
		version newVersion: Int,
		changeset: Int64,
		sqlUpdate: inout [OsmBaseObject: Bool])
	{
		let object = dictionary[oldId]!
		assert(object.ident == oldId)
		if newVersion == 0, newId == 0 {
			// Delete object for real
			// When a way is deleted we delete the nodes also, but they aren't marked as deleted in the graph.
			// If nodes are still in use by another way the newId and newVersion will be set and we won't take this path.
			assert(Int(newId) == 0 && newVersion == 0)
			if object.isNode() != nil {
				nodes.removeValue(forKey: object.ident)
			} else if object.isWay() != nil {
				ways.removeValue(forKey: object.ident)
			} else if object.isRelation() != nil {
				relations.removeValue(forKey: object.ident)
			} else {
				assert(false)
			}
			sqlUpdate[object] = false // mark for deletion
			return
		}

		assert(newVersion > 0)
		object.serverUpdateVersion(newVersion)
		object.serverUpdateChangeset(changeset)
		sqlUpdate[object] = true // mark for insertion

		if oldId != newId {
			// replace placeholder object with new server provided identity
			assert(Int(oldId) < 0 && Int(newId) > 0)
			dictionary.removeValue(forKey: object.ident)
			object.serverUpdateIdent(newId)
			dictionary[object.ident] = object
		} else {
			assert(Int(oldId) > 0)
		}
		object.resetModifyCount(undoManager)
	}

	class func encodeBase64(_ plainText: String) -> String {
		let data = plainText.data(using: .utf8)
		let output = data!.base64EncodedString(options: [])
		return output
	}

	func putRequest(
		_ url: String,
		method: String,
		xml: DDXMLDocument?,
		completion: @escaping (_ data: Data?, _ error: String?) -> Void)
	{
		guard let url1 = URL(string: url) else {
			completion(nil, "Unable to build URL")
			return
		}
		let request = NSMutableURLRequest(url: url1)
		request.httpMethod = method
		if let xml = xml {
			var data = xml.xmlData(withOptions: 0)
			data = (try? data.gzipped()) ?? data
			request.httpBody = data
			request.setValue("text/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
			request.setValue("gzip", forHTTPHeaderField: "Content-Encoding")
		}
		request.cachePolicy = .reloadIgnoringLocalCacheData

		var auth = "\(AppDelegate.shared.userName):\(AppDelegate.shared.userPassword)"
		auth = OsmMapData.encodeBase64(auth)
		auth = "Basic \(auth)"
		request.setValue(auth, forHTTPHeaderField: "Authorization")

		let task = URLSession.shared.dataTask(with: request as URLRequest, completionHandler: { data, response, error in
			DispatchQueue.main.async(execute: {
				let httpResponse = ((response is HTTPURLResponse) ? response : nil) as? HTTPURLResponse
				if data != nil, error == nil, httpResponse != nil, (httpResponse?.statusCode ?? 0) >= 200,
				   (httpResponse?.statusCode ?? 0) <= 299
				{
					completion(data, nil)
				} else {
					var errorMessage: String?
					if (data?.count ?? 0) > 0 {
						data?.withUnsafeBytes { bytes in
							errorMessage = String(bytes: bytes, encoding: .utf8)
						}
					} else {
						errorMessage = error != nil ? error?.localizedDescription : httpResponse != nil ? String(
							format: "HTTP Error %ld",
							Int(httpResponse?.statusCode ?? 0)) : "Unknown error"
					}
					errorMessage = (errorMessage ?? "") + "\n\n\(method) \(url)"
					completion(nil, errorMessage ?? "")
				}
			})
		})
		task.resume()
	}

	// create a new changeset to upload to
	func createChangeset(
		withComment comment: String,
		source: String,
		imagery: String,
		completion: @escaping (_ changesetID: Int64?, _ errorMessage: String?) -> Void)
	{
		let appDelegate = AppDelegate.shared
		let creator = "\(appDelegate.appName()) \(appDelegate.appVersion())"
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
		if let xmlCreate = OsmXmlGenerator.createXml(withType: "changeset", tags: tags) {
			let url = OSM_API_URL + "api/0.6/changeset/create"
			putRequest(url, method: "PUT", xml: xmlCreate) { putData, putErrorMessage in
				guard let putData = putData,
				      putErrorMessage == nil
				else {
					completion(nil, putErrorMessage ?? "")
					return
				}

				let responseString = String(decoding: putData, as: UTF8.self)
				if let changeset = Int64(responseString) {
					// The response string only contains of the digits 0 through 9.
					// Assume that the request was successful and that the server responded with a changeset ID.
					completion(changeset, nil)
				} else {
					// The response did not only contain digits; treat this as an error.
					completion(nil, responseString)
				}
			}
		}
	}

	// upload xml generated by mapData
	func uploadChangeset(
		withComment comment: String,
		source: String,
		imagery: String,
		completion: @escaping (_ errorMessage: String?) -> Void)
	{
		createChangeset(withComment: comment, source: source, imagery: imagery) { [self] changesetID, errorMessage in
			if let changesetID = changesetID {
				uploadChangeset(changesetID, retries: 20, completion: completion)
			} else {
				completion(errorMessage)
			}
		}
	}

	// upload xml edited by user
	func uploadChangesetXml(
		_ xmlChanges: DDXMLDocument,
		comment: String,
		source: String,
		imagery: String,
		completion: @escaping (_ error: String?) -> Void)
	{
		consistencyCheck()

		createChangeset(withComment: comment, source: source, imagery: imagery) { [self] changesetID, errorMessage in
			if let changesetID = changesetID {
				OsmMapData.updateChangesetXml(xmlChanges, withChangesetID: changesetID)
				uploadChangesetXML(xmlChanges, changesetID: changesetID, retries: 0, completion: completion)
			} else {
				completion(errorMessage)
			}
		}
	}

	func verifyUserCredentials(withCompletion completion: @escaping (_ errorMessage: String?) -> Void) {
		let appDelegate = AppDelegate.shared

		let url = OSM_API_URL + "api/0.6/user/details"
		putRequest(url, method: "GET", xml: nil) { data, errorMessage in
			var ok = false
			var errorMsg = errorMessage
			if let data = data {
				let text = String(data: data, encoding: .utf8)
				if let doc = try? DDXMLDocument(xmlString: text ?? "", options: 0),
				   let users = doc.rootElement()?.elements(forName: "user"),
				   let user = users.last,
				   let displayName = user.attribute(forName: "display_name")?.stringValue,
				   displayName.compare(appDelegate.userName, options: .caseInsensitive) == .orderedSame
				{
					// update display name to have proper case:
					appDelegate.userName = displayName
					ok = true
				}
			}
			if ok {
				completion(nil)
			} else {
				if errorMsg == nil {
					errorMsg = NSLocalizedString("Not found", comment: "User credentials not found")
				}
				completion(errorMsg)
			}
		}
	}

	func changesetAsAttributedString() -> NSAttributedString? {
		guard let doc = OsmXmlGenerator.createXmlFor(nodes: nodes.values,
		                                             ways: ways.values,
		                                             relations: relations.values)
		else {
			return nil
		}
		return OsmXmlGenerator.attributedStringForXML(doc)
	}

	func changesetAsXml() -> String? {
		let xml = OsmXmlGenerator.createXmlFor(nodes: nodes.values,
		                                       ways: ways.values,
		                                       relations: relations.values)
		if xml == nil {
			return nil
		}
		return xml!.xmlString(withOptions: UInt(DDXMLNodePrettyPrint))
	}

	// MARK: Save/Restore

	func encode(with coder: NSCoder) {
		consistencyCheck()

		coder.encode(nodes, forKey: "nodes")
		coder.encode(ways, forKey: "ways")
		coder.encode(relations, forKey: "relations")
		coder.encode(region, forKey: "region")
		coder.encode(spatial, forKey: "spatial")
		coder.encode(undoManager, forKey: "undoManager")
	}

	required convenience init?(coder: NSCoder) {
		guard
			let nodes = coder.decodeObject(forKey: "nodes") as? [OsmIdentifier: OsmNode],
			let ways = coder.decodeObject(forKey: "ways") as? [OsmIdentifier: OsmWay],
			let relations = coder.decodeObject(forKey: "relations") as? [OsmIdentifier: OsmRelation],
			let region = coder.decodeObject(forKey: "region") as? QuadMap,
			let spatial = coder.decodeObject(forKey: "spatial") as? QuadMap,
			let undoManager = coder.decodeObject(forKey: "undoManager") as? MyUndoManager
		else { return nil }

		self.init(region: region,
		          spatial: spatial,
		          undoManager: undoManager)

		self.nodes = nodes
		self.ways = ways
		self.relations = relations

		initCommon()

		if region.isEmpty() {
			// This path taken if we came from a quick-save
			// didn't save spatial, so add everything back into it
			enumerateObjects(usingBlock: { object in
				self.spatial.addMember(object, undo: nil)
			})
		}
	}

	func modifiedObjects() -> OsmMapData {
		// get modified nodes and ways
		var objects = Array(undoManager.objectRefs())
		objects += nodes.values.filter({ $0.deleted ? ($0.ident > 0) : $0.isModified() })
		objects += ways.values.filter({ $0.deleted ? ($0.ident > 0) : $0.isModified() })
		objects += relations.values.filter({ $0.deleted ? ($0.ident > 0) : $0.isModified() })

		let modified = OsmMapData()
		for obj in objects {
			if let node = obj as? OsmNode {
				modified.nodes[node.ident] = node
			} else if let way = obj as? OsmWay {
				modified.ways[way.ident] = way
				for node in way.nodes {
					modified.nodes[node.ident] = node
				}
			} else if let relation = obj as? OsmRelation {
				modified.relations[relation.ident] = relation
			} else {
				// some other undo object
			}
		}
		return modified
	}

	func purgeExceptUndo() {
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

		for (_, object) in nodes {
			if object.isModified() {
				_ = dirty.insert(object)
			}
		}
		for (_, object) in ways {
			if object.isModified() {
				_ = dirty.insert(object)
			}
		}
		for (_, object) in relations {
			if object.isModified() {
				_ = dirty.insert(object)
			}
		}

		// get objects referenced by undo manager
		let undoRefs = undoManager.objectRefs()
		dirty = dirty.union(undoRefs)

		// add nodes in ways to dirty set, because we must preserve them to maintain consistency
		for way in Array(dirty) {
			if way is OsmWay {
				if let way = way as? OsmWay {
					dirty.formUnion(Set(way.nodes))
				}
			}
		}

		// deresolve relations
		for rel in dirty {
			guard let rel = rel as? OsmRelation else {
				continue
			}
			rel.deresolveRefs()
		}

		// purge everything
		purgeExceptUndo()

		// put dirty stuff back in
		for object in dirty {
			if let obj = object.isNode() {
				nodes[object.ident] = obj
			} else if let obj = object.isWay() {
				ways[object.ident] = obj
			} else if let obj = object.isRelation() {
				relations[object.ident] = obj
			} else {
				assert(false)
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

	static func pathToArchiveFile() -> String {
		// get tile cache folder
		let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).map(\.path)
		let bundleName = Bundle.main.infoDictionary?["CFBundleIdentifier"] as? String
		let path = URL(fileURLWithPath: URL(fileURLWithPath: paths[0]).appendingPathComponent(bundleName ?? "").path)
			.appendingPathComponent("OSM Downloaded Data.archive").path
		try? FileManager.default.createDirectory(
			atPath: URL(fileURLWithPath: path).deletingLastPathComponent().path,
			withIntermediateDirectories: true,
			attributes: nil)
		return path
	}

	func sqlSaveNodes(
		_ saveNodes: [OsmNode],
		saveWays: [OsmWay],
		saveRelations: [OsmRelation],
		deleteNodes: [OsmNode],
		deleteWays: [OsmWay],
		deleteRelations: [OsmRelation],
		isUpdate: Bool)
	{
		if (saveNodes.count + saveWays.count + saveRelations.count + deleteNodes.count + deleteWays
			.count + deleteRelations.count) == 0
		{
			return
		}
		Database.dispatchQueue.async(execute: { [self] in
			var t = CACurrentMediaTime()
			var ok: Bool = false
			do {
				let db = try Database(name: "")
				try db.createTables()
				try db.save(saveNodes: saveNodes, saveWays: saveWays, saveRelations: saveRelations,
				            deleteNodes: deleteNodes, deleteWays: deleteWays, deleteRelations: deleteRelations,
				            isUpdate: isUpdate)
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

	func discardStaleData() -> Bool {
		if modificationCount() > 0 {
			return false
		}
		let undoObjects = undoManager.objectRefs()

		// don't discard too frequently
		let now = Date()
		if now.timeIntervalSince(previousDiscardDate) < 60 {
			return false
		}

		// remove objects if they are too old, or we have too many:
		let limit = 100000
		var oldest = Date(timeIntervalSinceNow: -24 * 60 * 60)

		// get rid of old quads marked as downloaded
		var fraction = Double(nodes.count + ways.count + relations.count) / Double(limit)
		if fraction <= 1.0 {
			// the number of objects is acceptable
			fraction = 0.0
		} else {
			fraction = 1.0 - 1.0 / fraction
			if fraction < 0.3 {
				fraction = 0.3 // don't waste resources trimming tiny quantities
			}
		}

		var t = CACurrentMediaTime()

		var didExpand = false
		while true {
			guard let newOldest = region.discardOldestQuads(fraction, oldest: oldest)
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
					if obj.isNode() != nil {
						if region.pointIsCovered(obj.isNode()!.location()) {
							covered = true
						}
					} else if obj.isWay() != nil {
						if region.anyNodeIsCovered(obj.isWay()!.nodes) {
							covered = true
						}
					}
					if covered {
						break
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

			print(String(format: "remove %ld objects\n", removeNodes.count + removeWays.count + removeRelations.count))

			if Double(nodes.count + ways.count + relations.count) < (Double(limit) * 1.3) {
				// good enough
				if !didExpand, removeNodes.count + removeWays.count + removeRelations.count == 0 {
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
			if obj.isNode() != nil {
				return nodes[obj.ident] == nil
			} else if obj.isWay() != nil {
				return ways[obj.ident] == nil
			} else if obj.isRelation() != nil {
				return relations[obj.ident] == nil
			} else {
				return true
			}
		})

		// fixup relation references
		for (_, relation) in relations {
			relation.deresolveRefs()
			_ = relation.resolveToMapData(self)
		}

		consistencyCheck()

		t = CACurrentMediaTime() - t
		print("Discard sweep time = \(t)\n")

		// make a copy of items to save because the dictionary might get updated by the time the Database block runs
		let saveNodes = Array(nodes.values)
		let saveWays = Array(ways.values)
		let saveRelations = Array(relations.values)

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
				print("failed to recreate SQL database\n")
				return
			}
			let realPath = Database.databasePath(withName: "")
			let error = rename(tmpPath, realPath)
			if error != 0 {
				print("failed to rename SQL database\n")
			}
			t2 = CACurrentMediaTime() - t2
			print(String(
				format: "%@Discard save time = %f, saved %ld objects\n",
				t2 > 1.0 ? "*** " : "",
				t2,
				Int(nodeCount()) + Int(wayCount()) + Int(relationCount())))

			DispatchQueue.main.async(execute: {
				previousDiscardDate = Date()
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
				assert(false)
			}
		}

		sqlSaveNodes(
			insertNode,
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
		nodes = modified.nodes
		ways = modified.ways
		relations = modified.relations
		// the spatial used to be handled here as well, but now it simply never saves it's contents

		// Do the save.
		let archiver = OsmMapDataArchiver()
		_ = archiver.saveArchive(mapData: self)

		// restore originals
		nodes = origNodes
		ways = origWays
		relations = origRelations

		t = CACurrentMediaTime() - t
		DLog(
			"Archive save \(modified.nodeCount()),\(modified.wayCount()),\(modified.relationCount()),\(undoManager.countUndoGroups),\(region.countOfObjects()) = \(t)")

		periodicSaveTimer?.invalidate()
		periodicSaveTimer = nil
	}

	static func withArchivedData() throws -> OsmMapData {
		let archiver = OsmMapDataArchiver()
		let decode = try archiver.loadArchive()
		if decode.spatial.countOfObjects() > 0 {
			print("spatial accidentally saved, please fix")
			decode.spatial.rootQuad.reset()
		}

		// rebuild spatial database
		decode.enumerateObjects(usingBlock: { obj in
			if !obj.deleted {
				decode.spatial.addMember(obj, undo: nil)
			}
		})

		// merge info from SQL database
		do {
			let db = try Database(name: "")
			var newData = OsmDownloadData()
			newData.nodes = try db.querySqliteNodes()
			newData.ways = try db.querySqliteWays()
			newData.relations = try db.querySqliteRelations()

			try decode.merge(newData, savingToDatabase: false)
		} catch {
			// database couldn't be read
			print("Unable to read database: recreating from scratch\n")
			try? Database.delete(withName: "")
			// need to download all regions
			decode.region.rootQuad.reset()
		}

		decode.consistencyCheck()
		return decode
	}

	func consistencyCheckRelationMembers() {
		for (_, relation) in relations {
			for member in relation.members {
				if let object = member.obj {
					assert(object.parentRelations.contains(relation))
				}
			}
		}
	}

	func consistencyCheck() {
#if DEBUG
		// This is extremely expensive: DEBUG only!
		print("Checking spatial database consistency")

		consistencyCheckRelationMembers()
		spatial.consistencyCheck(nodes: Array(nodes.values),
		                         ways: Array(ways.values),
		                         relations: Array(relations.values))

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

		// check for duplicated/overlappying nodes
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

		// check for duplicate consecutive nodes in a way
		for way in ways.values {
			let nodes = way.nodes
			for index in nodes.indices.dropLast() {
				assert( nodes[index].ident != nodes[index+1].ident )
			}
		}
#endif
	}
}

enum MapDataError: Error {
	case archiveDoesNotExist
	case archiveCannotBeRead // I/O error
	case archiveCannotBeDecoded // NSKeyedUnarchiver problem
}

class OsmMapDataArchiver: NSObject, NSKeyedUnarchiverDelegate {
	func saveArchive(mapData: OsmMapData) -> Bool {
		let path = OsmMapData.pathToArchiveFile()
		let data = NSMutableData()
		let archiver = NSKeyedArchiver(forWritingWith: data)
		archiver.encode(mapData, forKey: "OsmMapData")
		archiver.finishEncoding()
		let ok = data.write(toFile: path, atomically: true)
		return ok
	}

	func loadArchive() throws -> OsmMapData {
		let path = OsmMapData.pathToArchiveFile()
		let url = URL(fileURLWithPath: path)
		if (try? url.checkResourceIsReachable()) != true {
			print("Archive file doesn't exist")
			throw MapDataError.archiveDoesNotExist
		}
		guard let data = try? Data(contentsOf: url) else {
			print("Archive file doesn't exist")
			throw MapDataError.archiveCannotBeRead
		}
		let unarchiver = NSKeyedUnarchiver(forReadingWith: data)
		unarchiver.delegate = self
		guard let decode = unarchiver.decodeObject(forKey: "OsmMapData") as? OsmMapData else {
			print("Couldn't decode archive file")
			throw MapDataError.archiveCannotBeDecoded
		}
		return decode
	}

	func unarchiver(_ unarchiver: NSKeyedUnarchiver, didDecode object: Any?) -> Any? {
		if object is EditorMapLayer {
			DbgAssert(OsmMapData.g_EditorMapLayerForArchive != nil)
			return OsmMapData.g_EditorMapLayerForArchive
		}
		return object
	}

	func unarchiver(
		_ unarchiver: NSKeyedUnarchiver,
		cannotDecodeObjectOfClassName name: String,
		originalClasses classNames: [String]) -> AnyClass?
	{
		fatalError("archive error: cannotDecodeObjectOfClassName \(name)")
	}

	func unarchiver(_ unarchiver: NSKeyedUnarchiver, willReplace object: Any, with newObject: Any) {
		DLog("replacing \(object) -> \(newObject)")
	}
}
