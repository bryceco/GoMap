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


final fileprivate class ServerQuery {
	var quadList: [QuadBox] = []
	var rect = OSMRect.zero
}

@objcMembers
final class OsmMapData: NSObject, XMLParserDelegate, NSCoding {
	fileprivate static var g_EditorMapLayerForArchive: EditorMapLayer? = nil

	private var parserCurrentElementText: String?
	private var parserStack: [AnyHashable] = []
	private var parseError: Error?

	private(set) var nodes: [OsmIdentifier : OsmNode] = [:]
	private(set) var ways: [OsmIdentifier : OsmWay] = [:]
	private(set) var relations: [OsmIdentifier : OsmRelation] = [:]
    var region = QuadMap() // currently downloaded region
    var spatial = QuadMap() // spatial index of osm data
    var undoManager = MyUndoManager()
    var periodicSaveTimer: Timer?

    // undo comments
    var undoContextForComment: ((_ comment: String) -> [String : Any])? = nil
    var undoCommentCallback: ((_ undo: Bool, _ context: [String : Any]) -> Void)? = nil
    
	private var previousDiscardDate: Date = Date.distantPast
    
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
    
	override init() {
        parserStack = []
		nodes = [:]
		ways = [:]
		relations = [:]
        region = QuadMap()
        spatial = QuadMap()
        undoManager = MyUndoManager()
		undoContextForComment = nil

		super.init()

        initCommon()
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name(MyUndoManager.UndoManagerDidChangeNotification), object: undoManager)
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
            hostname = (hostname as NSString?)?.substring(to: (hostname.count) - 1) ?? ""
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
        NotificationCenter.default.addObserver(forName: NSNotification.Name(MyUndoManager.UndoManagerDidChangeNotification), object: undoManager, queue: nil, using: { note in
            let myself = weakSelf
            if myself == nil {
                return
            }
            if myself?.periodicSaveTimer == nil {
                if let myself = myself {
                    myself.periodicSaveTimer = Timer.scheduledTimer(timeInterval: 10.0, target: myself, selector: #selector(self.periodicSave(_:)), userInfo: nil, repeats: false)
                }
            }
        })
    }
    
    @objc func periodicSave(_ timer: Timer) {
        let appDelegate = AppDelegate.shared
        appDelegate.mapView.save() // this will also invalidate the timer
    }
    
    func setConstructed() {
        (nodes as NSDictionary?)?.enumerateKeysAndObjects({ ident, node, stop in
            (node as? OsmNode)?.setConstructed()
        })
        (ways as NSDictionary?)?.enumerateKeysAndObjects({ ident, way, stop in
            (way as? OsmWay)?.setConstructed()
        })
        (relations as NSDictionary?)?.enumerateKeysAndObjects({ ident, relation, stop in
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
                return nodes[ident];
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

    func enumerateObjects(usingBlock block: @escaping (_ obj: OsmBaseObject) -> Void) {
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
    
    func enumerateObjects(inRegion bbox: OSMRect, block: @escaping (_ obj: OsmBaseObject) -> Void) {
#if false && DEBUG
        print("box = \(NSCoder.string(for: CGRectFromOSMRect(bbox)))")
#endif
        if bbox.origin.x < 180 && bbox.origin.x + bbox.size.width > 180 {
            let left = OSMRect(origin: OSMPoint(x: bbox.origin.x, y: bbox.origin.y), size: OSMSize(width: (180 - bbox.origin.x), height: bbox.size.height))
            let right = OSMRect(origin: OSMPoint(x: -180, y: bbox.origin.y), size: OSMSize(width: (bbox.origin.x + bbox.size.width - 180), height: bbox.size.height))
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
        var dict: [String : OsmUserStatistics] = [:]
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
		undo.registerUndo(withTarget: self, selector: #selector(clearCachedProperties(_:undo:)), objects: [object, undo])
		object.clearCachedProperties()
    }

	@objc
    func setTags(_ dict: [String : String], for object: OsmBaseObject) {
		let localDict = OsmTags.DictWithTagsTruncatedTo255( dict )
        registerUndoCommentString(NSLocalizedString("set tags", comment: ""))
        object.setTags(localDict, undo: undoManager)
    }
    
    func createNode(atLocation loc: CLLocationCoordinate2D) -> OsmNode {
		let node = OsmNode(asUserCreated: AppDelegate.shared.userName)
        node.setLongitude(loc.longitude, latitude: loc.latitude, undo: nil)
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
		_  = spatial.removeMember(node, undo: undoManager)
    }
    
    func deleteWayUnsafe(_ way: OsmWay) {
		registerUndoCommentString(NSLocalizedString("delete way", comment: ""))
		_ = spatial.removeMember(way, undo: undoManager)

		remove(fromParentRelationsUnsafe: way)

		while way.nodes.count != 0 {
			let node = way.nodes.last
			deleteNode(inWayUnsafe: way, index: (way.nodes.count - 1), preserveNode: node?.hasInterestingTags() ?? false)
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
		DbgAssert((node.wayCount) > 0)

		let bbox = way.boundingBox
		way.removeNodeAtIndex(index, undo: undoManager)
		// if removing the node leads to 2 identical nodes being consecutive delete one of them as well
		while (index > 0 && index < way.nodes.count) && (way.nodes[index - 1] == way.nodes[index]) {
			way.removeNodeAtIndex(index, undo: undoManager)
		}
		spatial.updateMember(way, fromBox: bbox, undo: undoManager)

		if node.wayCount == 0 && !preserveNode {
			deleteNodeUnsafe(node)
        }
    }
    
    // MARK: external editing commands
    
    
    func setLongitude(_ longitude: Double, latitude: Double, for node: OsmNode) {
        registerUndoCommentString(NSLocalizedString("move", comment: ""))
        
        // need to update all ways/relation which contain the node
		let parents = objectsContaining(node).map({ ($0, $0.boundingBox) })
		let bboxNode = node.boundingBox
        node.setLongitude(longitude, latitude: latitude, undo: undoManager)
        spatial.updateMember(node, fromBox: bboxNode, undo: undoManager)
        
        for i in 0..<parents.count {
            let (parent,box) = parents[i]
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
	func undo() -> [AnyHashable : Any]? {
        let comment = undoManager.undo()
        if let undoCommentCallback = undoCommentCallback {
            undoCommentCallback(true, comment ?? [:])
        }
        return comment
    }
    
	@discardableResult
	func redo() -> [AnyHashable : Any]? {
        let comment = undoManager.redo()
        if let undoCommentCallback = undoCommentCallback {
            undoCommentCallback(false, comment ?? [:])
        }
        return comment
    }
    
    func canUndo() -> Bool {
        return undoManager.canUndo
    }
    
    func canRedo() -> Bool {
        return undoManager.canRedo
    }
    
    func addChangeCallback(_ callback: @escaping () -> Void) {
        NotificationCenter.default.addObserver(forName: NSNotification.Name(MyUndoManager.UndoManagerDidChangeNotification), object: undoManager, queue: nil, using: { fnote in
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
    
    func registerUndoCommentContext(_ context: [String : Any]) {
		undoManager.registerUndoComment( context )
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
		var prevQuery: ServerQuery? = nil
		for q in quadList {
			if let prevQuery = prevQuery,
			   q.rect.origin.y == prevQuery.rect.origin.y,
			   q.rect.origin.x == prevQuery.rect.origin.x + prevQuery.rect.size.width,
			   q.rect.size.height == prevQuery.rect.size.height
			{
				// combine with previous quad(s)
				prevQuery.quadList.append( q )
				prevQuery.rect.size.width += q.rect.size.width
			} else {
				// create new query for quad
				prevQuery = ServerQuery()
				prevQuery!.quadList = [q]
				prevQuery!.rect = q.rect
				queries.append( prevQuery! )
            }
        }
        
        // any items that didn't get grouped get put back on the list
		quadList = queries.compactMap({ query in
			return query.quadList.count == 1 ? query.quadList[0] : nil
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
				prevQuery.quadList.append( q )
				prevQuery.rect.size.height += q.rect.size.height
			} else {
				prevQuery = ServerQuery()
				prevQuery!.quadList = [q]
				prevQuery!.rect = q.rect
				queries.append( prevQuery! )
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
    
    // http://wiki.openstreetmap.org/wiki/API_v0.6#Retrieving_map_data_by_bounding_box:_GET_.2Fapi.2F0.6.2Fmap
    private func osmData(forUrl url: String, quads: ServerQuery?, completion: @escaping (_ quads: ServerQuery?, _ data: OsmMapData?, _ error: Error?) -> Void) {
        DownloadThreadPool.osmPool().stream(forUrl: url, callback: { stream, error2 in
            if error2 != nil || stream?.streamError != nil {
                
                DispatchQueue.main.async(execute: {
                    completion(quads, nil, (stream?.streamError ?? error2)!)
                })
            } else {
				let stream = stream!
				var mapData: OsmMapData? = OsmMapData()
				var err: Error? = nil
                do {
                    try mapData!.parseXmlStream(stream)
                } catch {
					if stream.streamError != nil {
                        err = stream.streamError
                    } else if err != nil {
                        // use the parser's reported error
                    } else {
                        err = NSError(domain: "parser", code: 100, userInfo: [
                            NSLocalizedDescriptionKey: NSLocalizedString("Data not available", comment: "")
                        ])
                    }
                }
                if err != nil {
                    mapData = nil
                }
                DispatchQueue.main.async(execute: {
                    completion(quads, mapData, err)
                })
            }
            
        })
    }
    
	private func osmData(forBox query: ServerQuery, completion: @escaping (_ query: ServerQuery?, _ data: OsmMapData?, _ error: Error?) -> Void) {
		let box = query.rect
        let x = box.origin.x
		let y = box.origin.y
		let width = box.size.width
		let height = box.size.height
		let url = OSM_API_URL + "api/0.6/map?bbox=\(x),\(y),\(x + width),\(y + height)"
		self.osmData(forUrl: url, quads: query, completion: completion)
    }
    
    // download data
    func update(withBox box: OSMRect, progressDelegate progress: (NSObjectProtocol & MapViewProgress)?, completion: @escaping (_ partial: Bool, _ error: Error?) -> Void) {
        var activeRequests = 0
        let mergePartialResults: ((_ query: ServerQuery?, _ mapData: OsmMapData?, _ error: Error?) -> Void) = { [self] query, mapData, error in
            progress?.progressDecrement()
            activeRequests -= 1
			try? merge(mapData, fromDownload: true, quadList: query?.quadList ?? [], success: (mapData != nil && error == nil))
            completion(activeRequests > 0, error)
        }
        
        // get list of new quads to fetch
        let newQuads = region.newQuads(forRect: box)
		if newQuads.count == 0 {
			activeRequests += 1
			progress?.progressIncrement()
			mergePartialResults(nil, nil, nil)
		} else {
			let queryList = OsmMapData.coalesceQuadQueries(newQuads)
			for query in queryList {
				activeRequests += 1
				progress?.progressIncrement()
				osmData(forBox: query, completion: mergePartialResults)
			}
		}
        
        progress?.progressAnimate()
    }
    
    func cancelCurrentDownloads() {
        if DownloadThreadPool.osmPool().downloadsInProgress() > 0 {
            DownloadThreadPool.osmPool().cancelAllDownloads()
        }
    }
    
    // MARK: Download parsing
    
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes attributeDict: [String : String] = [:]) {
        parserCurrentElementText = nil

        if elementName == "node" {
            let lat = Double(attributeDict["lat"] ?? "") ?? 0.0
            let lon = Double(attributeDict["lon"] ?? "") ?? 0.0
            let node = OsmNode(fromXmlDict: attributeDict)!
			node.setLongitude(lon, latitude: lat, undo: nil)
            nodes[node.ident] = node
            parserStack.append(node)
        } else if elementName == "way" {
            let way = OsmWay(fromXmlDict: attributeDict)!
            ways[way.ident] = way
            parserStack.append(way)
        } else if elementName == "tag" {
            let key = attributeDict["k"]!
            let value = attributeDict["v"]!
			let object = parserStack.last as! OsmBaseObject
            object.constructTag(key, value: value)
            parserStack.append("tag")
        } else if elementName == "nd" {
            let way = parserStack.last as? OsmWay
            let ref = attributeDict["ref"]
            assert((ref != nil))
            way?.constructNode(NSNumber(value: Int64(ref ?? "") ?? 0))
            parserStack.append("nd")
        } else if elementName == "relation" {
            let relation = OsmRelation(fromXmlDict: attributeDict)!
            relations[relation.ident] = relation
            parserStack.append(relation)
        } else if elementName == "member" {
            let type = attributeDict["type"]
            let ref = NSNumber(value: Int64(attributeDict["ref"] ?? "") ?? 0)
            let role = attributeDict["role"]
            let member = OsmMember(type: type, ref: ref.int64Value, role: role)
            let relation = parserStack.last as! OsmRelation
            relation.constructMember(member)
            parserStack.append(member)
        } else if elementName == "osm" {
            
            // osm header
            let version = attributeDict["version"]
            if version != "0.6" {
                parseError = NSError(domain: "Parser", code: 102, userInfo: [
                    NSLocalizedDescriptionKey: String.localizedStringWithFormat(NSLocalizedString("OSM data must be version 0.6 (fetched '%@')", comment: ""), version ?? "")
                ])
                parser.abortParsing()
            }
            parserStack.append("osm")
        } else if elementName == "bounds" {
#if false
            let minLat = Double(attributeDict["minlat"] ?? "") ?? 0.0
            let minLon = Double(attributeDict["minlon"] ?? "") ?? 0.0
            let maxLat = Double(attributeDict["maxlat"] ?? "") ?? 0.0
            let maxLon = Double(attributeDict["maxlon"] ?? "") ?? 0.0
#endif
            parserStack.append("bounds")
        } else if elementName == "note" {
            
            // issued by Overpass API server
            parserStack.append(elementName)
        } else if elementName == "meta" {
            
            // issued by Overpass API server
            parserStack.append(elementName)
        } else {
            
            DLog("OSM parser: Unknown tag '%@'", elementName)
            parserStack.append(elementName)
#if false
            parseError = NSError(domain: "Parser", code: 102, userInfo: [
                NSLocalizedDescriptionKey: "OSM parser: Unknown tag '\(elementName)'"
            ])
            parser.abortParsing()
#endif
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        parserStack.removeLast()
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if parserCurrentElementText == nil {
            parserCurrentElementText = string
        } else {
			parserCurrentElementText!.append( string )
        }
    }
    
    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        DLog("Parse error: \(parseError.localizedDescription), line \(parser.lineNumber), column \(parser.columnNumber)")
        self.parseError = parseError
    }
    
    func parserDidEndDocument(_ parser: XMLParser) {
        assert(parserStack.count == 0 || parseError != nil)
        parserCurrentElementText = nil
        parserStack = []
    }
    
    func parseXmlStream(_ stream: InputStream) throws {
		defer {
			stream.close()
		}

		let parser = XMLParser(stream: stream)
		parser.delegate = self
        parseError = nil

        let ok = parser.parse() && parseError == nil
		if !ok {
			throw parseError!
        }
    }
    
	func merge(_ newData: OsmMapData?, fromDownload downloaded: Bool, quadList: [QuadBox], success: Bool) throws {
		if let newData = newData {
            var newNodes: [OsmNode] = []
            var newWays: [OsmWay] = []
            var newRelations: [OsmRelation] = []
            
			for (key, node) in newData.nodes {
				let current = nodes[key]
				if current == nil {
                    nodes[key] = node
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
            
            for (key, way) in newData.ways {
                let current = ways[key]
                if current == nil {
                    ways[key] = way
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
            
			for (key, relation) in newData.relations {
				let current = relations[key]
				if current == nil {
					relations[key] = relation
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
            
            for (_, node) in newData.nodes {
                node.setConstructed()
            }
            for (_, way) in newData.ways {
                way.setConstructed()
            }
            for (_, relation) in newData.relations {
                relation.setConstructed()
            }
            
            // store new nodes in database
            if downloaded {
                sqlSaveNodes(newNodes, saveWays: newWays, saveRelations: newRelations, deleteNodes: [], deleteWays: [], deleteRelations: [], isUpdate: false)
                
                // purge old data
                DispatchQueue.main.asyncAfter(deadline: (DispatchTime.now() + 1.0), execute: {
                    AppDelegate.shared.mapView.discardStaleData()
                })
            }
        }
        
        for q in quadList {
            region.makeWhole(q, success: success)
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
				if let attribute = DDXMLNode.attribute(withName: "changeset", stringValue: String(changesetID)) as? DDXMLNode {
					osmObject.addAttribute(attribute)
				}
            }
        }
    }
    
    func uploadChangesetXML(_ xmlChanges: DDXMLDocument, changesetID: Int64, retries: Int, completion: @escaping (_ errorMessage: String?) -> Void) {
        let url2 = OSM_API_URL + "api/0.6/changeset/\(changesetID)/upload"
        putRequest(url2, method: "POST", xml: xmlChanges) { [self] postData, postErrorMessage in
			guard let postData = postData else {
				completion( postErrorMessage )
				return
			}
			let response = String(decoding: postData, as: UTF8.self)

            if retries > 0 && response.hasPrefix("Version mismatch") {
				// update the bad element and retry
				DLog( "Upload error: \(response)")
				var localVersion = 0
				var serverVersion = 0
				var serverType: NSString? = ""
				var objId: OsmIdentifier = 0
				// "Version mismatch: Provided %d, server had: %d of %[a-zA-Z] %lld"
				let scanner = Scanner(string: response)
				if scanner.scanString("Version mismatch: Provided", into:nil),
				   scanner.scanInt(&localVersion),
				   scanner.scanString(", server had:", into: nil),
				   scanner.scanInt(&serverVersion),
				   scanner.scanString("of", into: nil),
				   scanner.scanCharacters(from: CharacterSet.alphanumerics, into: &serverType),
				   scanner.scanInt64(&objId),
				   let serverType = serverType
				{
					var serverType = serverType as String
					serverType = serverType.lowercased()
					var url3 = OSM_API_URL + "api/0.6/\(serverType)/\(objId)"
					if serverType == "way" || serverType == "relation" {
						url3 = url3 + "/full"
					}
					osmData(forUrl: url3, quads: nil, completion: { quads, mapData, error in
						try? merge(mapData, fromDownload: true, quadList: [], success: true)
						// try again:
						uploadChangeset(changesetID, retries:retries-1, completion:completion)
					})
					return;
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
            
            var sqlUpdate: [OsmBaseObject : Bool] = [:]
			for element in diffDoc.rootElement()?.children ?? [] {
                guard let element = element as? DDXMLElement else {
                    continue
                }
                let name = element.name
                let oldId = Int64(element.attribute(forName: "old_id")?.stringValue ?? "0")!
                let newId = Int64(element.attribute(forName: "new_id")?.stringValue ?? "0")!
                let newVersion = Int(element.attribute(forName: "new_version")?.stringValue ?? "0")!
                
                if name == "node" {
					updateObjectDictionary(&nodes, oldId: oldId, newId: newId, version: newVersion, changeset: changesetID, sqlUpdate: &sqlUpdate)
                } else if name == "way" {
                    updateObjectDictionary(&ways, oldId: oldId, newId: newId, version: newVersion, changeset: changesetID, sqlUpdate: &sqlUpdate)
                } else if name == "relation" {
                    updateObjectDictionary(&relations, oldId: oldId, newId: newId, version: newVersion, changeset: changesetID, sqlUpdate: &sqlUpdate)
				} else {
                    DLog("Bad upload diff document")
                }
            }
            
            updateSql(sqlUpdate)
            
            let url3 = OSM_API_URL + "api/0.6/changeset/\(changesetID)/close"
            putRequest(url3, method: "PUT", xml: nil) { data, errorMessage in
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
		guard let xmlChanges = createXml() else {
			completion("Failure generating XML")
			return
		}
		OsmMapData.updateChangesetXml(xmlChanges, withChangesetID: changesetID)
		uploadChangesetXML(xmlChanges, changesetID: changesetID, retries: retries, completion: completion)
    }
    
    class func element(for object: OsmBaseObject) -> DDXMLElement {
		guard let type = (object.isNode() != nil) ? "node" : (object.isWay() != nil) ? "way" : (object.isRelation() != nil) ? "relation" : nil else {
			fatalError()
		}
        let element = DDXMLNode.element(withName: type) as! DDXMLElement
        if let attribute = DDXMLNode.attribute(withName: "id", stringValue: NSNumber(value: object.ident).stringValue) as? DDXMLNode {
            element.addAttribute(attribute)
        }
        if let attribute = DDXMLNode.attribute(withName: "timestamp", stringValue: object.timestamp) as? DDXMLNode {
            element.addAttribute(attribute)
        }
        if let attribute = DDXMLNode.attribute(withName: "version", stringValue: NSNumber(value: object.version).stringValue) as? DDXMLNode {
            element.addAttribute(attribute)
        }
        return element
    }
    
    class func addTags(for object: OsmBaseObject, element: DDXMLElement) {
        for (key, value) in object.tags {
            let tagElement = DDXMLElement.element(withName: "tag") as! DDXMLElement
			if let attribute = DDXMLNode.attribute(withName: "k", stringValue: key) as? DDXMLNode {
                tagElement.addAttribute(attribute)
            }
            if let attribute = DDXMLNode.attribute(withName: "v", stringValue: value) as? DDXMLNode {
                tagElement.addAttribute(attribute)
            }
			element.addChild(tagElement)
        }
    }
    
    //MARK: Upload
    
	func updateObjectDictionary<T:OsmBaseObject>(_ dictionary: inout [OsmIdentifier : T], oldId: OsmIdentifier, newId: OsmIdentifier, version newVersion: Int, changeset: Int64, sqlUpdate: inout [OsmBaseObject : Bool]) {
		let object = dictionary[oldId]!
		assert(object.ident == oldId)
        if newVersion == 0 && newId == 0 {
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
    
    func createXml() -> DDXMLDocument? {
        let createNodeElement = DDXMLNode.element(withName: "create") as! DDXMLElement
        let modifyNodeElement = DDXMLNode.element(withName: "modify") as! DDXMLElement
        let deleteNodeElement = DDXMLNode.element(withName: "delete") as! DDXMLElement
        let createWayElement = DDXMLNode.element(withName: "create") as! DDXMLElement
        let modifyWayElement = DDXMLNode.element(withName: "modify") as! DDXMLElement
        let deleteWayElement = DDXMLNode.element(withName: "delete") as! DDXMLElement
        let createRelationElement = DDXMLNode.element(withName: "create") as! DDXMLElement
        let modifyRelationElement = DDXMLNode.element(withName: "modify") as! DDXMLElement
        let deleteRelationElement = DDXMLNode.element(withName: "delete") as! DDXMLElement
        
        if let attribute = DDXMLNode.attribute(withName: "if-unused", stringValue: "yes") as? DDXMLNode {
            deleteNodeElement.addAttribute(attribute)
        }
        if let attribute = DDXMLNode.attribute(withName: "if-unused", stringValue: "yes") as? DDXMLNode {
            deleteWayElement.addAttribute(attribute)
        }
        if let attribute = DDXMLNode.attribute(withName: "if-unused", stringValue: "yes") as? DDXMLNode {
            deleteRelationElement.addAttribute(attribute)
        }
        
        for (_, node) in nodes {
            if node.deleted && node.ident > 0 {
                // deleted
                let element = OsmMapData.element(for: node)
				deleteNodeElement.addChild(element)
            } else if node.isModified() && !node.deleted {
                // added/modified
                let element = OsmMapData.element(for: node)
                if let attribute = DDXMLNode.attribute(withName: "lat", stringValue: NSNumber(value: node.lat).stringValue) as? DDXMLNode {
                    element.addAttribute(attribute)
                }
                if let attribute = DDXMLNode.attribute(withName: "lon", stringValue: NSNumber(value: node.lon).stringValue) as? DDXMLNode {
                    element.addAttribute(attribute)
                }
                OsmMapData.addTags(for: node, element: element)
                if node.ident < 0 {
					createNodeElement.addChild(element)
                } else {
					modifyNodeElement.addChild(element)
                }
            }
        }
        
        for (_, way) in ways {
            if way.deleted && way.ident > 0 {
                let element = OsmMapData.element(for: way)
				deleteWayElement.addChild(element)
				for node in way.nodes {
					let nodeElement = OsmMapData.element(for: node)
					deleteWayElement.addChild(nodeElement)
				}
            } else if way.isModified() && !way.deleted {
                // added/modified
                let element = OsmMapData.element(for: way)
				for node in way.nodes {
					let refElement = DDXMLElement.element(withName: "nd") as! DDXMLElement
					if let attribute = DDXMLNode.attribute(withName: "ref", stringValue: NSNumber(value: node.ident).stringValue) as? DDXMLNode {
						refElement.addAttribute(attribute)
					}
					element.addChild(refElement)
				}
                OsmMapData.addTags(for: way, element: element)
                if way.ident < 0 {
					createWayElement.addChild(element)
                } else {
					modifyWayElement.addChild(element)
                }
            }
        }
        
        for (_, relation) in relations {
            if relation.deleted && relation.ident > 0 {
                let element = OsmMapData.element(for: relation)
				deleteRelationElement.addChild(element)
            } else if relation.isModified() && !relation.deleted {
                // added/modified
                let element = OsmMapData.element(for: relation)
				for member in relation.members {
					let memberElement = DDXMLElement.element(withName: "member") as? DDXMLElement
					if let attribute = DDXMLNode.attribute(withName: "type", stringValue: (member.type ?? "")) as? DDXMLNode {
						memberElement?.addAttribute(attribute)
					}
					if let attribute = DDXMLNode.attribute(withName: "ref", stringValue: NSNumber(value: member.ref).stringValue) as? DDXMLNode {
						memberElement?.addAttribute(attribute)
					}
					if let attribute = DDXMLNode.attribute(withName: "role", stringValue: (member.role ?? "")) as? DDXMLNode {
						memberElement?.addAttribute(attribute)
					}
					if let memberElement = memberElement {
						element.addChild(memberElement)
					}
				}
                OsmMapData.addTags(for: relation, element: element)
                if relation.ident < 0 {
					createRelationElement.addChild(element)
                } else {
					modifyRelationElement.addChild(element)
                }
            }
        }
        
#if os(iOS)
        let appDelegate = AppDelegate.shared
        let appName = appDelegate.appName()
		let appVersion = appDelegate.appVersion()
		let text = """
                <?xml version="1.0"?>\
                <osmChange generator="\(appName) \(appVersion)" version="0.6"></osmChange>
                """
		let doc = try! DDXMLDocument(xmlString: text, options: 0)
        let root = doc.rootElement()!
#else
        let appDelegate = NSApplication.shared.delegate as? AppDelegate
        let root = XMLNode.element(withName: "osmChange") as? XMLElement
        if let attribute = XMLNode.attribute(withName: "generator", stringValue: appDelegate?.appName ?? "") as? DDXMLNode {
            root?.addAttribute(attribute)
        }
        if let attribute = XMLNode.attribute(withName: "version", stringValue: "0.6") as? DDXMLNode {
            root?.addAttribute(attribute)
        }
        let doc = XMLDocument(rootElement: root)
        doc.characterEncoding = "UTF-8"
#endif
		if createNodeElement.childCount > 0 {
			root.addChild(createNodeElement)
		}
		if createWayElement.childCount > 0 {
			root.addChild(createWayElement)
		}
		if createRelationElement.childCount > 0 {
			root.addChild(createRelationElement)
		}

		if modifyNodeElement.childCount > 0 {
			root.addChild(modifyNodeElement)
		}
		if modifyWayElement.childCount > 0 {
			root.addChild(modifyWayElement)
		}
		if modifyRelationElement.childCount > 0 {
			root.addChild(modifyRelationElement)
		}

		if deleteRelationElement.childCount > 0 {
			root.addChild(deleteRelationElement)
		}
		if deleteWayElement.childCount > 0 {
			root.addChild(deleteWayElement)
		}
		if deleteNodeElement.childCount > 0 {
			root.addChild(deleteNodeElement)
		}

		if root.childCount == 0 {
			return nil // nothing to add
		}

        return doc
    }
    
    func putRequest(_ url: String, method: String, xml: DDXMLDocument?, completion: @escaping (_ data: Data?, _ error: String?) -> Void) {
		guard let url1 = URL(string: url) else {
			completion(nil,"Unable to build URL")
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
				if data != nil && error == nil && httpResponse != nil && (httpResponse?.statusCode ?? 0) >= 200 && (httpResponse?.statusCode ?? 0) <= 299 {
					completion(data, nil)
				} else {
					var errorMessage: String?
					if (data?.count ?? 0) > 0 {
						data?.withUnsafeBytes { bytes in
							errorMessage = String(bytes: bytes, encoding: .utf8)
						}
					} else {
						errorMessage = error != nil ? error?.localizedDescription : httpResponse != nil ? String(format: "HTTP Error %ld", Int(httpResponse?.statusCode ?? 0)) : "Unknown error"
					}
					errorMessage = (errorMessage ?? "") + "\n\n\(method) \(url)"
					completion(nil, errorMessage ?? "")
				}
			})
		})
        task.resume()
    }
    
    class func createXml(withType type: String?, tags dictionary: [String : String]) -> DDXMLDocument? {
#if os(iOS)
        var doc: DDXMLDocument? = nil
        do {
            doc = try DDXMLDocument(xmlString: "<osm></osm>", options: 0)
        } catch {
        }
        let root = doc?.rootElement()
#else
        let root = DDXMLNode.element(withName: "osm") as? DDXMLElement
        let doc = DDXMLDocument(rootElement: root)
        doc.characterEncoding = "UTF-8"
#endif
        let typeElement = DDXMLNode.element(withName: type ?? "") as? DDXMLElement
        if let typeElement = typeElement {
            root?.addChild(typeElement)
        }
        
        for (key, value) in dictionary {
            let tag = DDXMLNode.element(withName: "tag") as? DDXMLElement
            if let tag = tag {
                typeElement?.addChild(tag)
            }
            let attrKey = DDXMLNode.attribute(withName: "k", stringValue: key) as? DDXMLNode
            let attrValue = DDXMLNode.attribute(withName: "v", stringValue: value) as? DDXMLNode
            if let attrKey = attrKey {
                tag?.addAttribute(attrKey)
            }
            if let attrValue = attrValue {
                tag?.addAttribute(attrValue)
            }

        }
        
        return doc
    }
    
    // create a new changeset to upload to
    func createChangeset(withComment comment: String, source: String, imagery: String, completion: @escaping (_ changesetID: Int64?, _ errorMessage: String?) -> Void) {
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
        if let xmlCreate = OsmMapData.createXml(withType: "changeset", tags: tags) {
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
    func uploadChangeset(withComment comment: String, source: String, imagery: String, completion: @escaping (_ errorMessage: String?) -> Void) {
        createChangeset(withComment: comment, source: source, imagery: imagery) { [self] changesetID, errorMessage in
            if let changesetID = changesetID {
                uploadChangeset(changesetID, retries: 20, completion: completion)
            } else {
                completion(errorMessage)
            }
        }
    }
    
    // upload xml edited by user
    func uploadChangesetXml(_ xmlChanges: DDXMLDocument, comment: String, source: String, imagery: String, completion: @escaping (_ error: String?) -> Void) {
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
    
    // MARK: Pretty print changeset
    
    func update(_ string: NSMutableAttributedString?, withTag tag: DDXMLElement?) {
#if os(iOS)
        let font = UIFont.preferredFont(forTextStyle: .callout)
#else
        let font = NSFont.labelFont(ofSize: 12)
#endif
        
        var foregroundColor = UIColor.black
        if #available(iOS 13.0, *) {
            foregroundColor = UIColor.label
        }
        
        let text = "\t\t\(tag?.attribute(forName: "k")?.stringValue ?? "") = \(tag?.attribute(forName: "v")?.stringValue ?? "")\n"
        string?.append(NSAttributedString(string: text, attributes: [
            NSAttributedString.Key.font: font,
            NSAttributedString.Key.foregroundColor: foregroundColor
        ]))
    }
    
    func update(_ string: NSMutableAttributedString?, withMember tag: DDXMLElement?) {
#if os(iOS)
        let font = UIFont.preferredFont(forTextStyle: .callout)
#else
        let font = NSFont.labelFont(ofSize: 12)
#endif
        var foregroundColor = UIColor.black
        if #available(iOS 13.0, *) {
            foregroundColor = UIColor.label
        }
        
        let text = "\t\t\(tag?.attribute(forName: "type")?.stringValue ?? "") \(tag?.attribute(forName: "ref")?.stringValue ?? ""): \"\(tag?.attribute(forName: "role")?.stringValue ?? "")\"\n"
        string?.append(NSAttributedString(string: text, attributes: [
            NSAttributedString.Key.font: font,
            NSAttributedString.Key.foregroundColor: foregroundColor
        ]))
    }
    
    func update(_ string: NSMutableAttributedString?, withNode node: DDXMLElement?) {
#if os(iOS)
        let font = UIFont.preferredFont(forTextStyle: .body)
#else
        let font = NSFont.labelFont(ofSize: 12)
#endif
        
        var foregroundColor = UIColor.black
        if #available(iOS 13.0, *) {
            foregroundColor = UIColor.label
        }
        
        let nodeName = node?.attribute(forName: "id")?.stringValue
        string?.append(NSAttributedString(string: "\tNode ", attributes: [
            NSAttributedString.Key.font: font,
            NSAttributedString.Key.foregroundColor: foregroundColor
        ]))
        string?.append(
            NSAttributedString(
                string: nodeName ?? "",
                attributes: [
                    NSAttributedString.Key.font: font,
                    NSAttributedString.Key.link: "n" + (nodeName ?? "")
                ]))
        string?.append(NSAttributedString(string: "\n", attributes: [
            NSAttributedString.Key.font: font
        ]))
        for tag in node?.children ?? [] {
            guard let tag = tag as? DDXMLElement else {
                continue
            }
            if tag.name == "tag" {
                update(string, withTag: tag)
            } else {
                assert(false)
            }
        }
    }
    
    func update(_ string: NSMutableAttributedString?, withWay way: DDXMLElement?) {
        var nodeCount = 0
        for tag in way?.children ?? [] {
            guard let tag = tag as? DDXMLElement else {
                continue
            }
            if tag.name == "nd" {
                nodeCount += 1
            }
        }
        
#if os(iOS)
        let font = UIFont.preferredFont(forTextStyle: .body)
#else
        let font = NSFont.labelFont(ofSize: 12)
#endif
        
        var foregroundColor = UIColor.black
        if #available(iOS 13.0, *) {
            foregroundColor = UIColor.label
        }
        
        let wayName = way?.attribute(forName: "id")?.stringValue
        string?.append(NSAttributedString(string: NSLocalizedString("\tWay ", comment: ""), attributes: [
            NSAttributedString.Key.font: font,
            NSAttributedString.Key.foregroundColor: foregroundColor
        ]))
        string?.append(
            NSAttributedString(
                string: wayName ?? "",
                attributes: [
                    NSAttributedString.Key.font: font,
                    NSAttributedString.Key.link: "w" + (wayName ?? "")
                ]))
        string?.append(
            NSAttributedString(
                string: String.localizedStringWithFormat(NSLocalizedString(" (%d nodes)\n", comment: ""), nodeCount),
                attributes: [
                    NSAttributedString.Key.font: font,
                    NSAttributedString.Key.foregroundColor: foregroundColor
                ]))
        
        for tag in way?.children ?? [] {
            guard let tag = tag as? DDXMLElement else {
                continue
            }
            if tag.name == "tag" {
                update(string, withTag: tag)
            } else if tag.name == "nd" {
                // skip
            } else {
                assert(false)
            }
        }
    }
    
    func update(_ string: NSMutableAttributedString?, withRelation relation: DDXMLElement?) {
        var memberCount = 0
        for tag in relation?.children ?? [] {
            guard let tag = tag as? DDXMLElement else {
                continue
            }
            if tag.name == "member" {
                memberCount += 1
            }
        }
        
#if os(iOS)
        let font = UIFont.preferredFont(forTextStyle: .body)
#else
        let font = NSFont.labelFont(ofSize: 12)
#endif
        
        var foregroundColor = UIColor.black
        if #available(iOS 13.0, *) {
            foregroundColor = UIColor.label
        }
        
        let relationName = relation?.attribute(forName: "id")?.stringValue
        string?.append(NSAttributedString(string: NSLocalizedString("\tRelation ", comment: ""), attributes: [
            NSAttributedString.Key.font: font,
            NSAttributedString.Key.foregroundColor: foregroundColor
        ]))
        string?.append(
            NSAttributedString(
                string: relationName ?? "",
                attributes: [
                    NSAttributedString.Key.font: font,
                    NSAttributedString.Key.link: "r" + (relationName ?? "")
                ]))
        string?.append(
            NSAttributedString(
                string: String.localizedStringWithFormat(NSLocalizedString(" (%d members)\n", comment: ""), memberCount),
                attributes: [
                    NSAttributedString.Key.font: font,
                    NSAttributedString.Key.foregroundColor: foregroundColor
                ]))
        
        for tag in relation?.children ?? [] {
            guard let tag = tag as? DDXMLElement else {
                continue
            }
            if tag.name == "tag" {
                update(string, withTag: tag)
            } else if tag.name == "member" {
                update(string, withMember: tag)
            } else {
                assert(false)
            }
        }
    }
    
    func update(_ string: NSMutableAttributedString?, withHeader header: String?, objects: [AnyHashable]?) {
        if (objects?.count ?? 0) == 0 {
            return
        }
        
        var foregroundColor = UIColor.black
        if #available(iOS 13.0, *) {
            foregroundColor = UIColor.label
        }
        
#if os(iOS)
        let font = UIFont.preferredFont(forTextStyle: .headline)
#else
        let font = NSFont.labelFont(ofSize: 12)
#endif
        string?.append(NSAttributedString(string: header ?? "", attributes: [
            NSAttributedString.Key.font: font,
            NSAttributedString.Key.foregroundColor: foregroundColor
        ]))
        for object in objects ?? [] {
            guard let object = object as? DDXMLElement else {
                continue
            }
            if object.name == "node" {
                update(string, withNode: object)
            } else if object.name == "way" {
                update(string, withWay: object)
            } else if object.name == "relation" {
                update(string, withRelation: object)
            } else {
                assert(false)
            }
        }
    }
    
    // upload changeset
    func changesetAsAttributedString() -> NSAttributedString? {
        let doc = createXml()
        if doc == nil {
            return nil
        }
        let string = NSMutableAttributedString()
        let root = doc?.rootElement()
        
        let deletes = root?.elements(forName: "delete")
        let creates = root?.elements(forName: "create")
        let modifys = root?.elements(forName: "modify")
        for delete in deletes ?? [] {
            update(string, withHeader: NSLocalizedString("Delete\n", comment: ""), objects: delete.children)
        }
        for create in creates ?? [] {
            update(string, withHeader: NSLocalizedString("Create\n", comment: ""), objects: create.children)
        }
        for modify in modifys ?? [] {
            update(string, withHeader: NSLocalizedString("Modify\n", comment: ""), objects: modify.children)
        }
        return string
    }
    
    func changesetAsXml() -> String? {
        let xml = createXml()
        if xml == nil {
            return nil
        }
        return xml!.xmlString(withOptions: UInt(DDXMLNodePrettyPrint))
    }
    
    // MARK: Save/Restore
    
    func encode(with coder: NSCoder) {
        coder.encode(nodes, forKey: "nodes")
        coder.encode(ways, forKey: "ways")
        coder.encode(relations, forKey: "relations")
        coder.encode(region, forKey: "region")
        coder.encode(spatial, forKey: "spatial")
        coder.encode(undoManager, forKey: "undoManager")
    }
    
    required convenience init?(coder: NSCoder) {
		self.init()

		guard
			let nodes = coder.decodeObject(forKey: "nodes") as? [OsmIdentifier : OsmNode],
			let ways = coder.decodeObject(forKey: "ways") as? [OsmIdentifier : OsmWay],
			let relations = coder.decodeObject(forKey: "relations") as? [OsmIdentifier : OsmRelation],
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
		var objects = Array( undoManager.objectRefs() )
		objects +=     nodes.values.filter({ $0.deleted ? ($0.ident > 0) : $0.isModified() })
		objects +=      ways.values.filter({ $0.deleted ? ($0.ident > 0) : $0.isModified() })
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
        spatial.rootQuad.reset()
        region = QuadMap()
        
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
                _=dirty.insert(object)
            }
        }
        for (_, object) in ways {
            if object.isModified() {
				_=dirty.insert(object)
            }
        }
        for (_, object) in relations {
            if object.isModified() {
				_=dirty.insert(object)
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
			_=rel.resolveToMapData(self)
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
		let path = URL(fileURLWithPath: URL(fileURLWithPath: paths[0]).appendingPathComponent(bundleName ?? "").path).appendingPathComponent("OSM Downloaded Data.archive").path
		try? FileManager.default.createDirectory(atPath: URL(fileURLWithPath: path).deletingLastPathComponent().path, withIntermediateDirectories: true, attributes: nil)
		return path
    }

    
    func sqlSaveNodes(_ saveNodes: [OsmNode], saveWays: [OsmWay], saveRelations: [OsmRelation], deleteNodes: [OsmNode], deleteWays: [OsmWay], deleteRelations: [OsmRelation], isUpdate: Bool) {
		if (saveNodes.count + saveWays.count + saveRelations.count + deleteNodes.count + deleteWays.count + deleteRelations.count) == 0 {
            return
        }
        Database.dispatchQueue.async(execute: { [self] in
            var t = CACurrentMediaTime()
            var ok: Bool = false
			do {
				guard let db = Database(name: "") else {
					throw NSError()
				}
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
                DLog("\(t > 1.0 ? "*** " : "")sql save \(saveNodes.count + saveWays.count + saveRelations.count) objects, time = \(t) (\(Int(nodeCount()) + Int(wayCount()) + Int(relationCount()))) objects total)")
                if !ok {
                    // database failure
                    region = QuadMap()
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
        while(true)  {
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
                print(String(format: "Discarding %f%% stale data %ld seconds old\n", 100 * fraction, Int(ceil(interval))))
            } else if interval < 60 * 60 {
                print(String(format: "Discarding %f%% stale data %ld minutes old\n", 100 * fraction, Int(interval) / 60))
            } else {
                print(String(format: "Discarding %f%% stale data %ld hours old\n", 100 * fraction, Int(interval) / 60 / 60))
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
                        node.setWayCount((node.wayCount-1), undo: nil)
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
                if !didExpand && removeNodes.count + removeWays.count + removeRelations.count == 0 {
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
			_=relation.resolveToMapData(self)
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
				guard let db2 = Database(name: "tmp") else {
					throw NSError()
				}
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
            print(String(format: "%@Discard save time = %f, saved %ld objects\n", t2 > 1.0 ? "*** " : "", t2, Int(nodeCount()) + Int(wayCount()) + Int(relationCount())))
            
            DispatchQueue.main.async(execute: {
                previousDiscardDate = Date()
            })
        })

        return true
    }
    
    // after uploading a changeset we have to update the SQL database to reflect the changes the server replied with
    func updateSql(_ sqlUpdate: [OsmBaseObject : Bool]) {
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
        
        sqlSaveNodes(insertNode, saveWays: insertWay, saveRelations: insertRelation, deleteNodes: deleteNode, deleteWays: deleteWay, deleteRelations: deleteRelation, isUpdate: true)
    }
    
    func archiveModifiedData() {
        var t = CACurrentMediaTime()
        // save dirty data and relations
		DbgAssert((OsmMapData.g_EditorMapLayerForArchive != nil))

		// save our original data
		let origNodes = self.nodes
		let origWays = self.ways
		let origRelations = self.relations
		let origSpatial = self.spatial

		// update self with minimized versions appropriate for saving
		let modified = self.modifiedObjects()
		self.nodes = modified.nodes
		self.ways = modified.ways
		self.relations = modified.relations
		self.spatial = QuadMap()

		// Do the save.
		let archiver = OsmMapDataArchiver()
		_=archiver.saveArchive(mapData: self)

		// restore originals
		self.nodes = origNodes
		self.ways = origWays
		self.relations = origRelations
		self.spatial = origSpatial

        t = CACurrentMediaTime() - t
		DLog("Archive save \(modified.nodeCount()),\(modified.wayCount()),\(modified.relationCount()),\(undoManager.countUndoGroups),\(region.countOfObjects()) = \(t)")

        periodicSaveTimer?.invalidate()
        periodicSaveTimer = nil
    }
    
    static func withArchivedData() -> OsmMapData? {

		let archiver = OsmMapDataArchiver()
		guard let decode = archiver.loadArchive() else { return nil }
		if decode.spatial.countOfObjects() > 0 {
			print("spatial accidentally saved, please fix")
			decode.spatial = QuadMap()
		}

		// rebuild spatial database
		decode.enumerateObjects(usingBlock: { obj in
			if !obj.deleted {
				decode.spatial.addMember(obj, undo: nil)
            }
        })
        
        // merge info from SQL database
		do {
			guard let db = Database(name: "") else {
				throw NSError()
			}
			let newData = OsmMapData()
			newData.nodes = try db.querySqliteNodes()
			newData.ways = try db.querySqliteWays()
			newData.relations = try db.querySqliteRelations()

			try decode.merge(newData, fromDownload: false, quadList: [], success: true)
		} catch {
            // database couldn't be read
            print("Unable to read database: recreating from scratch\n")
			try? Database.delete(withName: "")
            // need to download all regions
			decode.region = QuadMap()
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
				assert( self.nodes[node.ident] === node )
			} else if let way = obj as? OsmWay {
				assert( self.ways[way.ident] === way )
			} else if let relation = obj as? OsmRelation {
				assert( self.relations[relation.ident] === relation )
			}
		}
#endif
	}
}

class OsmMapDataArchiver: NSObject, NSKeyedUnarchiverDelegate {

	func saveArchive( mapData: OsmMapData ) -> Bool {
		let path = OsmMapData.pathToArchiveFile()
		let data = NSMutableData()
		#if DEBUG
		assert(mapData.spatial.countOfObjects() == 0)
		#endif
		let archiver = NSKeyedArchiver(forWritingWith: data)
		archiver.encode(mapData, forKey: "OsmMapData")
		archiver.finishEncoding()
		let ok = data.write(toFile: path, atomically: true)
		return ok
	}

	func loadArchive() -> OsmMapData? {
		let path = OsmMapData.pathToArchiveFile()
		let url = URL(fileURLWithPath: path)
		guard let data = try? Data(contentsOf: url) else {
			return nil
		}

		let unarchiver = NSKeyedUnarchiver(forReadingWith: data )
		unarchiver.delegate = self
		guard let decode = unarchiver.decodeObject(forKey: "OsmMapData") as? OsmMapData else {
			return nil
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

	func unarchiver(_ unarchiver: NSKeyedUnarchiver, cannotDecodeObjectOfClassName name: String, originalClasses classNames: [String]) -> AnyClass? {
		DLog("archive error: %@", name)
		return nil
	}

	func unarchiver(_ unarchiver: NSKeyedUnarchiver, willReplace object: Any, with newObject: Any) {
		DLog("replacing \(object) -> \(newObject)")
	}

}
