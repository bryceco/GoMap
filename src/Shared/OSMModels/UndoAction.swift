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
		case let .comment(ctx):
			return Set([ctx.selections.relation as OsmBaseObject?,
			            ctx.selections.way,
			            ctx.selections.node].compactMap { $0 })
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
		case let .comment(ctx):
			return "UndoAction \(group): comment(\(ctx.comment))"
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
		case let .comment(ctx):
			coder.encode(Tag.comment.rawValue, forKey: "tag")
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

	required init?(coder: NSCoder) {
		let group = coder.decodeInteger(forKey: "group")
		guard let decoded = UndoAction.decodeType(from: coder) else {
			self.group = 0
			self.type = .comment(UndoContext(comment: "",
			                                 mapTransform: .identity,
			                                 pushpinPoint: nil,
			                                 selections: MapView.Selections()))
			super.init()
			return nil
		}
		self.group = group
		self.type = decoded
		super.init()
	}

	/// Decodes the `OsmEditOperation` from `coder`. Returns `nil` if the tag is
	/// unknown or required objects are missing (e.g. archive version mismatch).
	private static func decodeType(from coder: NSCoder) -> OsmEditOperation? {
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
