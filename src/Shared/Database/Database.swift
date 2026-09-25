//
//  Database.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 9/14/14.
//  Copyright (c) 2014 Bryce Cogswell. All rights reserved.
//

import Foundation

#if DEBUG && false
let USE_RTREE = 1
#else
let USE_RTREE = 0
#endif

enum DatabaseError: LocalizedError {
	case wayReferencedByNodeDoesNotExist
	case relationReferencedByMemberDoesNotExist
	case unlinkFailed(Int32)

	public var errorDescription: String? {
		switch self {
		case .wayReferencedByNodeDoesNotExist: return "DatabaseError.wayReferencedByNodeDoesNotExist"
		case .relationReferencedByMemberDoesNotExist: return "DatabaseError.relationReferencedByMemberDoesNotExist"
		case let .unlinkFailed(rc): return "DatabaseError.unlinkFailed(\(rc))"
		}
	}
}

final class Database {
	private let db: Sqlite

#if USE_RTREE
	private var spatialInsert: SqliteStatement?
	private var spatialDelete: SqliteStatement?
#endif

	static let dispatchQueue = DispatchQueue(label: "com.bryceco.gomap.database",
	                                         qos: .default,
	                                         attributes: [])

	// MARK: initialize

	class func databasePath(withName name: String) -> String {
		return Sqlite.pathForOsmName(name)
	}

	// return self if database can be opened
	// return nil if database doesn't exist or is corrupted
	init(name: String) throws {
		let db = try Sqlite(osmName: name)
		self.db = db
		try db.exec("PRAGMA foreign_keys=ON;")
	}

	var path: String { db.path }

	class func delete(withName name: String) throws {
		let path = Database.databasePath(withName: name)
		let rc = unlink(path)
		if rc != 0 {
			throw DatabaseError.unlinkFailed(errno)
		}
	}

	deinit {}

	private func dropTables() throws {
		try db.exec("drop table node_tags;")
		try db.exec("drop table nodes;")
		try db.exec("drop table way_tags;")
		try db.exec("drop table way_nodes;")
		try db.exec("drop table ways;")
		try db.exec("drop table relation_tags;")
		try db.exec("drop table relation_members;")
		try db.exec("drop table relations;")
#if USE_RTREE
		try db.exec("drop table spatial;")
#endif
		try db.exec("vacuum;") // compact database
	}

	func createTables() throws {
		// nodes

		try db.exec(
			"""
				CREATE TABLE IF NOT EXISTS nodes(\
					IDENT		INT8	unique PRIMARY KEY	NOT NULL,\
					USER        varchar(255)	NOT NULL,\
					TIMESTAMP   varchar(255)	NOT NULL,\
					VERSION     INT				NOT NULL,\
					CHANGESET   INT8			NOT NULL,\
					UID         INT				NOT NULL,\
					longitude   real			NOT NULL,\
					latitude	real			NOT NULL\
				);
			""")

		try db.exec(
			"""
				create table if not exists node_tags(\
					ident	int8			not null,\
					key		varchar(255)	not null,\
					value	varchar(255)	not null,\
					FOREIGN KEY(ident) REFERENCES nodes(ident) on delete cascade);
			""")

		// ways

		try db.exec(
			"""
				CREATE TABLE IF NOT EXISTS ways(\
					IDENT		INT8	unique PRIMARY KEY	NOT NULL,\
					USER        varchar(255)				NOT NULL,\
					TIMESTAMP   varchar(255)				NOT NULL,\
					VERSION     INT							NOT NULL,\
					CHANGESET   INT8						NOT NULL,\
					UID         INT							NOT NULL,\
					nodecount   INT							NOT NULL\
				);
			""")

		try db.exec(
			"""
				create table if not exists way_nodes(\
					ident		int8	not null,\
					node_id		int8	not null,\
					node_index	int4	not null,\
					FOREIGN KEY(ident) REFERENCES ways(ident) on delete cascade);
			""")

		try db.exec(
			"""
				create table if not exists way_tags(\
					ident	int8			not null,\
					key		varchar(255)	not null,\
					value	varchar(255)	not null,\
					FOREIGN KEY(ident) REFERENCES ways(ident) on delete cascade);
			""")

		// relations

		try db.exec(
			"""
				CREATE TABLE IF NOT EXISTS relations(\
					IDENT		INT8	unique PRIMARY KEY	NOT NULL,\
					USER        varchar(255)		NOT NULL,\
					TIMESTAMP   varchar(255)		NOT NULL,\
					VERSION     INT					NOT NULL,\
					CHANGESET   INT8				NOT NULL,\
					UID         INT					NOT NULL,\
					membercount INT					NOT NULL\
					);
			""")

		try db.exec(
			"""
				create table if not exists relation_members(\
					ident			int8			not null,\
					type			varchar[255]	not null,\
					ref				int8			not null,\
					role			varchar[255]	not null,\
					member_index	int4			not null,\
					FOREIGN KEY(ident) REFERENCES relations(ident) on delete cascade);
			""")

		try db.exec(
			"""
				create table if not exists relation_tags(\
					ident	int8			not null,\
					key		varchar(255)	not null,\
					value	varchar(255)	not null,\
					FOREIGN KEY(ident) REFERENCES relations(ident) on delete cascade);
			""")

		// spatial

#if USE_RTREE
		try db.exec(
			"""
				create virtual table if not exists spatial using rtree(\
					ident	int8	primary key	not null,\
					minX	double	not null,\
					maxX	double	not null,\
					minY	double	not null,\
					maxY	double	not null\
				);
			""")
#endif
	}

	// MARK: spatial

#if USE_RTREE
	private func deleteSpatial(_ object: OsmBaseObject?) throws {
		if spatialDelete == nil {
			spatialDelete = try db.prepare("DELETE FROM spatial WHERE ident=?;")
		}
		guard let spatialDelete else { return }
		try spatialDelete.reset()
		try spatialDelete.clearBindings()
		try spatialDelete.bindInt64(1, TaggedObjectIdent(object))
		try spatialDelete.step()
	}

	private func add(toSpatial object: OsmBaseObject?) throws {
		if spatialInsert == nil {
			spatialInsert = try db.prepare("INSERT INTO spatial (ident,minX,maxX,minY,maxY) VALUES (?,?,?,?,?);")
		}
		guard let spatialInsert, let bbox = object?.boundingBox else { return }
		try spatialInsert.reset()
		try spatialInsert.clearBindings()
		try spatialInsert.bindInt64(1, TaggedObjectIdent(object))
		try spatialInsert.bindDouble(2, bbox.origin.x)
		try spatialInsert.bindDouble(3, bbox.origin.x + bbox.size.width)
		try spatialInsert.bindDouble(4, bbox.origin.y)
		try spatialInsert.bindDouble(5, bbox.origin.y + bbox.size.height)
		// If there's a constraint violation the object is already in the table.
		// This might be an update to a later version from the server, so delete and retry.
		while try spatialInsert.step(hasResult: Sqlite.CONSTRAINT) {
			try deleteSpatial(object)
		}
	}
#endif

	// MARK: save

	private func saveNodes(_ nodes: [OsmServerNode]) throws {
		if nodes.count == 0 {
			return
		}

		let nodeStatement = try db.prepare(
			"INSERT INTO NODES (user,timestamp,version,changeset,uid,longitude,latitude,ident) VALUES (?,?,?,?,?,?,?,?);")
		let tagStatement = try db.prepare("INSERT INTO node_tags (ident,key,value) VALUES (?,?,?);")

		for node in nodes {
			try nodeStatement.reset()
			try nodeStatement.clearBindings()
			try nodeStatement.bindText(1, node.user)
			try nodeStatement.bindText(2, node.timestamp)
			try nodeStatement.bindInt32(3, Int32(node.version))
			try nodeStatement.bindInt64(4, node.changeset)
			try nodeStatement.bindInt32(5, Int32(node.uid))
			try nodeStatement.bindDouble(6, node.latLon.lon)
			try nodeStatement.bindDouble(7, node.latLon.lat)
			try nodeStatement.bindInt64(8, node.ident)

			while try nodeStatement.step(hasResult: Sqlite.CONSTRAINT) {
				// tried to insert something already there. This might be an update to a later version from the server so delete what we have and retry
				print(String(format: "retry node %lld\n", node.ident))
				try? deleteNodes([node.ident])
			}

			for (key, value) in node.tags {
				try tagStatement.reset()
				try tagStatement.clearBindings()
				try tagStatement.bindInt64(1, node.ident)
				try tagStatement.bindText(2, key)
				try tagStatement.bindText(3, value)
				try tagStatement.step()
			}
#if USE_RTREE
			add(toSpatial: node)
#endif
		}
	}

	private func saveWays(_ ways: [OsmServerWay]) throws {
		if ways.count == 0 {
			return
		}

		let wayStatement = try db
			.prepare("INSERT INTO ways (ident,user,timestamp,version,changeset,uid,nodecount) VALUES (?,?,?,?,?,?,?);")
		let tagStatement = try db.prepare("INSERT INTO way_tags (ident,key,value) VALUES (?,?,?);")
		let nodeStatement = try db.prepare("INSERT INTO way_nodes (ident,node_id,node_index) VALUES (?,?,?);")

		for way in ways {
			try wayStatement.reset()
			try wayStatement.clearBindings()
			try wayStatement.bindInt64(1, way.ident)
			try wayStatement.bindText(2, way.user)
			try wayStatement.bindText(3, way.timestamp)
			try wayStatement.bindInt32(4, Int32(way.version))
			try wayStatement.bindInt64(5, way.changeset)
			try wayStatement.bindInt32(6, Int32(way.uid))
			try wayStatement.bindInt32(7, Int32(way.nodeRefs.count))
			while try wayStatement.step(hasResult: Sqlite.CONSTRAINT) {
				// tried to insert something already there. This might be an update to a later version from the server so delete what we have and retry
				print(String(format: "retry way %lld\n", way.ident))
				try? deleteWays([way.ident])
			}

			for (key, value) in way.tags {
				try tagStatement.reset()
				try tagStatement.clearBindings()
				try tagStatement.bindInt64(1, way.ident)
				try tagStatement.bindText(2, key)
				try tagStatement.bindText(3, value)
				try tagStatement.step()
			}

			var index: Int32 = 0
			for nodeRef in way.nodeRefs {
				try nodeStatement.reset()
				try nodeStatement.clearBindings()
				try nodeStatement.bindInt64(1, way.ident)
				try nodeStatement.bindInt64(2, nodeRef)
				try nodeStatement.bindInt32(3, index)
				try nodeStatement.step()
				index += 1
			}
#if USE_RTREE
			add(toSpatial: way)
#endif
		}
	}

	private func saveRelations(_ relations: [OsmServerRelation]) throws {
		if relations.count == 0 {
			return
		}

		let baseStatement = try db
			.prepare(
				"INSERT INTO relations (ident,user,timestamp,version,changeset,uid,membercount) VALUES (?,?,?,?,?,?,?);")
		let tagStatement = try db.prepare("INSERT INTO relation_tags (ident,key,value) VALUES (?,?,?);")
		let memberStatement = try db
			.prepare("INSERT INTO relation_members (ident,type,ref,role,member_index) VALUES (?,?,?,?,?);")

		for relation in relations {
			try baseStatement.reset()
			try baseStatement.clearBindings()
			try baseStatement.bindInt64(1, relation.ident)
			try baseStatement.bindText(2, relation.user)
			try baseStatement.bindText(3, relation.timestamp)
			try baseStatement.bindInt32(4, Int32(relation.version))
			try baseStatement.bindInt64(5, relation.changeset)
			try baseStatement.bindInt32(6, Int32(relation.uid))
			try baseStatement.bindInt32(7, Int32(relation.members.count))
			while try baseStatement.step(hasResult: Sqlite.CONSTRAINT) {
				// tried to insert something already there. This might be an update to a later version from the server so delete what we have and retry
				print(String(format: "retry relation %lld\n", relation.ident))
				try? deleteRelations([relation.ident])
			}

			for (key, value) in relation.tags {
				try tagStatement.reset()
				try tagStatement.clearBindings()
				try tagStatement.bindInt64(1, relation.ident)
				try tagStatement.bindText(2, key)
				try tagStatement.bindText(3, value)
				try tagStatement.step()
			}

			var index: Int32 = 0
			for member in relation.members {
				try memberStatement.reset()
				try memberStatement.clearBindings()
				try memberStatement.bindInt64(1, relation.ident)
				try memberStatement.bindText(2, member.type.string)
				try memberStatement.bindInt64(3, member.ref)
				try memberStatement.bindText(4, member.role)
				try memberStatement.bindInt32(5, index)
				try memberStatement.step()
				index += 1
			}
#if USE_RTREE
			add(toSpatial: relation)
#endif
		}
	}

	// MARK: delete

	private func deleteNodes(_ nodes: [OsmIdentifier]) throws {
		if nodes.isEmpty {
			return
		}

		let nodeStatement = try db.prepare("DELETE from NODES where ident=?;")

		for ident in nodes {
			try nodeStatement.reset()
			try nodeStatement.clearBindings()
			try nodeStatement.bindInt64(1, ident)
			try nodeStatement.step()
		}
	}

	private func deleteWays(_ ways: [OsmIdentifier]) throws {
		if ways.count == 0 {
			return
		}

		let nodeStatement = try db.prepare("DELETE from WAYS where ident=?;")

		for ident in ways {
			try nodeStatement.reset()
			try nodeStatement.clearBindings()
			try nodeStatement.bindInt64(1, ident)
			try nodeStatement.step()
		}
	}

	private func deleteRelations(_ relations: [OsmIdentifier]) throws {
		if relations.count == 0 {
			return
		}

		let relationStatement = try db.prepare("DELETE from RELATIONS where ident=?;")

		for ident in relations {
			try relationStatement.reset()
			try relationStatement.clearBindings()
			try relationStatement.bindInt64(1, ident)
			try relationStatement.step()
		}
	}

	// MARK: update

	func save(
		saveNodes: [OsmServerNode],
		saveWays: [OsmServerWay],
		saveRelations: [OsmServerRelation],
		deleteNodes: [OsmIdentifier],
		deleteWays: [OsmIdentifier],
		deleteRelations: [OsmIdentifier],
		isUpdate: Bool) throws
	{
		try db.exec("BEGIN")

		do {
			if isUpdate {
				try self.deleteNodes(saveNodes.map(\.ident))
				try self.deleteWays(saveWays.map(\.ident))
				try self.deleteRelations(saveRelations.map(\.ident))
			}
			try self.saveNodes(saveNodes)
			try self.saveWays(saveWays)
			try self.saveRelations(saveRelations)
			try self.deleteNodes(deleteNodes)
			try self.deleteWays(deleteWays)
			try self.deleteRelations(deleteRelations)
			try db.exec("COMMIT")
		} catch {
			try db.exec("ROLLBACK")
			throw error
		}
	}

	// MARK: query

	private func queryTagTable(_ tableName: String, sizeEstimate: Int) throws -> [OsmIdentifier: [String: String]] {
		let query = "SELECT key,value,ident FROM \(tableName)"
		let tagStatement = try db.prepare(query)

		var dict: [OsmIdentifier: [String: String]] = [:]
		dict.reserveCapacity(sizeEstimate)

		try tagStatement.reset()
		try tagStatement.clearBindings()
		while try tagStatement.step(hasResult: Sqlite.ROW) {
			let key = tagStatement.columnText(0)
			let value = tagStatement.columnText(1)
			let ident = tagStatement.columnInt64(2)

			if dict[ident] == nil {
				dict[ident] = [key: value]
			} else {
				dict[ident]![key] = value
			}
		}

		return dict
	}

	func queryNodes() throws -> [OsmServerNode] {
		let nodeStatement =
			try db.prepare("SELECT ident,user,timestamp,version,changeset,uid,longitude,latitude FROM nodes;")

		let tagsDict = try queryTagTable("node_tags", sizeEstimate: 5000)

		var nodes: [OsmServerNode] = []
		nodes.reserveCapacity(100000)

		while try nodeStatement.step(hasResult: Sqlite.ROW) {
			let ident = nodeStatement.columnInt64(0)
			let user = nodeStatement.columnText(1)
			let timestamp = nodeStatement.columnText(2)
			let version = nodeStatement.columnInt32(3)
			let changeset = nodeStatement.columnInt64(4)
			let uid = nodeStatement.columnInt32(5)
			let longitude = nodeStatement.columnDouble(6)
			let latitude = nodeStatement.columnDouble(7)

			let tags = tagsDict[ident] ?? [:]

			let node = OsmServerNode(
				ident: ident,
				version: Int(version),
				changeset: Int64(changeset),
				user: user,
				uid: Int(uid),
				timestamp: timestamp,
				tags: tags,
				body: LatLon(latitude: latitude, longitude: longitude))

			nodes.append(node)
		}

		return nodes
	}

	private struct WayMetadata {
		let user: String, timestamp: String, tags: [String: String]
		let version: Int32, uid: Int32
		let changeset: Int64
		var nodeRefs: [OsmIdentifier]
	}

	func queryWays() throws -> [OsmServerWay] {
		let wayStatement = try db.prepare("SELECT ident,user,timestamp,version,changeset,uid,nodecount FROM ways")
		let tagsDict = try queryTagTable("way_tags", sizeEstimate: 20000)

		// Collect way metadata, pre-sizing nodeRef arrays using nodecount
		var wayMeta: [OsmIdentifier: WayMetadata] = [:]

		while try wayStatement.step(hasResult: Sqlite.ROW) {
			let ident = wayStatement.columnInt64(0)
			let user = wayStatement.columnText(1)
			let timestamp = wayStatement.columnText(2)
			let version = wayStatement.columnInt32(3)
			let changeset = wayStatement.columnInt64(4)
			let uid = wayStatement.columnInt32(5)
			let nodecount = wayStatement.columnInt32(6)
			let tags = tagsDict[ident] ?? [:]
			wayMeta[ident] = WayMetadata(
				user: user, timestamp: timestamp, tags: tags,
				version: version, uid: uid, changeset: changeset,
				nodeRefs: [OsmIdentifier](repeating: -1, count: Int(nodecount)))
		}

		// Fill in node IDs by index
		try fillNodeRefs(into: &wayMeta)

		return wayMeta.map { ident, meta in
			OsmServerWay(
				ident: ident,
				version: Int(meta.version),
				changeset: meta.changeset,
				user: meta.user,
				uid: Int(meta.uid),
				timestamp: meta.timestamp,
				tags: meta.tags,
				body: meta.nodeRefs)
		}
	}

	private func fillNodeRefs(into wayMeta: inout [OsmIdentifier: WayMetadata]) throws {
		let nodeStatement = try db.prepare("SELECT ident,node_id,node_index FROM way_nodes")

		while try nodeStatement.step(hasResult: Sqlite.ROW) {
			let ident = nodeStatement.columnInt64(0)
			let node_id = nodeStatement.columnInt64(1)
			let node_index = nodeStatement.columnInt32(2)

			guard wayMeta[ident] != nil else {
				throw DatabaseError.wayReferencedByNodeDoesNotExist
			}
			wayMeta[ident]!.nodeRefs[Int(node_index)] = node_id
		}
	}

	private struct RelationMetadata {
		let user: String, timestamp: String, tags: [String: String]
		let version: Int32, uid: Int32
		let changeset: Int64
		var members: [OsmMember?]
	}

	func queryRelations() throws -> [OsmServerRelation] {
		let relationStatement = try db
			.prepare("SELECT ident,user,timestamp,version,changeset,uid,membercount FROM relations")

		let tagsDict = try queryTagTable("relation_tags", sizeEstimate: 1000)

		var relationMeta: [OsmIdentifier: RelationMetadata] = [:]
		relationMeta.reserveCapacity(1000)

		while try relationStatement.step(hasResult: Sqlite.ROW) {
			let ident = relationStatement.columnInt64(0)
			let user = relationStatement.columnText(1)
			let timestamp = relationStatement.columnText(2)
			let version = relationStatement.columnInt32(3)
			let changeset = relationStatement.columnInt64(4)
			let uid = relationStatement.columnInt32(5)
			let membercount = relationStatement.columnInt32(6)
			let tags = tagsDict[ident] ?? [:]
			relationMeta[ident] = RelationMetadata(
				user: user, timestamp: timestamp, tags: tags,
				version: version, uid: uid, changeset: changeset,
				members: [OsmMember?](repeating: nil, count: Int(membercount)))
		}

		try fillMembers(into: &relationMeta)

		return relationMeta.map { ident, meta in
			OsmServerRelation(
				ident: ident,
				version: Int(meta.version),
				changeset: meta.changeset,
				user: meta.user,
				uid: Int(meta.uid),
				timestamp: meta.timestamp,
				tags: meta.tags,
				body: meta.members.map { $0! })
		}
	}

	private func fillMembers(into relationMeta: inout [OsmIdentifier: RelationMetadata]) throws {
		let memberStatement = try db.prepare("SELECT ident,type,ref,role,member_index FROM relation_members")

		while try memberStatement.step(hasResult: Sqlite.ROW) {
			let ident = memberStatement.columnInt64(0)
			let type = memberStatement.columnText(1)
			let ref = memberStatement.columnInt64(2)
			let role = memberStatement.columnText(3)
			let member_index = memberStatement.columnInt32(4)

			guard relationMeta[ident] != nil else {
				throw DatabaseError.relationReferencedByMemberDoesNotExist
			}
			let member = try OsmMember(type: OSM_TYPE(string: type), ref: ref, role: role)
			relationMeta[ident]!.members[Int(member_index)] = member
		}
	}
}
