//
//  UndoAction+Ext.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 6/1/26.
//  Copyright © 2026 Bryce Cogswell. All rights reserved.
//

extension UndoAction {
	/// All OSM objects referenced by this action — the target (if it is an OSM object)
	/// plus any OSM objects found directly in `objects` or as values inside a comment dict.
	func osmObjects() -> Set<OsmBaseObject> {
		var result: Set<OsmBaseObject> = []
		if let obj = target as? OsmBaseObject {
			result.insert(obj)
		}
		for obj in objects {
			if let osm = obj as? OsmBaseObject {
				result.insert(osm)
			} else if let dict = obj as? [String: Any] {
				result.formUnion(dict.values.compactMap { $0 as? OsmBaseObject })
			}
		}
		return result
	}

	private func describeObject(_ obj: Any) -> String {
		switch obj {
		case let node as OsmNode:
			return "node(\(node.ident))"
		case let way as OsmWay:
			return "way(\(way.ident))"
		case let relation as OsmRelation:
			return "relation(\(relation.ident))"
		case let dict as NSDictionary:
			if let comment = dict["comment"] as? String {
				return "\"\(comment)\""
			}
			return "Dictionary"
		case is NSData:
			return "Data"
		case let num as NSNumber where CFGetTypeID(num) == CFBooleanGetTypeID():
			return num.boolValue ? "true" : "false"
		case let num as NSNumber:
			return "\(num)"
		default:
			return String(describing: type(of: obj))
		}
	}

	@objc override public var description: String {
		let targetName = describeObject(target)
		let selectorParts = selector.split(separator: ":").map(String.init)
		let methodName = selectorParts.first ?? selector
		let args = objects.enumerated().map { index, obj in
			let desc = describeObject(obj)
			return index > 0 && index < selectorParts.count ? "\(selectorParts[index]): \(desc)" : desc
		}.joined(separator: ", ")
		return "UndoAction \(group): \(targetName).\(methodName)(\(args))"
	}
}
