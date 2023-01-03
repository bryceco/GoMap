//
//  OsmMember.swift
//  Go Map!!
//
//  Created by Wolfgang Timme on 1/18/20.
//  Copyright © 2020 Bryce Cogswell. All rights reserved.
//

final class OsmMember: NSObject, NSSecureCoding {
	static let supportsSecureCoding: Bool = true

	let ref: OsmIdentifier
	private(set) var type: OSM_TYPE // way, node, or relation
	private(set) var obj: OsmBaseObject?
	private(set) var role: String?

	override var description: String {
		return "\(super.description) role=\(role ?? ""); type=\(type); ref=\(ref);"
	}

	init(type: OSM_TYPE, ref: OsmIdentifier, role: String?) {
		self.type = type
		self.ref = ref
		obj = nil
		self.role = role
		super.init()
	}

	init(obj: OsmBaseObject, role: String?) {
		self.obj = obj
		ref = obj.ident
		self.role = role
		if obj.isNode() != nil {
			type = .NODE
		} else if obj.isWay() != nil {
			type = .WAY
		} else if obj.isRelation() != nil {
			type = .RELATION
		} else {
			fatalError()
		}
		super.init()
	}

	func deresolveRef() {
		obj = nil
	}

	func resolveRef(to object: OsmBaseObject) {
		precondition(ref == object.ident)
		obj = object
	}

	func isNode() -> Bool {
		return type == .NODE
	}

	func isWay() -> Bool {
		return type == .WAY
	}

	func isRelation() -> Bool {
		return type == .RELATION
	}

	func encode(with coder: NSCoder) {
		coder.encode(type.string, forKey: "type")
		coder.encode(NSNumber(value: ref), forKey: "ref")
		coder.encode(role, forKey: "role")
	}

	required init?(coder: NSCoder) {
		guard let type2 = coder.decodeObject(forKey: "type") as? String,
		      let type = try? OSM_TYPE(string: type2)
		else {
			return nil
		}
		self.type = type
		guard let ref2 = coder.decodeObject(forKey: "ref")
		else { fatalError("OsmMember ref is nil") }
		if let ref2 = ref2 as? NSNumber {
			// normal path
			ref = ref2.int64Value
		} else if let ref2 = ref2 as? OsmBaseObject {
			// shouldn't happen but seems to when upgrading from old obj-c versions
			ref = ref2.ident
		} else {
			// shouldn't happen
			fatalError("OsmMember ref is not NSNumber: \(Swift.type(of: ref2))")
		}
		role = coder.decodeObject(forKey: "role") as? String
		obj = nil
		super.init()
	}
}
