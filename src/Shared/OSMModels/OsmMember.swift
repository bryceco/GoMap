//
//  OsmMember.swift
//  Go Map!!
//
//  Created by Wolfgang Timme on 1/18/20.
//  Copyright © 2020 Bryce. All rights reserved.
//

@objcMembers
class OsmMember: NSObject, NSCoding {

	let ref: OsmIdentifier
	private(set) var type: String?	// way, node, or relation: to help identify ref
	private(set) var obj: OsmBaseObject?
	private(set) var role: String?

    override var description: String {
		return "\(super.description) role=\(role ?? ""); type=\(type ?? ""); ref=\(ref);"
    }

    init(type: String?, ref: OsmIdentifier, role: String?) {
        self.type = type
        self.ref = ref
		self.obj = nil
		self.role = role
		super.init()
    }

	init(obj: OsmBaseObject, role: String?) {
		self.obj = obj
		self.ref = obj.ident
		self.role = role
        if obj.isNode() != nil {
			type = "node"
        } else if obj.isWay() != nil {
            type = "way"
        } else if obj.isRelation() != nil {
			type = "relation"
        } else {
            type = nil
        }
		super.init()
    }

	func resolveRef(to object: OsmBaseObject) {
		assert( self.ref == object.ident )
		obj = object
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
		coder.encode(type, forKey: "type")
		coder.encode(ref, forKey: "ref")
		coder.encode(role, forKey: "role")
    }

    required init?(coder: NSCoder) {
        type = coder.decodeObject(forKey: "type") as? String
        ref = coder.decodeInt64(forKey: "ref")
        role = coder.decodeObject(forKey: "role") as? String
		obj = nil
		super.init()
    }
}
