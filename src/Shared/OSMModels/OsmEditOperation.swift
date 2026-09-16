//
//  OsmEditOperation.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 9/13/26.
//  Copyright © 2026 Bryce Cogswell. All rights reserved.
//

import Foundation

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
///
/// Cases removed vs. the micro-op design:
///   `addToSpatial`, `removeFromSpatial`, `updateInSpatial` — absorbed into each op's apply
///   `incrementModifyCount` — tracked externally by `MyUndoManager`
///   `clearCachedProperties` — absorbed into `setTags` / `moveNode` apply bodies
enum OsmEditOperation {
	// MARK: OsmBaseObject
	case setTimestamp(OsmBaseObject, Date)
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
	case comment([String: Any])
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

		case let .setTimestamp(obj, newDate):
			let oldDate = obj.dateForTimestamp()
			obj.setTimestamp(newDate, token)
			return .setTimestamp(obj, oldDate)

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

// MARK: - modifyObjects

extension OsmEditOperation {
	/// Objects whose `isModified` flag should be updated when this operation is applied.
	/// `setTimestamp` and `comment` are excluded because they don't mark objects as dirty.
	var modifyObjects: Set<OsmBaseObject> {
		switch self {
		case .setTimestamp, .comment:
			return []
		case let .setDeleted(obj, _),
		     let .setTags(obj, _):
			return [obj]
		case let .moveNode(node, _):
			return [node]
		case let .addNode(way, _, _),
		     let .removeNode(way, _):
			return [way]
		case let .assignMembers(rel, _),
		     let .addMember(rel, _, _),
		     let .removeMember(rel, _):
			return [rel]
		}
	}
}
