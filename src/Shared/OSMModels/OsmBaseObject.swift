//  Converted to Swift 5.4 by Swiftify v5.4.27034 - https://swiftify.com/
//
//  OsmBaseObject.swift
//  Go Map!!
//
//  Created by Wolfgang Timme on 1/18/20.
//  Copyright © 2020 Bryce. All rights reserved.
//

import Foundation

enum OSM_TYPE : Int {
    case _NODE = 1
    case _WAY = 2
    case _RELATION = 3
}

enum ONEWAY : Int {
    case _BACKWARD = -1
    case _NONE = 0
    case _FORWARD = 1
}

enum TRISTATE : Int {
    case _UNKNOWN
    case _YES
    case _NO
}

class OsmBaseObject: NSObject, NSCoding, NSCopying {
    func encode(with coder: NSCoder) {
        <#code#>
    }
    
    required init?(coder: NSCoder) {
        <#code#>
    }
    
    func copy(with zone: NSZone? = nil) -> Any {
        <#code#>
    }
    
    
    let PATH_SCALING = 0.0
    let GEOMETRY_AREA = "area"
    let GEOMETRY_WAY = "line"
    let GEOMETRY_NODE = "point"
    let GEOMETRY_VERTEX = "vertex"
    var _constructed = false
    var _nextUnusedIdentifier = 0
    public var renderPriorityCached = 0
    private var _deleted = false
    var deleted: Bool {
        return _deleted
    }
    var renderInfo: RenderInfo?
    private(set) var modifyCount: Int32 = 0
    private(set) var parentRelations: [AnyHashable]?
    
    func IsInterestingKey(_ key: String) -> Bool {
        if key == "attribution" {
            return false
        }
        if key == "created_by" {
            return false
        }
        if key == "source" {
            return false
        }
        if key == "odbl" {
            return false
        }
        if key.hasPrefix("tiger:") {
            return false
        }
        if key.hasPrefix("source:") {
            return false
        }
        if key.hasPrefix("source_ref") {
            return false
        }

        if OsmMapData.tagsToAutomaticallyStrip.contains(key) {
            return false
        }

        return true
    }
    
    var extendedIdentifier: OsmIdentifier {
        let type = extendedType
        return ident | type.rawValue << 62
    }
    
    var extendedType: OSM_TYPE! {
        return isNode() != nil ? ._NODE : isWay() != nil ? ._WAY : ._RELATION
    }
    // attributes
    
    private var _tags: [String : String]?
    var tags: [String : String]? {
        return _tags
    }
    private(set) var ident = 0
    private(set) var user: String?
    private(set) var timestamp: String?
    private(set) var version: Int32 = 0
    private(set) var changeset: OsmIdentifier?
    private(set) var uid: Int32 = 0
    private(set) var visible = false
    
    var isShown: TRISTATE!
    // extra stuff
    
    private var _boundingBox = OSMRect()
    var boundingBox: OSMRect {
        if _boundingBox.origin.x == 0 && _boundingBox.origin.y == 0 && _boundingBox.size.width == 0 && _boundingBox.size.height == 0 {
            computeBoundingBox()
        }
        return _boundingBox
    }
    var shapeLayers: [CALayer & LayerPropertiesProviding]?
    
    private var _isOneWay = ONEWAY(rawValue: 0)
    var isOneWay: ONEWAY? {
        return ONEWAY(rawValue: _isOneWay?.rawValue ?? 0)
    }
    
    override var description: String {
        var text = "id=\(ident) constructed=\(_constructed ? "Yes" : "No") deleted=\(deleted ? "Yes" : "No") modifyCount=\(modifyCount)"
        for (key, value) in tags ?? [:] {
            text += "\n  '\(key)' = '\(value)'"
        }
        return text
    }
    
    func hasInterestingTags() -> Bool {
        for (key, _) in tags ?? [:] {
            if IsInterestingKey(key) {
                return true
            }
        }
        return false
    }
    
    func isCoastline() -> Bool {
        let natural = tags?["natural"]
        if let natural = natural {
            if natural == "coastline" {
                return true
            }
            if natural == "water" {
                if isRelation() == nil && (parentRelations?.count ?? 0) == 0 {
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
    
    func computeBoundingBox() {
        assert(false)
        boundingBox = OSMRectMake(0, 0, 0, 0)
    }
    
    func distance(toLineSegment point1: OSMPoint, point point2: OSMPoint) -> Double {
        assert(false)
        return 1000000.0
    }
    
    func selectionPoint() -> OSMPoint {
        assert(false)
        return OSMPointMake(0, 0)
    }
    
    func pointOnObject(for target: OSMPoint) -> OSMPoint {
        assert(false)
        return OSMPointMake(0, 0)
    }
    
    func linePathForObject(withRefPoint refPoint: OSMPoint?) -> CGPath? {
        var refPoint = refPoint
        let wayList = isWay() != nil ? [self] : isRelation() != nil ? isRelation()?.waysInMultipolygon() : nil
        if wayList == nil {
            return nil
        }
        
        var path = CGMutablePath()
        var initial = OSMPoint(x: 0, y: 0)
        var haveInitial = false
        
        for way in wayList ?? [] {
            guard let way = way as? OsmWay else {
                continue
            }
            
            var first = true
            for node in way.nodes ?? [] {
                var pt = MapPointForLatitudeLongitude(node.lat, node.lon)
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
                    path.move(to: CGPoint(x: pt.x, y: pt.y), transform: .identity)
                    first = false
                } else {
                    path.addLine(to: CGPoint(x: pt.x, y: pt.y), transform: .identity)
                }
            }
        }
        
        if refPoint != nil && haveInitial {
            // place refPoint at upper-left corner of bounding box so it can be the origin for the frame/anchorPoint
            let bbox = path.boundingBoxOfPath
            if !bbox.origin.x.isInfinite {
                var tran = CGAffineTransform(translationX: -bbox.origin.x, y: -bbox.origin.y)
                let path2 = path.copy(using: &tran) as? CGMutablePath
                if let path2 = path2 {
                    path = path2
                }
                refPoint = OSMPointMake(initial.x + Double(bbox.origin.x) / PATH_SCALING, initial.y + Double(bbox.origin.y) / PATH_SCALING)
            } else {
#if DEBUG
                    DLog("bad path: \(self)")
#endif
            }
        }
        return path
    }
    
    // suitable for drawing polygon areas with holes, etc.
    func shapePathForObject(withRefPoint pRefPoint: OSMPoint?) -> CGPath? {
        assert(false)
        return nil
    }
    
    func nextUnusedIdentifier() -> Int {
        if _nextUnusedIdentifier == 0 {
            _nextUnusedIdentifier = UserDefaults.standard.integer(forKey: "nextUnusedIdentifier")
        }
        _nextUnusedIdentifier -= 1
        UserDefaults.standard.set(_nextUnusedIdentifier, forKey: "nextUnusedIdentifier")
        return _nextUnusedIdentifier
    }
    
    func MergeTags(_ ourTags: [String : String]?, _ otherTags: [String : String]?, _ allowConflicts: Bool) -> [String : String]? {
        if (ourTags?.count) == 0 {
            return otherTags
        }

        var merged = ourTags
        for (otherKey, otherValue) in otherTags ?? [:] {
            let ourValue = merged?[otherKey]
            if ourValue == nil || allowConflicts {
                merged?[otherKey ] = otherValue
            } else if ourValue == otherValue {
                // we already have it but replacement is the same
            } else if IsInterestingKey(otherKey) {
                break // conflict
                merged = nil
            } else {
                // we don't allow conflicts, but its not an interesting key/value so just ignore the conflict
            }
        }
        
        if merged == nil {
            return nil // conflict
        }
        return merged
    }
    
    // MARK: Construction
    
    func constructBaseAttributes(withVersion version: Int32, changeset: Int64, user: String, uid: Int32, ident: Int64, timestamp timestmap: String) {
        assert(!_constructed)
        self.version = version
        self.changeset = changeset
        self.user = user
        self.uid = uid
        visible = true
        self.ident = Int(ident)
        timestamp = timestmap
    }
    
    func constructBaseAttributes(fromXmlDict attributeDict: [String : Any]) {
        let version = (attributeDict["version"] as? NSNumber)?.int32Value ?? 0
        let changeset = (attributeDict["changeset"] as? NSNumber)?.int64Value ?? 0
        let user = attributeDict["user"] as? String ?? ""
        let uid = (attributeDict["uid"] as? NSNumber)?.int32Value ?? 0
        let ident = (attributeDict["id"] as? NSNumber)?.int64Value ?? 0
        let timestamp = attributeDict["timestamp"] as? String ?? ""
        
        constructBaseAttributes(withVersion: version, changeset: changeset, user: user, uid: uid, ident: ident, timestamp: timestamp)
    }

    func constructTag(_ tag: String, value: String) {
        // drop deprecated tags
        if tag == "created_by" {
            return
        }
        
        assert(!_constructed)
        if tags == nil {
            tags = [tag: value]
        } else {
            tags?[tag] = value
        }
    }

    func constructed() -> Bool {
        return _constructed
    }
    
    func setConstructed() {
        if user == nil {
            user = "" // some old objects don't have users attached to them
        }
        _constructed = true
        modifyCount = 0
    }
    
    static var rfc3339DateFormatter: DateFormatter? = nil
    
    class func rfc3339DateFormatter() -> DateFormatter? {
        if rfc3339DateFormatter == nil {
            rfc3339DateFormatter = DateFormatter()
            assert(rfc3339DateFormatter != nil)
            let enUSPOSIXLocale = NSLocale(localeIdentifier: "en_US_POSIX")
            assert(enUSPOSIXLocale != nil)
            rfc3339DateFormatter?.locale = enUSPOSIXLocale as Locale
            rfc3339DateFormatter?.dateFormat = "yyyy'-'MM'-'dd'T'HH':'mm':'ss'Z'"
            rfc3339DateFormatter?.timeZone = NSTimeZone(forSecondsFromGMT: 0) as TimeZone
        }
        return rfc3339DateFormatter
    }
    
    func dateForTimestamp() -> Date? {
        let date = OsmBaseObject.rfc3339DateFormatter()?.date(from: timestamp ?? "")
        assert(date)
        return date
    }
    
    @objc func setTimestamp(_ date: Date?, undo: UndoManager?) {
        if _constructed {
            assert(undo)
            undo?.registerUndo(withTarget: self, selector: #selector(setTimestamp(_:undo:)), objects: [dateForTimestamp(), undo])
        }
        if let date = date {
            timestamp = OsmBaseObject.rfc3339DateFormatter()?.string(from: date)
        }
        assert(timestamp)
    }
    
    func clearCachedProperties() {
        renderInfo = nil
        renderPriorityCached = 0
        isOneWay = nil
        isShown = ._UNKNOWN
        boundingBox = OSMRectZero()
        
        for layer in shapeLayers ?? [] {
            guard let layer = layer as? CALayer else {
                continue
            }
            layer.removeFromSuperlayer()
        }
        shapeLayers = nil
    }
    
    func isModified() -> Bool {
        return modifyCount > 0
    }
    
    func incrementModifyCount(_ undo: UndoManager?) {
        assert(modifyCount >= 0)
        if _constructed {
            assert(undo)
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
    
    func resetModifyCount(_ undo: UndoManager?) {
        assert(undo)
        modifyCount = 0
        
        clearCachedProperties()
    }
    
    func serverUpdateVersion(_ version: Int) {
        self.version = Int32(version)
    }
    
    func serverUpdateChangeset(_ changeset: OsmIdentifier) {
        self.changeset = changeset
    }
    
    func serverUpdateIdent(_ ident: OsmIdentifier) {
        assert(self.ident.int64Value < 0 && Int(ident) > 0)
        self.ident = NSNumber(value: ident)
    }
    
    func serverUpdate(inPlace newerVersion: OsmBaseObject?) {
        assert((ident == newerVersion?.ident))
        assert(version() < (newerVersion?.version() ?? 0))
        tags = newerVersion?.tags
        user = newerVersion?.user
        timestamp = newerVersion?.timestamp
        version = newerVersion?.version() ?? 0
        changeset = newerVersion?.changeset
        uid = newerVersion?.uid ?? 0
        // derived data
        clearCachedProperties()
    }
    
    @objc func setDeleted(_ deleted: Bool, undo: UndoManager?) {
        if _constructed {
            assert(undo)
            incrementModifyCount(undo)
            undo?.registerUndo(withTarget: self, selector: #selector(setDeleted(_:undo:)), objects: [NSNumber(value: self.deleted), undo])
        }
        self.deleted = deleted
    }
    
    @objc func setTags(_ tags: [String : String]?, undo: UndoManager?) {
        if _constructed {
            assert(undo)
            incrementModifyCount(undo)
            undo?.registerUndo(withTarget: self, selector: #selector(setTags(_:undo:)), objects: [self.tags ?? NSNull(), undo])
        }
        self.tags = tags
        clearCachedProperties()
    }
    
    // get all keys that contain another part, like "restriction:conditional"
    func extendedKeys(forKey key: String?) -> [AnyHashable]? {
        var keys: [AnyHashable]? = nil
        for tag in tags ?? [:] {
            if tag.hasPrefix(key ?? "") && tag[tag.index(tag.startIndex, offsetBy: UInt((key?.count ?? 0)))] == ":" {
                if keys == nil {
                    keys = [tag]
                } else {
                    if let keys = keys {
                        keys = keys + [tag]
                    }
                }
            }
        }
        return keys
    }
    
    func nodeSet() -> Set<AnyHashable>? {
        assert(false)
        return nil
    }
    
    func overlapsBox(_ box: OSMRect) -> Bool {
        return OSMRectIntersectsRect(boundingBox(), box)
    }
    
    static var givenNameHighwayTypes: [AnyHashable : Any]? = nil
    
    func givenName() -> String? {
        enum Uses : Int {
            case name = 1
            case ref = 2
        }
        
        if OsmBaseObject.givenNameHighwayTypes == nil {
            OsmBaseObject.givenNameHighwayTypes = [
                "motorway": NSNumber(value: Uses.ref.rawValue),
                "trunk": NSNumber(value: Uses.ref.rawValue),
                "primary": NSNumber(value: Uses.ref.rawValue),
                "secondary": NSNumber(value: Uses.ref.rawValue),
                "tertiary": NSNumber(value: Uses.ref.rawValue),
                "unclassified": NSNumber(value: Uses.name.rawValue),
                "residential": NSNumber(value: Uses.name.rawValue),
                "road": NSNumber(value: Uses.name.rawValue),
                "living_street": NSNumber(value: Uses.name.rawValue)
            ]
        }
        
        
        var name = tags?["name"]
        if (name?.count ?? 0) != 0 {
            return name
        }
        
        if isWay() != nil {
            let highway = tags?["highway"]
            if let highway = highway {
                let uses = OsmBaseObject.givenNameHighwayTypes[highway].intValue
                if uses & Uses.ref.rawValue != 0 {
                    name = tags?["ref"]
                    if (name?.count ?? 0) != 0 {
                        return name
                    }
                }
            }
        }
        
        return tags?["brand"]
    }
    
    func friendlyDescription(withDetails details: Bool) -> String? {
        var name = givenName()
        if (name?.count ?? 0) != 0 {
            return name
        }
        
        let feature = PresetsDatabase.shared.matchObjectTags(
            toFeature: tags,
            geometry: geometryName(),
            includeNSI: true)
        if let feature = feature {
            let isGeneric = (feature.featureID == "point") || (feature.featureID == "line") || (feature.featureID == "area")
            if !isGeneric {
                name = feature.friendlyName
                if (name?.count ?? 0) > 0 {
                    return name
                }
            }
        }
        
        if isRelation() != nil {
            var restriction = tags?["restriction"]
            if restriction == nil {
                let a = extendedKeys(forKey: "restriction")
                if (a?.count ?? 0) != 0 {
                    let key = a?.last as? String
                    restriction = tags?[key ?? ""]
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
                return String.localizedStringWithFormat(NSLocalizedString("Relation: %@", comment: ""), tags?["type"] ?? "")
            }
        }
        
        if DEBUG {
            let indoor = tags?["indoor"]
            if let indoor = indoor {
                var text = "Indoor \(indoor)"
                let level = tags?["level"]
                if let level = level {
                    text = text + ", level \(level)"
                }
                return text
            }
        }
        
        var tagDescription: String? = nil
        let featureKeys = PresetsDatabase.shared.allFeatureKeys()
        // look for a feature key
        (tags as NSDictionary?)?.enumerateKeysAndObjects({ key, value, stop in
            if featureKeys.contains(key ?? "") {
                stop = UnsafeMutablePointer<ObjCBool>(mutating: &true)
                tagDescription = "\(key ?? "") = \(value ?? "")"
            }
        })
        if tagDescription == nil {
            // any non-ignored key
            (tags as NSDictionary?)?.enumerateKeysAndObjects({ key, value, stop in
                if IsInterestingKey(key) {
                    stop = UnsafeMutablePointer<ObjCBool>(mutating: &true)
                    tagDescription = "\(key ?? "") = \(value ?? "")"
                }
            })
        }
        if let tagDescription = tagDescription {
            return tagDescription
        }
        
        if isNode() != nil && (isNode()?.wayCount ?? 0) > 0 {
            return details
                ? String.localizedStringWithFormat(NSLocalizedString("node %@ (in way)", comment: ""), ident)
                : NSLocalizedString("(node in way)", comment: "")
        }
        
        if isNode() != nil {
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
            let relation = isRelation()
            let type = relation?.tags?["type"]
            if (type?.count ?? 0) != 0 {
                name = relation?.tags?[type ?? ""]
                if (name?.count ?? 0) != 0 {
                    return "\(type ?? "") (\(name ?? ""))"
                } else {
                    return String.localizedStringWithFormat(NSLocalizedString("%@ (relation)", comment: ""), type ?? "")
                }
            }
            return String.localizedStringWithFormat(NSLocalizedString("(relation %@)", comment: ""), ident)
        }
        
        return NSLocalizedString("other object", comment: "")
    }
    
    func friendlyDescription() -> String? {
        return friendlyDescription(withDetails: false)
    }
    
    func friendlyDescriptionWithDetails() -> String? {
        return friendlyDescription(withDetails: true)
    }
    
    func copy(with zone: NSZone? = nil) -> Any {
        return self
    }
    
    func encode(with coder: NSCoder) {
        coder.encode(ident, forKey: "ident")
        coder.encode(user, forKey: "user")
        coder.encode(timestamp, forKey: "timestamp")
        coder.encode(Int(version), forKey: "version")
        coder.encode(Int(changeset ?? 0), forKey: "changeset")
        coder.encode(Int(uid), forKey: "uid")
        coder.encode(visible, forKey: "visible")
        coder.encode(tags, forKey: "tags")
        coder.encode(deleted, forKey: "deleted")
        coder.encode(modifyCount, forKey: "modified")
    }
    
    required init?(coder: NSCoder) {
        super.init()
        if let decode = coder.decodeObject(forKey: "ident") as? NSNumber {
            ident = decode
        }
        user = coder.decodeObject(forKey: "user") as? String
        timestamp = coder.decodeObject(forKey: "timestamp") as? String
        version = coder.decodeInt32(forKey: "version")
        changeset = coder.decodeInteger(forKey: "changeset")
        uid = coder.decodeInt32(forKey: "uid")
        visible = coder.decodeBool(forKey: "visible")
        tags = coder.decodeObject(forKey: "tags") as? [String : String]
        deleted = coder.decodeBool(forKey: "deleted")
        modifyCount = coder.decodeInt32(forKey: "modified")
    }
    
    override init() {
        super.init()
    }
    
    func construct(asUserCreated userName: String?) {
        // newly created by user
        assert(!_constructed)
        ident = NSNumber(value: OsmBaseObject.nextUnusedIdentifier())
        visible = true
        user = userName ?? ""
        version = 1
        changeset = nil
        uid = 0
        deleted = true
        setTimestamp(Date(), undo: nil)
    }
    
    @objc func addParentRelation(_ parentRelation: OsmRelation?, undo: UndoManager?) {
        if _constructed && undo != nil {
            undo?.registerUndo(withTarget: self, selector: #selector(removeParentRelation(_:undo:)), objects: [parentRelation, undo])
        }
        
        if parentRelations != nil {
            if let parentRelation = parentRelation {
                if !(parentRelations?.contains(parentRelation) ?? false) {
                    if let parentRelations = parentRelations {
                        parentRelations = parentRelations + [parentRelation]
                    }
                }
            }
        } else {
            parentRelations = [parentRelation].compactMap { $0 }
        }
    }
    
    @objc func removeParentRelation(_ parentRelation: OsmRelation?, undo: UndoManager?) {
        if _constructed && undo != nil {
            undo?.registerUndo(withTarget: self, selector: #selector(addParentRelation(_:undo:)), objects: [parentRelation, undo])
        }
        var index: Int? = nil
        if let parentRelation = parentRelation {
            index = parentRelations?.firstIndex(of: parentRelation) ?? NSNotFound
        }
        if index == NSNotFound {
            DLog("missing relation")
            return
        }
        if (parentRelations?.count ?? 0) == 1 {
            parentRelations = nil
        } else {
            var a = parentRelations
            a?.remove(at: index ?? 0)
            if let a = a {
                parentRelations = a
            }
        }
    }
    
    func geometryName() -> String? {
        if isWay() != nil {
            if isWay()?.isArea() ?? false {
                return GEOMETRY_AREA
            } else {
                return GEOMETRY_WAY
            }
        } else if isNode() != nil {
            if (isNode()?.wayCount ?? 0) > 0 {
                return GEOMETRY_VERTEX
            } else {
                return GEOMETRY_NODE
            }
        } else if isRelation() != nil {
            if isRelation()?.isMultipolygon() ?? false {
                return GEOMETRY_AREA
            } else {
                return GEOMETRY_WAY
            }
        }
        return ""
    }
    
    class func extendedIdentifier(for type: OSM_TYPE, identifier: OsmIdentifier) -> OsmIdentifier {
        return (UInt64(identifier) & ((UInt64(1) << 62) - 1)) | (type.rawValue << 62)
    }
    
    class func decomposeExtendedIdentifier(_ extendedIdentifier: OsmIdentifier, type pType: OSM_TYPE?, ident pIdent: OsmIdentifier?) {
        var pType = pType
        var pIdent = pIdent
        pType = OSM_TYPE(rawValue: Int(extendedIdentifier) >> 62 & 3)
        var ident = Int64(UInt64(extendedIdentifier) & ((UInt64(1) << 62) - 1))
        ident = (ident << 2) >> 2 // sign extend
        pIdent = ident
    }
}
