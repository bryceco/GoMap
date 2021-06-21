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

final class Database {
	private let db: Sqlite

#if USE_RTREE
	private var spatialInsert: SqliteStatement
	private var spatialDelete: SqliteStatement
#endif

	static let dispatchQueue = DispatchQueue(label: "com.bryceco.gomap.database",
	                                         qos: .default,
	                                         attributes: [])

	// MARK: initialize

	class func databasePath(withName name: String) -> String {
		return Sqlite.pathForName(name)
	}

	// return self if database can be opened
	// return nil if database doesn't exist or is corrupted
	init?(name: String) {
		guard let db = Sqlite(name: name) else { return nil }
		self.db = db
		if (try? db.exec("PRAGMA foreign_keys=ON;")) == nil {
			return nil
		}
	}

	var path: String { db.path }

	class func delete(withName name: String) throws {
		let path = Database.databasePath(withName: name)
		if unlink(path) != 0 {
			throw SqliteError.unlink
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
	private func deleteSpatial(_ object: OsmBaseObject?) -> Bool {
		var rc: Int32
		if spatialDelete == nil {
			rc = sqlite3_prepare_v2(db, "INSERT INTO spatial (ident) VALUES (?,?);", -1, &spatialDelete, nil)
			if rc != SQLITE_OK {
				DbgAssert(false)
				return false
			}
		}

		sqlite3_reset(spatialDelete)
		SqlOk(sqlite3_clear_bindings(spatialDelete))
		SqlOk(sqlite3_bind_int64(spatialDelete, 1, TaggedObjectIdent(object)))
		rc = sqlite3_step(spatialDelete)
		return rc == SQLITE_DONE
	}

	private func add(toSpatial object: OsmBaseObject?) throws {
		if spatialInsert == nil {
			DbgOk(sqlite3_prepare_v2(db, "INSERT INTO spatial (ident,minX, maxX,minY, maxY) VALUES (?,?,?,?,?);", -1, &spatialInsert, nil))
		}

		let bbox = object?.boundingBox
		sqlite3_reset(spatialInsert)
		SqlOk(sqlite3_clear_bindings(spatialInsert))
		SqlOk(sqlite3_bind_int64(spatialInsert, 1, TaggedObjectIdent(object)))
		SqlOk(sqlite3_bind_double(spatialInsert, 2, bbox?.origin.x))
		SqlOk(sqlite3_bind_double(spatialInsert, 3, bbox?.origin.x + bbox?.size.width))
		SqlOk(sqlite3_bind_double(spatialInsert, 4, bbox?.origin.y))
		SqlOk(sqlite3_bind_double(spatialInsert, 5, bbox?.origin.y + bbox?.size.height))
		while true {
			let rc = sqlite3_step(spatialInsert)
			if rc != SQLITE_CONSTRAINT {
				SqlOk(rc, SQLITE_DONE)
				break
			}
			// tried to insert something already there. This might be an update to a later version from the server so delete what we have and retry
			try? deleteSpatial(object)
		}
	}
#endif

	// MARK: save

	private func saveNodes(_ nodes: [OsmNode]) throws {
		if nodes.count == 0 {
			return
		}

		let nodeStatement = try db.prepare("INSERT INTO NODES (user,timestamp,version,changeset,uid,longitude,latitude,ident) VALUES (?,?,?,?,?,?,?,?);")
		let tagStatement = try db.prepare("INSERT INTO node_tags (ident,key,value) VALUES (?,?,?);")

		for node in nodes {
			try db.reset(nodeStatement)
			try db.clearBindings(nodeStatement)
			try db.bindText(nodeStatement, 1, node.user)
			try db.bindText(nodeStatement, 2, node.timestamp)
			try db.bindInt32(nodeStatement, 3, Int32(node.version))
			try db.bindInt64(nodeStatement, 4, node.changeset)
			try db.bindInt32(nodeStatement, 5, Int32(node.uid))
			try db.bindDouble(nodeStatement, 6, node.latLon.lon)
			try db.bindDouble(nodeStatement, 7, node.latLon.lat)
			try db.bindInt64(nodeStatement, 8, node.ident)

			while try db.step(nodeStatement, hasResult: Sqlite.CONSTRAINT) {
				// tried to insert something already there. This might be an update to a later version from the server so delete what we have and retry
				print(String(format: "retry node %lld\n", node.ident))
				try? deleteNodes([node])
			}

			for (key, value) in node.tags {
				try db.reset(tagStatement)
				try db.clearBindings(tagStatement)
				try db.bindInt64(tagStatement, 1, node.ident)
				try db.bindText(tagStatement, 2, key)
				try db.bindText(tagStatement, 3, value)
				try db.step(tagStatement)
			}
#if USE_RTREE
			add(toSpatial: node)
#endif
		}
	}

	private func saveWays(_ ways: [OsmWay]) throws {
		if ways.count == 0 {
			return
		}

		let wayStatement = try db.prepare("INSERT INTO ways (ident,user,timestamp,version,changeset,uid,nodecount) VALUES (?,?,?,?,?,?,?);")
		let tagStatement = try db.prepare("INSERT INTO way_tags (ident,key,value) VALUES (?,?,?);")
		let nodeStatement = try db.prepare("INSERT INTO way_nodes (ident,node_id,node_index) VALUES (?,?,?);")

		for way in ways {
			try db.reset(wayStatement)
			try db.clearBindings(wayStatement)
			try db.bindInt64(wayStatement, 1, way.ident)
			try db.bindText(wayStatement, 2, way.user)
			try db.bindText(wayStatement, 3, way.timestamp)
			try db.bindInt32(wayStatement, 4, Int32(way.version))
			try db.bindInt64(wayStatement, 5, way.changeset)
			try db.bindInt32(wayStatement, 6, Int32(way.uid))
			try db.bindInt32(wayStatement, 7, Int32(way.nodes.count))
			while try db.step(wayStatement, hasResult: Sqlite.CONSTRAINT) {
				// tried to insert something already there. This might be an update to a later version from the server so delete what we have and retry
				print(String(format: "retry way %lld\n", way.ident))
				try? deleteWays([way])
			}

			for (key, value) in way.tags {
				try db.reset(tagStatement)
				try db.clearBindings(tagStatement)
				try db.bindInt64(tagStatement, 1, way.ident)
				try db.bindText(tagStatement, 2, key)
				try db.bindText(tagStatement, 3, value)
				try db.step(tagStatement)
			}

			var index: Int32 = 0
			for node in way.nodes {
				try db.reset(nodeStatement)
				try db.clearBindings(nodeStatement)
				try db.bindInt64(nodeStatement, 1, way.ident)
				try db.bindInt64(nodeStatement, 2, node.ident)
				try db.bindInt32(nodeStatement, 3, index)
				try db.step(nodeStatement)
				index += 1
			}
#if USE_RTREE
			add(toSpatial: way)
#endif
		}
	}

	private func saveRelations(_ relations: [OsmRelation]) throws {
		if relations.count == 0 {
			return
		}

		let baseStatement = try db.prepare("INSERT INTO relations (ident,user,timestamp,version,changeset,uid,membercount) VALUES (?,?,?,?,?,?,?);")
		let tagStatement = try db.prepare("INSERT INTO relation_tags (ident,key,value) VALUES (?,?,?);")
		let memberStatement = try db.prepare("INSERT INTO relation_members (ident,type,ref,role,member_index) VALUES (?,?,?,?,?);")

		for relation in relations {
			try db.reset(baseStatement)
			try db.clearBindings(baseStatement)
			try db.bindInt64(baseStatement, 1, relation.ident)
			try db.bindText(baseStatement, 2, relation.user)
			try db.bindText(baseStatement, 3, relation.timestamp)
			try db.bindInt32(baseStatement, 4, Int32(relation.version))
			try db.bindInt64(baseStatement, 5, relation.changeset)
			try db.bindInt32(baseStatement, 6, Int32(relation.uid))
			try db.bindInt32(baseStatement, 7, Int32(relation.members.count))
			while try db.step(baseStatement, hasResult: Sqlite.CONSTRAINT) {
				// tried to insert something already there. This might be an update to a later version from the server so delete what we have and retry
				print(String(format: "retry relation %lld\n", relation.ident))
				try? deleteRelations([relation])
			}

			for (key, value) in relation.tags {
				try db.reset(tagStatement)
				try db.clearBindings(tagStatement)
				try db.bindInt64(tagStatement, 1, relation.ident)
				try db.bindText(tagStatement, 2, key)
				try db.bindText(tagStatement, 3, value)
				try db.step(tagStatement)
			}

			var index: Int32 = 0
			for member in relation.members {
				try db.reset(memberStatement)
				try db.clearBindings(memberStatement)
				try db.bindInt64(memberStatement, 1, relation.ident)
				try db.bindText(memberStatement, 2, member.type)
				try db.bindInt64(memberStatement, 3, member.ref)
				try db.bindText(memberStatement, 4, member.role)
				try db.bindInt32(memberStatement, 5, index)
				try db.step(memberStatement)
				index += 1
			}
#if USE_RTREE
			add(toSpatial: relation)
#endif
		}
	}

	// MARK: delete

	private func deleteNodes(_ nodes: [OsmNode]) throws {
		if nodes.count == 0 {
			return
		}

		let nodeStatement = try db.prepare("DELETE from NODES where ident=?;")

		for node in nodes {
			try db.reset(nodeStatement)
			try db.clearBindings(nodeStatement)
			try db.bindInt64(nodeStatement, 1, node.ident)
			try db.step(nodeStatement)
		}
	}

	private func deleteWays(_ ways: [OsmWay]) throws {
		if ways.count == 0 {
			return
		}

		let nodeStatement = try db.prepare("DELETE from WAYS where ident=?;")

		for way in ways {
			try db.reset(nodeStatement)
			try db.clearBindings(nodeStatement)
			try db.bindInt64(nodeStatement, 1, way.ident)
			try db.step(nodeStatement)
		}
	}

	private func deleteRelations(_ relations: [OsmRelation]) throws {
		if relations.count == 0 {
			return
		}

		let relationStatement = try db.prepare("DELETE from RELATIONS where ident=?;")

		for relation in relations {
			try db.reset(relationStatement)
			try db.clearBindings(relationStatement)
			try db.bindInt64(relationStatement, 1, relation.ident)
			try db.step(relationStatement)
		}
	}

	// MARK: update

	func save(
		saveNodes: [OsmNode],
		saveWays: [OsmWay],
		saveRelations: [OsmRelation],
		deleteNodes: [OsmNode],
		deleteWays: [OsmWay],
		deleteRelations: [OsmRelation],
		isUpdate: Bool) throws
	{
#if DEBUG
#if !targetEnvironment(macCatalyst)
//		assert(dispatch_get_current_queue() == Database.dispatchQueue)
#endif
#endif

		try db.exec("BEGIN")

		do {
			if isUpdate {
				try self.deleteNodes(saveNodes)
				try self.deleteWays(saveWays)
				try self.deleteRelations(saveRelations)
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

	private func queryTagTable(_ tableName: String) throws -> [OsmIdentifier: [String: String]] {
		let query = "SELECT key,value,ident FROM \(tableName)"
		let tagStatement = try db.prepare(query)

		var list = [OsmIdentifier: [String: String]]()

		try db.reset(tagStatement)
		try db.clearBindings(tagStatement)
		while try db.step(tagStatement, hasResult: Sqlite.ROW) {
			let key = db.columnText(tagStatement, 0)
			let value = db.columnText(tagStatement, 1)
			let ident = db.columnInt64(tagStatement, 2)

			if list[ident] == nil {
				list[ident] = [:]
			}
			list[ident]![key] = value
		}

		return list
	}

	func querySqliteNodes() throws -> [OsmNode] {
		let nodeStatement = try db.prepare("SELECT ident,user,timestamp,version,changeset,uid,longitude,latitude FROM nodes;")

		let tagDict = try queryTagTable("node_tags")

		var nodes: [OsmNode] = []

		while try db.step(nodeStatement, hasResult: Sqlite.ROW) {
			let ident = db.columnInt64(nodeStatement, 0)
			let user = db.columnText(nodeStatement, 1)
			let timestamp = db.columnText(nodeStatement, 2)
			let version = db.columnInt32(nodeStatement, 3)
			let changeset = db.columnInt64(nodeStatement, 4)
			let uid = db.columnInt32(nodeStatement, 5)
			let longitude = db.columnDouble(nodeStatement, 6)
			let latitude = db.columnDouble(nodeStatement, 7)

			let tags = tagDict[ident] ?? [:]

			let node = OsmNode(
				withVersion: Int(version),
				changeset: Int64(changeset),
				user: user,
				uid: Int(uid),
				ident: ident,
				timestamp: timestamp,
				tags: tags)
			node.setLongitude(longitude, latitude: latitude, undo: nil)

			nodes.append(node)
		}

		for obj in nodes {
			obj.setConstructed()
		}

		return nodes
	}

	func querySqliteWays() throws -> [OsmWay] {
		let wayStatement = try db.prepare("SELECT ident,user,timestamp,version,changeset,uid,nodecount FROM ways")

		var ways: [OsmIdentifier: OsmWay] = [:]
		let tagDicts = try queryTagTable("way_tags")

		while try db.step(wayStatement, hasResult: Sqlite.ROW) {
			let ident = db.columnInt64(wayStatement, 0)
			let user = db.columnText(wayStatement, 1)
			let timestamp = db.columnText(wayStatement, 2)
			let version = db.columnInt32(wayStatement, 3)
			let changeset = db.columnInt64(wayStatement, 4)
			let uid = db.columnInt32(wayStatement, 5)
			let nodecount = db.columnInt32(wayStatement, 6)

			let tags = tagDicts[ident] ?? [:]

			let way = OsmWay(
				withVersion: Int(version),
				changeset: changeset,
				user: user,
				uid: Int(uid),
				ident: ident,
				timestamp: timestamp,
				tags: tags)

			let nodeRefs = [OsmIdentifier].init(repeating: -1, count: Int(nodecount))
			way.constructNodeList(nodeRefs)

			ways[way.ident] = way
		}

		try queryNodes(forWays: ways)

		return Array(ways.values)
	}

	private func queryNodes(forWays ways: [OsmIdentifier: OsmWay]) throws {
		let nodeStatement = try db.prepare("SELECT ident,node_id,node_index FROM way_nodes")

		while try db.step(nodeStatement, hasResult: Sqlite.ROW) {
			let ident = db.columnInt64(nodeStatement, 0)
			let node_id = db.columnInt64(nodeStatement, 1)
			let node_index = db.columnInt32(nodeStatement, 2)

			guard let way = ways[ident] else {
				throw SqliteError.OsmError("way referenced by node does not exist")
			}

			way.nodeRefs![Int(node_index)] = node_id
		}
	}

	func querySqliteRelations() throws -> [OsmRelation] {
		let relationStatement = try db.prepare("SELECT ident,user,timestamp,version,changeset,uid,membercount FROM relations")

		let tagsDict = try queryTagTable("relation_tags")

		var relations: [OsmIdentifier: OsmRelationBuilder] = [:]
		while try db.step(relationStatement, hasResult: Sqlite.ROW) {
			let ident = db.columnInt64(relationStatement, 0)
			let user = db.columnText(relationStatement, 1)
			let timestamp = db.columnText(relationStatement, 2)
			let version = db.columnInt32(relationStatement, 3)
			let changeset = db.columnInt64(relationStatement, 4)
			let uid = db.columnInt32(relationStatement, 5)
			let membercount = db.columnInt32(relationStatement, 6)

			let tags = tagsDict[ident] ?? [:]

			let relation = OsmRelation(
				withVersion: Int(version),
				changeset: changeset,
				user: user,
				uid: Int(uid),
				ident: ident,
				timestamp: timestamp,
				tags: tags)

			let builder = OsmRelationBuilder(with: relation, memberCount: Int(membercount))
			relations[relation.ident] = builder
		}

		// set the member objects for relations
		try queryMembers(forRelations: relations)
		for builder in relations.values {
			builder.relation.constructMembers(builder.members.map { $0! })
		}

		// build the dictionary
		return relations.values.map { $0.relation }
	}

	private func queryMembers(forRelations relations: [OsmIdentifier: OsmRelationBuilder]) throws {
		let memberStatement = try db.prepare("SELECT ident,type,ref,role,member_index FROM relation_members")

		while try db.step(memberStatement, hasResult: Sqlite.ROW) {
			let ident = db.columnInt64(memberStatement, 0)
			let type = db.columnText(memberStatement, 1)
			let ref = db.columnInt64(memberStatement, 2)
			let role = db.columnText(memberStatement, 3)
			let member_index = db.columnInt32(memberStatement, 4)

			guard let relation = relations[ident] else {
				throw SqliteError.OsmError("relation referenced by relation member does not exist")
			}
			let member = OsmMember(
				type: type,
				ref: ref,
				role: role)

			relation.members[Int(member_index)] = member
		}
	}
}
