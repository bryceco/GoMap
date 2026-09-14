//
//  UndoAction.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 9/13/26.
//  Copyright © 2026 Bryce Cogswell. All rights reserved.
//

import Foundation

// MARK: - EditToken

/// Proof that a mutation was initiated through an `UndoActionType.apply(to:)` call.
/// `fileprivate init()` means the only way to obtain a token is inside this file —
/// i.e. inside `UndoActionType.apply(to:)`.  Every tracked-object setter requires
/// one, so the compiler enforces that mutations flow through the undo system.
struct EditToken {
	fileprivate init() {}
}

// MARK: - UndoActionType

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
enum UndoActionType {
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

extension UndoActionType {
	/// Performs the mutation described by this case, absorbing all side effects
	/// (spatial index, cache invalidation), and returns the exact inverse operation.
	///
	/// Mutation and its inverse sit on adjacent lines in each case body — the
	/// "capture → mutate → return inverse" pattern makes correctness self-evident.
	///
	/// `modifyCount` is intentionally NOT adjusted here; `MyUndoManager` handles
	/// it externally via `modifyObjects` so undo/redo direction is unambiguous.
	@discardableResult
	func apply(to mapData: OsmMapData) -> UndoActionType {
		let token = EditToken()
		switch self {

		case let .setTimestamp(obj, newDate):
			let oldDate = obj.dateForTimestamp()
			obj.setTimestamp(newDate, token)
			return .setTimestamp(obj, oldDate)

		case let .setDeleted(obj, newDeleted):
			let oldDeleted = obj.deleted
			obj.setDeleted(newDeleted, token)
			// Absorb lifecycle spatial add/remove.
			if newDeleted && !oldDeleted {
				_ = mapData.spatial.removeMember(obj)
			} else if !newDeleted && oldDeleted {
				mapData.spatial.addMember(obj)
			}
			return .setDeleted(obj, oldDeleted)

		case let .setTags(obj, newTags):
			let oldTags = obj.tags
			obj.setTags(newTags, token) // calls clearCachedProperties internally
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
			mapData.spatial.updateMember(way, fromBox: oldBox)
			return .removeNode(way, index: index)

		case let .removeNode(way, index):
			let node = way.nodes[index]
			let oldBox = way.boundingBox
			way.removeNodeAtIndex(index, token)
			mapData.spatial.updateMember(way, fromBox: oldBox)
			return .addNode(way, node, index: index)

		case let .assignMembers(relation, newMembers):
			let oldMembers = relation.members
			let oldBox = relation.boundingBox
			relation.assignMembers(newMembers, token)
			mapData.spatial.updateMember(relation, fromBox: oldBox)
			return .assignMembers(relation, oldMembers)

		case let .addMember(relation, member, index):
			let oldBox = relation.boundingBox
			relation.addMember(member, atIndex: index, token)
			mapData.spatial.updateMember(relation, fromBox: oldBox)
			return .removeMember(relation, index: index)

		case let .removeMember(relation, index):
			let member = relation.members[index]
			let oldBox = relation.boundingBox
			relation.removeMemberAtIndex(index, token)
			mapData.spatial.updateMember(relation, fromBox: oldBox)
			return .addMember(relation, member, index: index)

		case .comment:
			// A comment is its own inverse; commentList is updated by MyUndoManager.
			return self
		}
	}
}

// MARK: - modifyObjects

extension UndoActionType {
	/// Objects whose `modifyCount` should be incremented (or decremented during undo)
	/// when this operation is applied. `setTimestamp` and `comment` are excluded
	/// because they don't mark objects as dirty.
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

// MARK: - UndoAction

/// Pairs an `UndoActionType` with its undo-group ID.
/// Implements `NSSecureCoding` so it can be archived as part of `OsmMapData`.
final class UndoAction: NSObject, NSSecureCoding {
	static var supportsSecureCoding: Bool { true }

	let type: UndoActionType
	var group: Int

	init(type: UndoActionType, group: Int = 0) {
		self.type = type
		self.group = group
	}

	// MARK: osmObjects (for upload grouping)

	/// All OSM objects directly referenced by this action, used to determine
	/// which undo groups share objects (for selective upload grouping).
	var osmObjects: Set<OsmBaseObject> {
		switch type {
		case let .setTimestamp(obj, _),
		     let .setDeleted(obj, _),
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
		case let .comment(dict):
			return Set(dict.values.compactMap { $0 as? OsmBaseObject })
		}
	}

	// MARK: description

	override var description: String {
		switch type {
		case let .setTimestamp(obj, date):
			return "UndoAction \(group): \(obj.ident).setTimestamp(\(date))"
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
		case let .comment(d):
			return "UndoAction \(group): comment(\(d["comment"] ?? ""))"
		}
	}

	// MARK: NSSecureCoding

	/// Integer tags written to the archive to identify the case.
	/// Tags 10–14 were retired with the micro-op design; gaps are intentional.
	private enum Tag: Int {
		case setTimestamp = 1
		case setDeleted = 2
		case setTags = 3
		case moveNode = 4 // was setLongitude; same 2-double encoding
		case addNode = 5
		case removeNode = 6
		case assignMembers = 7
		case addMember = 8
		case removeMember = 9
		// 10–14 retired
		case comment = 15
	}

	func encode(with coder: NSCoder) {
		coder.encode(group, forKey: "group")
		switch type {
		case let .setTimestamp(obj, date):
			coder.encode(Tag.setTimestamp.rawValue, forKey: "tag")
			coder.encode(obj, forKey: "obj")
			coder.encode(date as NSDate, forKey: "date")
		case let .setDeleted(obj, deleted):
			coder.encode(Tag.setDeleted.rawValue, forKey: "tag")
			coder.encode(obj, forKey: "obj")
			coder.encode(deleted, forKey: "bool")
		case let .setTags(obj, tags):
			coder.encode(Tag.setTags.rawValue, forKey: "tag")
			coder.encode(obj, forKey: "obj")
			coder.encode(tags as NSDictionary, forKey: "tags")
		case let .moveNode(node, latLon):
			coder.encode(Tag.moveNode.rawValue, forKey: "tag")
			coder.encode(node, forKey: "node")
			coder.encode(latLon.lon, forKey: "lon")
			coder.encode(latLon.lat, forKey: "lat")
		case let .addNode(way, node, index):
			coder.encode(Tag.addNode.rawValue, forKey: "tag")
			coder.encode(way, forKey: "way")
			coder.encode(node, forKey: "node")
			coder.encode(index, forKey: "index")
		case let .removeNode(way, index):
			coder.encode(Tag.removeNode.rawValue, forKey: "tag")
			coder.encode(way, forKey: "way")
			coder.encode(index, forKey: "index")
		case let .assignMembers(relation, members):
			coder.encode(Tag.assignMembers.rawValue, forKey: "tag")
			coder.encode(relation, forKey: "relation")
			coder.encode(members as NSArray, forKey: "members")
		case let .addMember(relation, member, index):
			coder.encode(Tag.addMember.rawValue, forKey: "tag")
			coder.encode(relation, forKey: "relation")
			coder.encode(member, forKey: "member")
			coder.encode(index, forKey: "index")
		case let .removeMember(relation, index):
			coder.encode(Tag.removeMember.rawValue, forKey: "tag")
			coder.encode(relation, forKey: "relation")
			coder.encode(index, forKey: "index")
		case let .comment(dict):
			coder.encode(Tag.comment.rawValue, forKey: "tag")
			coder.encode(dict as NSDictionary, forKey: "comment")
		}
	}

	required init?(coder: NSCoder) {
		let group = coder.decodeInteger(forKey: "group")
		guard let decoded = UndoAction.decodeType(from: coder) else {
			self.group = 0
			self.type = .comment([:])
			super.init()
			return nil
		}
		self.group = group
		self.type = decoded
		super.init()
	}

	/// Decodes the `UndoActionType` from `coder`. Returns `nil` if the tag is
	/// unknown or required objects are missing (e.g. archive version mismatch).
	private static func decodeType(from coder: NSCoder) -> UndoActionType? {
		let tagRaw = coder.decodeInteger(forKey: "tag")
		guard let tag = Tag(rawValue: tagRaw) else { return nil }

		switch tag {
		case .setTimestamp:
			guard let obj = coder.decodeObject(of: OsmBaseObject.self, forKey: "obj"),
			      let date = coder.decodeObject(of: NSDate.self, forKey: "date") as Date?
			else { return nil }
			return .setTimestamp(obj, date)

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
			// Must include all classes that can appear as values inside the dict.
			// Using only NSDictionary.self causes the decoder to reject embedded OsmNode/Way/Relation
			// objects and cache their UIDs as nil, which poisons subsequent decodes of the same objects
			// by actions like moveNode that decode them with the correct type — causing those decodes
			// to return nil from the UID cache and abort the entire undoStack deserialization.
			let dict = (coder.decodeObject(of: [NSDictionary.self,
			                                    OsmNode.self,
			                                    OsmWay.self,
			                                    OsmRelation.self,
			                                    NSString.self,
			                                    NSData.self,
			                                    NSMutableData.self],
			                               forKey: "comment") as? [String: Any]) ?? [:]
			return .comment(dict)
		}
	}
}
