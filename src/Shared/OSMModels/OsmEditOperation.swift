//
//  OsmEditOperation.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 9/13/26.
//  Copyright © 2026 Bryce Cogswell. All rights reserved.
//

import Foundation
import UIKit

// MARK: - UndoContext

/// The editor-layer state captured at the moment of a mutation, restored on undo/redo.
struct UndoContext {
	let comment: String
	let mapTransform: OSMTransform
	let pushpinPoint: CGPoint?
	let selections: MapView.Selections
}

// MARK: - EditToken

/// Proof that a mutation was initiated through an `OsmEditOperation.apply(to:)` call.
/// `fileprivate init()` means the only way to obtain a token is inside this file —
/// i.e. inside `OsmEditOperation.apply(to:)`.  Every tracked-object setter requires
/// one, so the compiler enforces that mutations flow through the undo system.
struct EditToken {
	fileprivate init() {}
}

// MARK: - OsmEditOperation

/// Macro-level invertible edit operations.
///
/// Each case carries exactly the values needed to reproduce the operation.
/// `apply(to:)` performs the mutation, absorbs all side-effects (spatial index
/// updates, cache invalidation), and returns the inverse operation.
enum OsmEditOperation {
	// MARK: OsmBaseObject
	case setDeleted(OsmBaseObject, Bool)
	case setTags(OsmBaseObject, [String: String])

	// MARK: OsmNode (was setLongitude; stores target LatLon directly)
	case moveNode(OsmNode, to: LatLon)

	// MARK: OsmWay (spatial index update for the way absorbed into apply)
	case addNode(OsmWay, OsmNode, index: Int)
	case removeNode(OsmWay, index: Int)

	// MARK: OsmRelation (spatial index update for the relation absorbed into apply)
	case assignMembers(OsmRelation, [OsmMember])
	case addMember(OsmRelation, OsmMember, index: Int)
	case removeMember(OsmRelation, index: Int)

	// MARK: Comment
	case comment(UndoContext)
}

// MARK: - apply(to:)

extension OsmEditOperation {
	/// Performs the mutation described by this case, absorbing all side effects
	/// (spatial index, cache invalidation), and returns the exact inverse operation.
	///
	/// Mutation and its inverse sit on adjacent lines in each case body — the
	/// "capture → mutate → return inverse" pattern makes correctness self-evident.
	@discardableResult
	func apply(to mapData: OsmMapData) -> OsmEditOperation {
		let token = EditToken()
		switch self {

		case let .setDeleted(obj, newDeleted):
			let oldDeleted = obj.deleted
			obj.setDeleted(newDeleted, token)
			obj.clearCachedProperties()
			// Absorb lifecycle spatial add/remove.
			if newDeleted && !oldDeleted {
				_ = mapData.spatial.removeMember(obj)
			} else if !newDeleted && oldDeleted {
				mapData.spatial.addMember(obj)
			}
			return .setDeleted(obj, oldDeleted)

		case let .setTags(obj, newTags):
			let oldTags = obj.tags
			obj.setTags(newTags, token)
			obj.clearCachedProperties()
			return .setTags(obj, oldTags)

		case let .moveNode(node, newLatLon):
			// Capture pre-move state for all objects whose bboxes depend on this node.
			let oldLatLon = node.latLon
			let parents = mapData.objectsContaining(node).map { ($0, $0.boundingBox) }
			let oldNodeBox = node.boundingBox
			node.setLongitude(newLatLon.lon, latitude: newLatLon.lat, token)
			mapData.spatial.updateMember(node, fromBox: oldNodeBox)
			for (parent, oldBox) in parents {
				parent.clearCachedProperties() // invalidates cached bbox
				mapData.spatial.updateMember(parent, fromBox: oldBox)
			}
			return .moveNode(node, to: oldLatLon)

		case let .addNode(way, node, index):
			let oldBox = way.boundingBox
			way.addNode(node, atIndex: index, token)
			way.clearCachedProperties()
			mapData.spatial.updateMember(way, fromBox: oldBox)
			return .removeNode(way, index: index)

		case let .removeNode(way, index):
			let node = way.nodes[index]
			let oldBox = way.boundingBox
			way.removeNodeAtIndex(index, token)
			way.clearCachedProperties()
			mapData.spatial.updateMember(way, fromBox: oldBox)
			return .addNode(way, node, index: index)

		case let .assignMembers(relation, newMembers):
			let oldMembers = relation.members
			let oldBox = relation.boundingBox
			relation.assignMembers(newMembers, token)
			relation.clearCachedProperties()
			mapData.spatial.updateMember(relation, fromBox: oldBox)
			return .assignMembers(relation, oldMembers)

		case let .addMember(relation, member, index):
			let oldBox = relation.boundingBox
			relation.addMember(member, atIndex: index, token)
			relation.clearCachedProperties()
			mapData.spatial.updateMember(relation, fromBox: oldBox)
			return .removeMember(relation, index: index)

		case let .removeMember(relation, index):
			let member = relation.members[index]
			let oldBox = relation.boundingBox
			relation.removeMemberAtIndex(index, token)
			relation.clearCachedProperties()
			mapData.spatial.updateMember(relation, fromBox: oldBox)
			return .addMember(relation, member, index: index)

		case .comment:
			// A comment is its own inverse; commentList is updated by MyUndoManager.
			return self
		}
	}
}

// MARK: - NSCoder support

extension OsmEditOperation {
	/// Integer tags written to the archive to identify the case.
	enum ArchiveTag: Int {
		case comment = 1
		case setDeleted = 2
		case setTags = 3
		case moveNode = 4
		case addNode = 5
		case removeNode = 6
		case assignMembers = 7
		case addMember = 8
		case removeMember = 9
	}

	func encode(with coder: NSCoder) {
		switch self {
		case let .setDeleted(obj, deleted):
			coder.encode(ArchiveTag.setDeleted.rawValue, forKey: "tag")
			coder.encode(obj, forKey: "obj")
			coder.encode(deleted, forKey: "bool")
		case let .setTags(obj, tags):
			coder.encode(ArchiveTag.setTags.rawValue, forKey: "tag")
			coder.encode(obj, forKey: "obj")
			coder.encode(tags as NSDictionary, forKey: "tags")
		case let .moveNode(node, latLon):
			coder.encode(ArchiveTag.moveNode.rawValue, forKey: "tag")
			coder.encode(node, forKey: "node")
			coder.encode(latLon.lon, forKey: "lon")
			coder.encode(latLon.lat, forKey: "lat")
		case let .addNode(way, node, index):
			coder.encode(ArchiveTag.addNode.rawValue, forKey: "tag")
			coder.encode(way, forKey: "way")
			coder.encode(node, forKey: "node")
			coder.encode(index, forKey: "index")
		case let .removeNode(way, index):
			coder.encode(ArchiveTag.removeNode.rawValue, forKey: "tag")
			coder.encode(way, forKey: "way")
			coder.encode(index, forKey: "index")
		case let .assignMembers(relation, members):
			coder.encode(ArchiveTag.assignMembers.rawValue, forKey: "tag")
			coder.encode(relation, forKey: "relation")
			coder.encode(members as NSArray, forKey: "members")
		case let .addMember(relation, member, index):
			coder.encode(ArchiveTag.addMember.rawValue, forKey: "tag")
			coder.encode(relation, forKey: "relation")
			coder.encode(member, forKey: "member")
			coder.encode(index, forKey: "index")
		case let .removeMember(relation, index):
			coder.encode(ArchiveTag.removeMember.rawValue, forKey: "tag")
			coder.encode(relation, forKey: "relation")
			coder.encode(index, forKey: "index")
		case let .comment(ctx):
			coder.encode(ArchiveTag.comment.rawValue, forKey: "tag")
			coder.encode(ctx.comment as NSString, forKey: "comment")
			coder.encode(Data.fromStruct(ctx.mapTransform) as NSData, forKey: "mapTransform")
			if let pushpinPoint = ctx.pushpinPoint {
				coder.encode(NSCoder.string(for: pushpinPoint) as NSString, forKey: "pushpinPoint")
			}
			coder.encode(ctx.selections.relation, forKey: "selectedRelation")
			coder.encode(ctx.selections.way, forKey: "selectedWay")
			coder.encode(ctx.selections.node, forKey: "selectedNode")
		}
	}

	/// Decodes an `OsmEditOperation` from `coder`. Returns `nil` if the tag is
	/// unknown or required objects are missing (e.g. archive version mismatch).
	static func decode(from coder: NSCoder) -> OsmEditOperation? {
		let tagRaw = coder.decodeInteger(forKey: "tag")
		guard let tag = ArchiveTag(rawValue: tagRaw) else { return nil }

		switch tag {
		case .setDeleted:
			guard let obj = coder.decodeObject(of: OsmBaseObject.self, forKey: "obj")
			else { return nil }
			return .setDeleted(obj, coder.decodeBool(forKey: "bool"))

		case .setTags:
			guard let obj = coder.decodeObject(of: OsmBaseObject.self, forKey: "obj"),
			      let tags = coder.decodeObject(of: NSDictionary.self, forKey: "tags") as? [String: String]
			else { return nil }
			return .setTags(obj, tags)

		case .moveNode:
			guard let node = coder.decodeObject(of: OsmNode.self, forKey: "node")
			else { return nil }
			return .moveNode(node, to: LatLon(latitude: coder.decodeDouble(forKey: "lat"),
			                                  longitude: coder.decodeDouble(forKey: "lon")))

		case .addNode:
			guard let way = coder.decodeObject(of: OsmWay.self, forKey: "way"),
			      let node = coder.decodeObject(of: OsmNode.self, forKey: "node")
			else { return nil }
			return .addNode(way, node, index: coder.decodeInteger(forKey: "index"))

		case .removeNode:
			guard let way = coder.decodeObject(of: OsmWay.self, forKey: "way")
			else { return nil }
			return .removeNode(way, index: coder.decodeInteger(forKey: "index"))

		case .assignMembers:
			guard let relation = coder.decodeObject(of: OsmRelation.self, forKey: "relation"),
			      let members = coder.decodeObject(of: NSArray.self, forKey: "members") as? [OsmMember]
			else { return nil }
			return .assignMembers(relation, members)

		case .addMember:
			guard let relation = coder.decodeObject(of: OsmRelation.self, forKey: "relation"),
			      let member = coder.decodeObject(of: OsmMember.self, forKey: "member")
			else { return nil }
			return .addMember(relation, member, index: coder.decodeInteger(forKey: "index"))

		case .removeMember:
			guard let relation = coder.decodeObject(of: OsmRelation.self, forKey: "relation")
			else { return nil }
			return .removeMember(relation, index: coder.decodeInteger(forKey: "index"))

		case .comment:
			guard let comment = coder.decodeObject(of: NSString.self, forKey: "comment") as String?,
			      let mapTransformData = coder.decodeObject(of: NSData.self, forKey: "mapTransform") as Data?,
			      let mapTransform: OSMTransform = mapTransformData.asStruct()
			else { return nil }
			let pushpinPoint = (coder.decodeObject(of: NSString.self, forKey: "pushpinPoint") as String?)
				.map { NSCoder.cgPoint(for: $0) }
			let selections = MapView.Selections(
				node: coder.decodeObject(of: OsmNode.self, forKey: "selectedNode"),
				way: coder.decodeObject(of: OsmWay.self, forKey: "selectedWay"),
				relation: coder.decodeObject(of: OsmRelation.self, forKey: "selectedRelation"))
			return .comment(UndoContext(comment: comment,
			                            mapTransform: mapTransform,
			                            pushpinPoint: pushpinPoint,
			                            selections: selections))
		}
	}
}

// MARK: - modifiesObject

extension OsmEditOperation {
	/// The object whose `isModified` flag should be updated when this operation is applied.
	/// `comment` is excluded because it doesn't mark objects as dirty.
	var modifiesObject: OsmBaseObject? {
		switch self {
		case .comment:
			return nil
		case let .setDeleted(obj, _),
		     let .setTags(obj, _):
			return obj
		case let .moveNode(node, _):
			return node
		case let .addNode(way, _, _),
		     let .removeNode(way, _):
			return way
		case let .assignMembers(rel, _),
		     let .addMember(rel, _, _),
		     let .removeMember(rel, _):
			return rel
		}
	}
}
