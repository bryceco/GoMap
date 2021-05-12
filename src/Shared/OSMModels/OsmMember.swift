//  Converted to Swift 5.4 by Swiftify v5.4.27034 - https://swiftify.com/
//
//  OsmMember.swift
//  Go Map!!
//
//  Created by Wolfgang Timme on 1/18/20.
//  Copyright © 2020 Bryce. All rights reserved.
//

class OsmMember: NSObject, NSCoding {
 // way, node, or relation: to help identify ref



    private(set) var type: String?
    private(set) var ref: Any?
    private(set) var role: String?

    override var description: String {
        if let ref = ref {
            return "\(super.description) role=\(role ?? ""); type=\(type ?? "");ref=\(ref);"
        }
        return nil
    }

    init(type: String?, ref: NSNumber?, role: String?) {
        super.init()
        self.type = type
        self.ref = ref
        self.role = role
    }

    init(ref: OsmBaseObject?, role: String?) {
        super.init()
        self.ref = ref
        self.role = role
        if ref?.isNode() != nil {
            type = "node"
        } else if ref?.isWay() != nil {
            type = "way"
        } else if ref?.isRelation() != nil {
            type = "relation"
        } else {
            type = nil
        }
    }

    func resolveRef(to object: OsmBaseObject?) {
        assert((ref is NSNumber) || (ref is OsmBaseObject))
        assert((object is NSNumber) || (object?.isNode() != nil && isNode()) || (object?.isWay() != nil && isWay()) || (object?.isRelation() != nil && isRelation()))
        ref = object
    }

    func isNode() -> Bool {
        return type == "node"
    }

    func isWay() -> Bool {
        return type == "way"
    }

    func isRelation() -> Bool {
        return type == "relation"
    }

    func encode(with coder: NSCoder) {
        let o = self.ref as? OsmBaseObject
        let ref = (self.ref is OsmBaseObject) ? o?.ident : (self.ref as? NSNumber)
        coder.encode(type, forKey: "type")
        coder.encode(ref, forKey: "ref")
        coder.encode(role, forKey: "role")
    }

    required init?(coder: NSCoder) {
        super.init()
        type = coder.decodeObject(forKey: "type") as? String
        ref = coder.decodeObject(forKey: "ref")
        role = coder.decodeObject(forKey: "role") as? String
    }
}