//
//  OsmBaseObject.swift
//  Go Map!!
//
//  Created by Wolfgang Timme on 1/18/20.
//  Copyright © 2020 Bryce Cogswell. All rights reserved.
//

import Foundation
import UIKit

@objc enum OSM_TYPE: Int {
	case _NODE = 1
	case _WAY = 2
	case _RELATION = 3
}

@objc enum ONEWAY: Int {
	case _BACKWARD = -1
	case _NONE = 0
	case _FORWARD = 1
}

@objc enum TRISTATE: Int {
	case _UNKNOWN
	case _YES
	case _NO
}

let PATH_SCALING = (256 * 256.0)

typealias OsmIdentifier = Int64

struct OsmExtendedIdentifier: Equatable, Hashable {
	let rawValue: Int64
	init(_ type: OSM_TYPE, _ ident: OsmIdentifier) {
		rawValue = (Int64(type.rawValue) << 62) | ident
	}

	init(_ obj: OsmBaseObject) {
		let type: OSM_TYPE = obj is OsmNode ? ._NODE : obj is OsmWay ? ._WAY : ._RELATION
		self.init(type, obj.ident)
	}

	// FIXME: backward compat
	init(_ raw: Int64) {
		rawValue = raw
	}

	var type: OSM_TYPE {
		return OSM_TYPE(rawValue: Int(rawValue >> 62) & 3)!
	}

	var ident: OsmIdentifier {
		return OsmIdentifier(rawValue & ((Int64(1) << 62) - 1))
	}
}

@objcMembers
class OsmBaseObject: NSObject, NSCoding, NSCopying {
	private(set) final var ident: OsmIdentifier
	private(set) final var user: String
	private(set) final var timestamp: String
	private(set) final var version: Int
	private(set) final var changeset: OsmIdentifier
	private(set) final var uid: Int
	private(set) final var visible: Bool

	final var isShown = TRISTATE._UNKNOWN

	// extra stuff

	final var _constructed = false

	public final var renderPriorityCached = 0
	private var _deleted = false
	final var deleted: Bool {
		return _deleted
	}

	final var renderInfo: RenderInfo?
	private(set) final var modifyCount: Int32 = 0
	private(set) final var parentRelations: [OsmRelation] = []

	override init() {
		ident = 0
		user = ""
		timestamp = ""
		version = 0
		changeset = 0
		uid = 0
		visible = false
		_deleted = false
		modifyCount = 0
	}

	func encode(with coder: NSCoder) {
		coder.encode(NSNumber(value: ident), forKey: "ident")
		coder.encode(user, forKey: "user")
		coder.encode(timestamp, forKey: "timestamp")
		coder.encode(Int(version), forKey: "version")
		coder.encode(Int(changeset), forKey: "changeset")
		coder.encode(Int(uid), forKey: "uid")
		coder.encode(visible, forKey: "visible")
		coder.encode(tags, forKey: "tags")
		coder.encode(deleted, forKey: "deleted")
		coder.encode(modifyCount, forKey: "modified")
	}

	required init?(coder: NSCoder) {
		ident = (coder.decodeObject(forKey: "ident") as? NSNumber)?.int64Value ?? 0
		user = coder.decodeObject(forKey: "user") as? String ?? ""
		timestamp = coder.decodeObject(forKey: "timestamp") as? String ?? ""
		version = Int(coder.decodeInt32(forKey: "version"))
		changeset = OsmIdentifier(coder.decodeInteger(forKey: "changeset"))
		uid = Int(coder.decodeInt32(forKey: "uid"))
		visible = coder.decodeBool(forKey: "visible")
		_tags = coder.decodeObject(forKey: "tags") as? [String: String] ?? [:]
		_deleted = coder.decodeBool(forKey: "deleted")
		modifyCount = coder.decodeInt32(forKey: "modified")
		super.init()
		assert(ident != 0)
	}

	init(withVersion version: Int, changeset: Int64, user: String, uid: Int, ident: Int64, timestamp: String, tags: [String: String]) {
		self.version = version
		self.changeset = changeset
		self.user = user
		self.uid = uid
		visible = true
		self.ident = ident
		self.timestamp = timestamp
		_tags = tags
		super.init()
	}

	init?(fromXmlDict attributeDict: [String: Any]) {
		if let version = attributeDict["version"] as? String,
		   let version = Int(version),
		   let changeset = attributeDict["changeset"] as? String,
		   let changeset = Int64(changeset),
		   let user = attributeDict["user"] as? String,
		   let uid = attributeDict["uid"] as? String,
		   let uid = Int(uid),
		   let ident = attributeDict["id"] as? String,
		   let ident = Int64(ident),
		   let timestamp = attributeDict["timestamp"] as? String
		{
			self.version = version
			self.changeset = changeset
			self.user = user
			self.uid = uid
			visible = true
			self.ident = ident
			self.timestamp = timestamp
			_tags = [:]
			super.init()
		} else {
			return nil
		}
	}

#if DEBUG
	// sometimes we end up with duplicates of objects and they need to be disambiguated:
	func address() -> UnsafeRawPointer {
		return UnsafeRawPointer(Unmanaged.passUnretained(self).toOpaque())
	}
#endif

	var extendedIdentifier: OsmExtendedIdentifier {
		return OsmExtendedIdentifier(self)
	}

	// FIXME: back compat, delete this function
	static func extendedIdentifierForType(_ type: OSM_TYPE, identifier: Int64) -> Int64 {
		return OsmExtendedIdentifier(type, identifier).rawValue
	}

	// attributes

	private var _tags: [String: String] = NSMutableDictionary() as! [String: String]
	var tags: [String: String] {
		return _tags
	}

	public var _boundingBox: OSMRect? // public only so subclasses can set it
	var boundingBox: OSMRect {
		if _boundingBox == nil {
			computeBoundingBox()
		}
		return _boundingBox!
	}

	var shapeLayers: [CALayer & LayerPropertiesProviding]?

	private var _isOneWay: ONEWAY?
	var isOneWay: ONEWAY {
		if _isOneWay == nil {
			_isOneWay = (self as? OsmWay)?.computeIsOneWay() ?? ._NONE
		}
		return _isOneWay!
	}

	override var description: String {
		var text = "id=\(ident) constructed=\(_constructed ? "Yes" : "No") deleted=\(deleted ? "Yes" : "No") modifyCount=\(modifyCount)"
		for (key, value) in tags {
			text += "\n  '\(key)' = '\(value)'"
		}
		return text
	}

	func hasInterestingTags() -> Bool {
		for (key, _) in tags {
			if OsmTags.IsInterestingKey(key) {
				return true
			}
		}
		return false
	}

	func isCoastline() -> Bool {
		let natural = tags["natural"]
		if let natural = natural {
			if natural == "coastline" {
				return true
			}
			if natural == "water" {
				if isRelation() == nil, parentRelations.count == 0 {
					return false // its a lake or something
				}
				return true
			}
		}
		return false
	}

	func isNode() -> OsmNode? {
		return nil
	}

	func isWay() -> OsmWay? {
		return nil
	}

	func isRelation() -> OsmRelation? {
		return nil
	}

	public func computeBoundingBox() {
		fatalError()
	}

	func distance(toLineSegment point1: OSMPoint, point point2: OSMPoint) -> Double {
		fatalError()
	}

	func selectionPoint() -> LatLon {
		fatalError()
	}

	func latLonOnObject(forLatLon target: LatLon) -> LatLon {
		fatalError()
	}

	func linePathForObject(withOptionalRefPoint refPoint: UnsafeMutablePointer<OSMPoint>?) -> CGPath? {
		let wayList: [OsmWay]
		if let way = self as? OsmWay {
			wayList = [way]
		} else if let rel = self as? OsmRelation {
			wayList = rel.waysInMultipolygon()
		} else {
			return nil
		}

		let path = CGMutablePath()
		var initial = OSMPoint(x: 0, y: 0)
		var haveInitial = false

		for way in wayList {
			var first = true
			for node in way.nodes {
				var pt = MapTransform.mapPoint(forLatLon: node.latLon)
				if pt.x.isInfinite {
					break
				}
				if !haveInitial {
					initial = pt
					haveInitial = true
				}
				pt.x -= initial.x
				pt.y -= initial.y
				pt.x *= PATH_SCALING
				pt.y *= PATH_SCALING
				if first {
					path.move(to: CGPoint(x: pt.x, y: pt.y))
					first = false
				} else {
					path.addLine(to: CGPoint(x: pt.x, y: pt.y))
				}
			}
		}

		if refPoint != nil, haveInitial {
			// place refPoint at upper-left corner of bounding box so it can be the origin for the frame/anchorPoint
			let bbox = path.boundingBoxOfPath
			if !bbox.origin.x.isInfinite {
				var tran = CGAffineTransform(translationX: -bbox.origin.x, y: -bbox.origin.y)
				let path2 = path.copy(using: &tran)!
				refPoint!.pointee = OSMPoint(x: initial.x + Double(bbox.origin.x) / PATH_SCALING,
				                             y: initial.y + Double(bbox.origin.y) / PATH_SCALING)
				return path2
			} else {
#if DEBUG
				DLog("bad path: \(self)")
#endif
			}
		}
		return path
	}

	func linePathForObject(withRefPoint refPoint: UnsafeMutablePointer<OSMPoint>) -> CGPath? {
		return linePathForObject(withOptionalRefPoint: refPoint)
	}

	func linePathForObject() -> CGPath? {
		return linePathForObject(withOptionalRefPoint: nil)
	}

	// suitable for drawing polygon areas with holes, etc.
	func shapePathForObject(withRefPoint pRefPoint: UnsafeMutablePointer<OSMPoint>) -> CGPath? {
		assert(false)
		return nil
	}

	static var _nextUnusedIdentifier: Int64 = 0
	static func nextUnusedIdentifier() -> Int64 {
		if OsmBaseObject._nextUnusedIdentifier == 0 {
			OsmBaseObject._nextUnusedIdentifier = Int64(UserDefaults.standard.integer(forKey: "nextUnusedIdentifier"))
		}
		OsmBaseObject._nextUnusedIdentifier -= 1
		UserDefaults.standard.set(OsmBaseObject._nextUnusedIdentifier, forKey: "nextUnusedIdentifier")
		return OsmBaseObject._nextUnusedIdentifier
	}

	// MARK: Construction

	func constructTag(_ tag: String, value: String) {
		// drop deprecated tags
		if tag == "created_by" {
			return
		}

		assert(!_constructed)
		_tags[tag] = value
	}

	func constructed() -> Bool {
		return _constructed
	}

	func setConstructed() {
		_constructed = true
		modifyCount = 0
	}

	static let _rfc3339DateFormatter: DateFormatter = {
		let format = DateFormatter()
		format.locale = NSLocale(localeIdentifier: "en_US_POSIX") as Locale
		format.dateFormat = "yyyy'-'MM'-'dd'T'HH':'mm':'ss'Z'"
		format.timeZone = NSTimeZone(forSecondsFromGMT: 0) as TimeZone
		return format
	}()

	static func rfc3339DateFormatter() -> DateFormatter {
		return _rfc3339DateFormatter
	}

	func dateForTimestamp() -> Date {
		if let date = OsmBaseObject.rfc3339DateFormatter().date(from: timestamp) {
			return date
		}
		fatalError()
	}

	func setTimestamp(_ date: Date, undo: MyUndoManager?) {
		if _constructed {
			undo?.registerUndo(withTarget: self, selector: #selector(setTimestamp(_:undo:)), objects: [dateForTimestamp(), undo!])
		}
		timestamp = OsmBaseObject.rfc3339DateFormatter().string(from: date)
	}

	func clearCachedProperties() {
		renderInfo = nil
		renderPriorityCached = 0
		_isOneWay = nil
		isShown = ._UNKNOWN
		_boundingBox = nil

		for layer in shapeLayers ?? [] {
			layer.removeFromSuperlayer()
		}
		shapeLayers = nil
	}

	func isModified() -> Bool {
		return modifyCount > 0
	}

	func incrementModifyCount(_ undo: MyUndoManager?) {
		assert(modifyCount >= 0)
		if _constructed {
			assert(undo != nil)
			// [undo registerUndoWithTarget:self selector:@selector(incrementModifyCount:) objects:@[undo]];
		}
		if undo?.isUndoing ?? false {
			modifyCount -= 1
		} else {
			modifyCount += 1
		}
		assert(modifyCount >= 0)

		// update cached values
		clearCachedProperties()
	}

	func resetModifyCount(_ undo: MyUndoManager) {
		modifyCount = 0

		clearCachedProperties()
	}

	func serverUpdateVersion(_ version: Int) {
		self.version = version
	}

	func serverUpdateChangeset(_ changeset: OsmIdentifier) {
		self.changeset = changeset
	}

	func serverUpdateIdent(_ ident: OsmIdentifier) {
		assert(self.ident < 0 && ident > 0)
		self.ident = ident
	}

	func serverUpdate(inPlace newerVersion: OsmBaseObject) {
		assert(ident == newerVersion.ident)
		assert(version < newerVersion.version)
		_tags = newerVersion.tags
		user = newerVersion.user
		timestamp = newerVersion.timestamp
		version = newerVersion.version
		changeset = newerVersion.changeset
		uid = newerVersion.uid
		// derived data
		clearCachedProperties()
	}

	func setDeleted(_ deleted: Bool, undo: MyUndoManager?) {
		if _constructed {
			assert(undo != nil)
			incrementModifyCount(undo)
			undo!.registerUndo(withTarget: self, selector: #selector(setDeleted(_:undo:)), objects: [NSNumber(value: self.deleted), undo!])
		}
		_deleted = deleted
	}

	func setTags(_ tags: [String: String], undo: MyUndoManager?) {
		if _constructed {
			assert(undo != nil)
			incrementModifyCount(undo!)
			undo!.registerUndo(withTarget: self, selector: #selector(setTags(_:undo:)), objects: [self.tags, undo!])
		}
		_tags = tags
		clearCachedProperties()
	}

	// get all keys that contain another part, like "restriction:conditional"
	func extendedKeys(forKey key: String) -> [String] {
		return tags.keys.filter {
			$0.hasPrefix(key) && $0.dropFirst(key.count).first == ":"
		}
	}

	func nodeSet() -> Set<OsmNode> {
		fatalError()
	}

	func overlapsBox(_ box: OSMRect) -> Bool {
		return boundingBox.intersectsRect(box)
	}

	private enum Uses: Int {
		case name = 1
		case ref = 2
	}

	private static let givenNameHighwayTypes: [String: Uses] = [
		"motorway": .ref,
		"trunk": .ref,
		"primary": .ref,
		"secondary": .ref,
		"tertiary": .ref,
		"unclassified": .name,
		"residential": .name,
		"road": .name,
		"living_street": .name
	]
	func givenName() -> String? {
		if let name = tags["name"] {
			return name
		}
		if isWay() != nil,
		   let highway = tags["highway"],
		   let uses = OsmBaseObject.givenNameHighwayTypes[highway],
		   uses == .ref,
		   let name = tags["ref"]
		{
			return name
		}
		return tags["brand"]
	}

	func friendlyDescription(withDetails details: Bool) -> String {
		if let name = givenName() {
			return name
		}

		if let feature = PresetsDatabase.shared.matchObjectTagsToFeature(tags,
		                                                                 geometry: geometryName(),
		                                                                 includeNSI: true)
		{
			let isGeneric = (feature.featureID == "point") || (feature.featureID == "line") || (feature.featureID == "area")
			if !isGeneric {
				return feature.friendlyName()
			}
		}

		if isRelation() != nil {
			var restriction = tags["restriction"]
			if restriction == nil {
				let a = extendedKeys(forKey: "restriction")
				if let key = a.last {
					restriction = tags[key]
				}
			}
			if let restriction = restriction {
				if restriction.hasPrefix("no_left_turn") {
					return NSLocalizedString("No Left Turn restriction", comment: "")
				}
				if restriction.hasPrefix("no_right_turn") {
					return NSLocalizedString("No Right Turn restriction", comment: "")
				}
				if restriction.hasPrefix("no_straight_on") {
					return NSLocalizedString("No Straight On restriction", comment: "")
				}
				if restriction.hasPrefix("only_left_turn") {
					return NSLocalizedString("Only Left Turn restriction", comment: "")
				}
				if restriction.hasPrefix("only_right_turn") {
					return NSLocalizedString("Only Right Turn restriction", comment: "")
				}
				if restriction.hasPrefix("only_straight_on") {
					return NSLocalizedString("Only Straight On restriction", comment: "")
				}
				if restriction.hasPrefix("no_u_turn") {
					return NSLocalizedString("No U-Turn restriction", comment: "")
				}
				return String.localizedStringWithFormat(NSLocalizedString("Restriction: %@", comment: ""), restriction)
			} else {
				let type = tags["type"] ?? "<>"
				return String.localizedStringWithFormat(NSLocalizedString("Relation: %@", comment: ""), type)
			}
		}

		// look for a feature key
		let featureKeys = PresetsDatabase.shared.allFeatureKeys()
		for (key, value) in tags {
			if featureKeys.contains(key) {
				return "\(key) = \(value)"
			}
		}

		// any non-ignored key
		for (key, value) in tags {
			if OsmTags.IsInterestingKey(key) {
				return "\(key) = \(value)"
			}
		}

		if let node = isNode() {
			if node.wayCount > 0 {
				return details
					? String.localizedStringWithFormat(NSLocalizedString("node %@ (in way)", comment: ""), ident)
					: NSLocalizedString("(node in way)", comment: "")
			}
			return details
				? String.localizedStringWithFormat(NSLocalizedString("node %@", comment: ""), ident)
				: NSLocalizedString("(node)", comment: "")
		}

		if isWay() != nil {
			return details
				? String.localizedStringWithFormat(NSLocalizedString("way %@", comment: ""), ident)
				: NSLocalizedString("(way)", comment: "")
		}

		if isRelation() != nil {
			if let type = tags["type"] {
				if let name = tags[type] {
					return "\(type) (\(name))"
				} else {
					return String.localizedStringWithFormat(NSLocalizedString("%@ (relation)", comment: ""), type)
				}
			}
			return String.localizedStringWithFormat(NSLocalizedString("(relation %@)", comment: ""), ident)
		}
		return NSLocalizedString("other object", comment: "")
	}

	func friendlyDescription() -> String {
		return friendlyDescription(withDetails: false)
	}

	func friendlyDescriptionWithDetails() -> String {
		return friendlyDescription(withDetails: true)
	}

	func copy(with zone: NSZone? = nil) -> Any {
		return self
	}

	func addParentRelation(_ parentRelation: OsmRelation, undo: MyUndoManager?) {
		if parentRelations.contains(parentRelation) {
			return
		}
		if _constructed, undo != nil {
			undo!.registerUndo(withTarget: self, selector: #selector(removeParentRelation(_:undo:)), objects: [parentRelation, undo!])
		}
		parentRelations.append(parentRelation)
	}

	func removeParentRelation(_ parentRelation: OsmRelation, undo: MyUndoManager?) {
		if _constructed, undo != nil {
			undo!.registerUndo(withTarget: self, selector: #selector(addParentRelation(_:undo:)), objects: [parentRelation, undo!])
		}
		guard let index = parentRelations.firstIndex(of: parentRelation) else {
			DLog("missing relation")
			return
		}
		parentRelations.remove(at: index)
	}

	func geometryName() -> String {
		if let way = isWay() {
			if way.isArea() {
				return GEOMETRY_AREA
			} else {
				return GEOMETRY_WAY
			}
		} else if let node = isNode() {
			if node.wayCount > 0 {
				return GEOMETRY_VERTEX
			} else {
				return GEOMETRY_NODE
			}
		} else if let relation = isRelation() {
			if relation.isMultipolygon() {
				return GEOMETRY_AREA
			} else {
				return GEOMETRY_WAY
			}
		}
		return ""
	}
}
