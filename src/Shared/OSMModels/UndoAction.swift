//
//  UndoAction.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 9/13/26.
//  Copyright © 2026 Bryce Cogswell. All rights reserved.
//

import Foundation
import UIKit

// MARK: - UndoAction

/// Pairs an `OsmEditOperation` with its undo-group ID.
/// Implements `NSSecureCoding` so it can be archived as part of `OsmMapData`.
final class UndoAction: NSObject, NSSecureCoding {
	static var supportsSecureCoding: Bool { true }

	let type: OsmEditOperation
	var group: Int

	init(type: OsmEditOperation, group: Int = 0) {
		self.type = type
		self.group = group
	}

	// MARK: osmObjects (for upload grouping)

	/// All OSM objects directly referenced by this action, used to determine
	/// which undo groups share objects (for selective upload grouping).
	var osmObjects: Set<OsmBaseObject> {
		switch type {
		case let .setDeleted(obj, _),
		     let .setTags(obj, _):
			return [obj]
		case let .moveNode(node, _):
			return [node]
		case let .addNode(way, node, _):
			return [way, node]
		case let .removeNode(way, _):
			return [way]
		case let .assignMembers(rel, _),
		     let .removeMember(rel, _):
			return [rel]
		case let .addMember(rel, member, _):
			var result: Set<OsmBaseObject> = [rel]
			if let obj = member.obj { result.insert(obj) }
			return result
		case let .comment(ctx):
			return Set([ctx.selections.relation as OsmBaseObject?,
			            ctx.selections.way,
			            ctx.selections.node].compactMap { $0 })
		}
	}

	// MARK: description

	override var description: String {
		switch type {
		case let .setDeleted(obj, del):
			return "UndoAction \(group): \(obj.ident).setDeleted(\(del))"
		case let .setTags(obj, _):
			return "UndoAction \(group): \(obj.ident).setTags(...)"
		case let .moveNode(node, latLon):
			return "UndoAction \(group): node(\(node.ident)).moveNode(to:\(latLon))"
		case let .addNode(way, node, i):
			return "UndoAction \(group): way(\(way.ident)).addNode(\(node.ident), at:\(i))"
		case let .removeNode(way, i):
			return "UndoAction \(group): way(\(way.ident)).removeNode(at:\(i))"
		case let .assignMembers(rel, _):
			return "UndoAction \(group): relation(\(rel.ident)).assignMembers(...)"
		case let .addMember(rel, _, i):
			return "UndoAction \(group): relation(\(rel.ident)).addMember(at:\(i))"
		case let .removeMember(rel, i):
			return "UndoAction \(group): relation(\(rel.ident)).removeMember(at:\(i))"
		case let .comment(ctx):
			return "UndoAction \(group): comment(\(ctx.comment))"
		}
	}

	// MARK: NSSecureCoding

	func encode(with coder: NSCoder) {
		coder.encode(group, forKey: "group")
		type.encode(with: coder)
	}

	required init?(coder: NSCoder) {
		let group = coder.decodeInteger(forKey: "group")
		guard let decoded = OsmEditOperation.decode(from: coder) else {
			return nil
		}
		self.group = group
		self.type = decoded
		super.init()
	}
}
