//  Converted to Swift 5.4 by Swiftify v5.4.27034 - https://swiftify.com/
//
//  OsmRelation.swift
//  Go Map!!
//
//  Created by Wolfgang Timme on 1/18/20.
//  Copyright © 2020 Bryce. All rights reserved.
//


class OsmRelation: OsmBaseObject {
    private(set) var members: [OsmMember]?

    override var description: String {
        return "OsmRelation \(super.description)"
    }

    func constructMember(_ member: OsmMember?) {
        assert(!constructed)
        if members == nil {
            members = [member].compactMap { $0 }
        } else {
            if let member = member {
                members?.append(member)
            }
        }
    }

    override func `is`() -> OsmRelation? {
        return self
    }

    func forAllMemberObjectsRecurse(_ callback: @escaping (OsmBaseObject?) -> Void, relations: inout Set<AnyHashable>) {
        for member in members ?? [] {
            let obj = member.ref as? OsmBaseObject
            if obj is OsmBaseObject {
                if obj?.isRelation() != nil {
                    if let obj = obj {
                        if relations.contains(obj) {
                            // skip
                        } else {
                            callback(obj)
                            relations.insert(obj)
                            obj?.isRelation()?.forAllMemberObjectsRecurse(callback, relations: &relations)
                        }
                    }
                } else {
                    callback(obj)
                }
            }
        }
    }

    func forAllMemberObjects(_ callback: @escaping (OsmBaseObject?) -> Void) {
        var relations = Set<AnyHashable>([self])
        forAllMemberObjectsRecurse(callback, relations: &relations)
    }

    func allMemberObjects() -> Set<AnyHashable>? {
        var objects = []
        forAllMemberObjects({ obj in
            objects.insert(obj)
        })
        return objects
    }

    func resolve(to mapData: OsmMapData?) -> Bool {
        var needsRedraw = false
        for member in members ?? [] {
            let ref = member.ref
            if !(ref is NSNumber) {
                // already resolved
                continue
            }

            if member.isWay() {
                let way = mapData?.way(forRef: ref)
                if let way = way {
                    member.resolveRef(to: way)
                    way.addParentRelation(self, undo: nil)
                    needsRedraw = true
                } else {
                    // way is not in current view
                }
            } else if member.isNode() {
                let node = mapData?.node(forRef: ref)
                if let node = node {
                    member.resolveRef(to: node)
                    node.addParentRelation(self, undo: nil)
                    needsRedraw = true
                } else {
                    // node is not in current view
                }
            } else if member.isRelation() {
                let rel = mapData?.relation(forRef: ref)
                if let rel = rel {
                    member.resolveRef(to: rel)
                    rel.addParentRelation(self, undo: nil)
                    needsRedraw = true
                } else {
                    // relation is not in current view
                }
            } else {
                assert(false)
            }
        }
        if needsRedraw {
            clearCachedProperties()
        }
        return needsRedraw
    }

    // convert references to objects back to NSNumber
    func deresolveRefs() {
        for member in members ?? [] {
            let ref = member.ref as? OsmBaseObject
            if ref is OsmBaseObject {
                ref?.removeParentRelation(self, undo: nil)
                member.resolveRef(to: ref?.ident as? OsmBaseObject)
            }
        }
    }

    @objc func assignMembers(_ members: [AnyHashable]?, undo: UndoManager?) {
        if constructed {
            assert(undo)
            incrementModifyCount(undo)
            undo?.registerUndo(withTarget: self, selector: #selector(assignMembers(_:undo:)), objects: [self.members, undo])
        }

        // figure out which members changed and update their relation parents
        if true {
        var old = []
        var new = []
        for m in self.members ?? [] {
            if m.ref is OsmBaseObject {
                old.insert(m.ref)
            }
        }
        for m in members ?? [] {
            guard let m = m as? OsmMember else {
                continue
            }
            if m.ref is OsmBaseObject {
                new.insert(m.ref)
            }
        }
        var common = new
        common.intersect(old)
        new.subtract(common) // added items
        old.subtract(common) // removed items
        for obj in old {
            guard let obj = obj as? OsmBaseObject else {
                continue
            }
            obj.removeParentRelation(self, undo: nil)
        }
        for obj in new {
            guard let obj = obj as? OsmBaseObject else {
                continue
            }
            obj.addParentRelation(self, undo: nil)
        }
        } else {
        let old = (self.members as NSArray?)?.sortedArray(comparator: { obj1, obj2 in
            let r1 = (obj1?.ref is OsmBaseObject) ? (obj1?.ref as? OsmBaseObject)?.ident : (obj1?.ref as? NSNumber)
            let r2 = (obj2?.ref is OsmBaseObject) ? (obj2?.ref as? OsmBaseObject)?.ident : (obj2?.ref as? NSNumber)
            if let r2 = r2 {
                return r1?.compare(r2) ?? ComparisonResult.orderedSame
            }
            return ComparisonResult.orderedSame
        })
        let new = (members as NSArray?)?.sortedArray(comparator: { obj1, obj2 in
            let r1 = (obj1?.ref is OsmBaseObject) ? (obj1?.ref as? OsmBaseObject)?.ident : (obj1?.ref as? NSNumber)
            let r2 = (obj2?.ref is OsmBaseObject) ? (obj2?.ref as? OsmBaseObject)?.ident : (obj2?.ref as? NSNumber)
            if let r2 = r2 {
                return r1?.compare(r2) ?? ComparisonResult.orderedSame
            }
            return ComparisonResult.orderedSame
        })
        }

        self.members = members as? [OsmMember]
    }

    @objc func removeMember(at index: Int, undo: UndoManager?) {
        assert(undo)
        let member = members?[index]
        incrementModifyCount(undo)
        undo?.registerUndo(withTarget: self, selector: #selector(add(_:at:undo:)), objects: [member, NSNumber(value: index), undo])
        members?.remove(at: index)
        let obj = member?.ref as? OsmBaseObject
        if obj is OsmBaseObject {
            obj?.removeParentRelation(self, undo: nil)
        }
    }

    @objc func add(_ member: OsmMember?, at index: Int, undo: UndoManager?) {
        if constructed {
            assert(undo)
            incrementModifyCount(undo)
            undo?.registerUndo(withTarget: self, selector: #selector(removeMember(at:undo:)), objects: [NSNumber(value: index), undo])
        }
        if members == nil {
            members = []
        }
        if let member = member {
            members?.insert(member, at: index)
        }
        let obj = member?.ref as? OsmBaseObject
        if obj is OsmBaseObject {
            obj?.addParentRelation(self, undo: nil)
        }
    }

    override func serverUpdate(inPlace newerVersion: OsmRelation?) {
        super.serverUpdate(inPlace: newerVersion)
        members = newerVersion?.members
    }

    override func computeBoundingBox() {
        var first = true
        var box = OSMRect(0, 0, 0, 0)
        let objects = allMemberObjects()
        for obj in objects ?? [] {
            guard let obj = obj as? OsmBaseObject else {
                continue
            }
            if obj.isRelation() != nil {
                continue // child members have already been added to the set
            }
            let rc = obj.boundingBox()
            if rc.origin.x == 0 && rc.origin.y == 0 && rc.size.height == 0 && rc.size.width == 0 {
                // skip
            } else if first {
                box = rc
                first = false
            } else {
                box = OSMRectUnion(box, rc)
            }
        }
        boundingBox = box
    }

    override func nodeSet() -> Set<AnyHashable>? {
        var set: Set<AnyHashable> = []
        for member in members ?? [] {
            if member.ref is NSNumber {
                continue // unresolved reference
            }

            if member.isNode() {
                let node = member.ref as? OsmNode
                set.insert(node)
            } else if member.isWay() {
                let way = member.ref as? OsmWay
                set.formUnion(Set(way?.nodes))
            } else if member.isRelation() {
                let relation = member.ref as? OsmRelation
                for node in relation?.nodeSet() ?? [] {
                    guard let node = node as? OsmNode else {
                        continue
                    }
                    set.insert(node)
                }
            } else {
                assert(false)
            }
        }
        return set
    }

    func member(byRole role: String?) -> OsmMember? {
        for member in members ?? [] {
            if member.role == role {
                return member
            }
        }
        return nil
    }

    func members(byRole role: String?) -> [AnyHashable]? {
        var a: [AnyHashable] = []
        for member in members ?? [] {
            if member.role == role {
                a.append(member)
            }
        }
        return a
    }

    func member(byRef ref: OsmBaseObject?) -> OsmMember? {
        for member in members ?? [] {
            if (member.ref as? OsmBaseObject) == ref {
                return member
            }
        }
        return nil
    }

    func isMultipolygon() -> Bool {
        let type = tags?["type"]
        return (type == "multipolygon") || (type == "building")
    }

    func isBoundary() -> Bool {
        return tags?["type"] == "boundary"
    }

    func isWaterway() -> Bool {
        return tags?["type"] == "waterway"
    }

    func isRoute() -> Bool {
        return tags?["type"] == "route"
    }

    func isRestriction() -> Bool {
        let type = tags?["type"]
        if let type = type {
            if type == "restriction" {
                return true
            }
            if type.hasPrefix("restriction:") {
                return true
            }
        }
        return false
    }

    func waysInMultipolygon() -> [AnyHashable]? {
        if !isMultipolygon() {
            return nil
        }
        var a = [AnyHashable](repeating: 0, count: members?.count ?? 0)
        for mem in members ?? [] {
            let role = mem.role
            if (role == "outer") || (role == "inner") {
                if mem.ref is OsmWay {
                    if let ref1 = mem.ref as? AnyHashable {
                        a.append(ref1)
                    }
                }
            }
        }
        return a
    }

    class func buildMultipolygon(fromMembers memberList: [AnyHashable]?, repairing: Bool, isComplete: UnsafeMutablePointer<ObjCBool>?) -> [AnyHashable]? {
        var isComplete = isComplete
        var loopList: [AnyHashable] = []
        var loop: [AnyHashable]? = nil
        var members = memberList
        members?.filter { NSPredicate(block: { member, bindings in
            return (member?.ref is OsmWay) && ((member?.role == "outer") || (member?.role == "inner"))
        }).evaluate(with: $0) }
        var isInner = false
        var foundAdjacent = false

        isComplete = UnsafeMutablePointer<ObjCBool>(mutating: (members?.count ?? 0) == (memberList?.count ?? 0))

        while (members?.count ?? 0) {
            if loop == nil {
                // add a member to loop
                let member = members?.last as? OsmMember
                members?.remove(at: (members?.count ?? 0) - 1)
                isInner = member?.role == "inner"
                let way = member?.ref as? OsmWay
                loop = way?.nodes
                foundAdjacent = true
            } else {
                // find adjacent way
                foundAdjacent = false
                for i in 0..<(members?.count ?? 0) {
                    let member = members?[i] as? OsmMember
                    if (member?.role == "inner") != isInner {
                        continue
                    }
                    let way = member?.ref as? OsmWay
                    let enumerator = way?.nodes?[0] == loop?.last
                        ? (way?.nodes as NSArray?)?.objectEnumerator()
                        : way?.nodes?.last == loop?.last
                            ? (way?.nodes as NSArray?)?.reverseObjectEnumerator()
                            : nil
                    if let enumerator = enumerator {
                        foundAdjacent = true
                        var first = true
                        for n in enumerator {
                            guard let n = n as? OsmNode else {
                                continue
                            }
                            if first {
                                first = false
                            } else {
                                loop?.append(n)
                            }
                        }
                        members?.remove(at: i)
                        break
                    }
                }
                if !foundAdjacent && repairing {
                    // invalid, but we'll try to continue
                    isComplete = UnsafeMutablePointer<ObjCBool>(mutating: &false)
                    if let aLoop = loop?[0] {
                        loop?.append(aLoop)
                    } // force-close the loop
                }
            }

            if (loop?.count ?? 0) != 0 && (loop?.last == loop?[0] || !foundAdjacent) {
                // finished a loop. Outer goes clockwise, inner goes counterclockwise
                let lp = OsmWay.isClockwiseArrayOfNodes(loop) == isInner ? ((loop as NSArray?)?.reverseObjectEnumerator().allObjects as? [AnyHashable]) : loop
                if let lp = lp {
                    loopList.append(lp)
                }
                loop = nil
            }
        }
        return loopList
    }

    func buildMultipolygonRepairing(_ repairing: Bool) -> [AnyHashable]? {
        if !isMultipolygon() {
            return nil
        }
        var isComplete = true
        let a = OsmRelation.buildMultipolygon(fromMembers: members, repairing: repairing, isComplete: UnsafeMutablePointer<ObjCBool>(mutating: &isComplete))
        return a
    }

    override func shapePathForObject(withRefPoint pRefPoint: OSMPoint?) -> CGPath? {
        var pRefPoint = pRefPoint
        let loopList = buildMultipolygonRepairing(true)
        if (loopList?.count ?? 0) == 0 {
            return nil
        }

        let path = CGMutablePath()
        var hasRefPoint = false
        var refPoint: OSMPoint

        for loop in loopList ?? [] {
            guard let loop = loop as? [AnyHashable] else {
                continue
            }
            var first = true
            for n in loop {
                guard let n = n as? OsmNode else {
                    continue
                }
                let pt = MapPointForLatitudeLongitude(n.lat, n.lon)
                if first {
                    first = false
                    if !hasRefPoint {
                        hasRefPoint = true
                        refPoint = pt
                    }
                    path.move(to: CGPoint(x: CGFloat((pt.x - refPoint.x) * PATH_SCALING), y: CGFloat((pt.y - refPoint.y) * PATH_SCALING)), transform: .identity)
                } else {
                    path.addLine(to: CGPoint(x: CGFloat((pt.x - refPoint.x) * PATH_SCALING), y: CGFloat((pt.y - refPoint.y) * PATH_SCALING)), transform: .identity)
                }
            }
        }
        pRefPoint = refPoint
        return path
    }

    func centerPoint() -> OSMPoint {
        var outerSet: [AnyHashable] = []
        for member in members ?? [] {
            if member.role == "outer" {
                let way = member.ref as? OsmWay
                if way is OsmWay {
                    if let way = way {
                        outerSet.append(way)
                    }
                }
            }
        }
        if outerSet.count == 1 {
            return outerSet[0].centerPoint()
        } else {
            let rc = boundingBox()
            return OSMPointMake(rc.origin.x + rc.size.width / 2, rc.origin.y + rc.size.height / 2)
        }
    }

    override func selectionPoint() -> OSMPoint {
        let bbox = boundingBox()
        let center = OSMPoint(bbox.origin.x + bbox.size.width / 2, bbox.origin.y + bbox.size.height / 2)
        if isMultipolygon() {
            // pick a point on an outer polygon that is close to the center of the bbox
            for member in members ?? [] {
                if member.role == "outer" {
                    let way = member.ref as? OsmWay
                    if (way is OsmWay) && (way?.nodes?.count ?? 0) > 0 {
                        return (way?.pointOnObject(for: center))!
                    }
                }
            }
        }
        if isRestriction() {
            // pick via node or way
            for member in members ?? [] {
                if member.role == "via" {
                    let object = member.ref as? OsmBaseObject
                    if object is OsmBaseObject {
                        if object?.isNode() != nil || object?.isWay() != nil {
                            return (object?.selectionPoint())!
                        }
                    }
                }
            }
        }
        // choose any node/way member
        let all = allMemberObjects() // might be a super relation, so need to recurse down
        let object = all?.first as? OsmBaseObject
        return (object?.selectionPoint())!
    }

    override func distance(toLineSegment point1: OSMPoint, point point2: OSMPoint) -> Double {
        var dist = 1000000.0
        for member in members ?? [] {
            let object = member.ref as? OsmBaseObject
            if object is OsmBaseObject {
                if object?.isRelation() == nil {
                    let d = object?.distance(toLineSegment: point1, point: point2) ?? 0.0
                    if d < dist {
                        dist = d
                    }
                }
            }
        }
        return dist
    }

    override func pointOnObject(for target: OSMPoint) -> OSMPoint {
        var bestPoint = target
        var bestDistance = 10000000.0
        for object in allMemberObjects() ?? [] {
            guard let object = object as? OsmBaseObject else {
                continue
            }
            let pt = object.pointOnObject(for: target)
            let dist = DistanceFromPointToPoint(target, pt)
            if dist < bestDistance {
                bestDistance = dist
                bestPoint = pt
            }
        }
        return bestPoint
    }

    func contains(_ object: OsmBaseObject?) -> Bool {
        let node = object?.isNode()
        let set = allMemberObjects()
        for obj in set ?? [] {
            guard let obj = obj as? OsmBaseObject else {
                continue
            }
            if obj == object {
                return true
            }
            if let object = object as? OsmNode {
                if node != nil && obj.isWay() != nil && obj.isWay()?.nodes?.contains(object) ?? false {
                    return true
                }
            }
        }
        return false
    }

    override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(members, forKey: "members")
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        members = coder.decodeObject(forKey: "members") as? [OsmMember]
        constructed = true
    }
}