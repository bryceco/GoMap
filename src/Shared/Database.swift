//
//  Database.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 9/14/14.
//  Copyright (c) 2014 Bryce Cogswell. All rights reserved.
//

import Foundation
import SQLite3

#if DEBUG && false
	let USE_RTREE = 1
#else
	let USE_RTREE = 0
#endif

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum DatabaseError: Error {
	case unlink
	case exec(String)
	case prepare(String)
	case clearBindings
	case bind
	case step
	case OsmError(String)
}

final class Database {
	private typealias sqlite3 = OpaquePointer
	private typealias sqlite3_stmt = OpaquePointer

	let path: String
	private let db: sqlite3
	
#if USE_RTREE
	private var spatialInsert: sqlite3_stmt
    private var spatialDelete: sqlite3_stmt
#endif

	static let dispatchQueue = DispatchQueue(label: "com.bryceco.gomap.database",
											 qos: .default,
											 attributes: [])

    // MARK: initialize
    
	class func databasePath(withName name: String) -> String {
		let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).map(\.path)
		let bundleName = Bundle.main.infoDictionary?["CFBundleIdentifier"] as! String
		var path = URL(fileURLWithPath: URL(fileURLWithPath: paths[0]).appendingPathComponent(bundleName).path).appendingPathComponent("data.sqlite3").path
		if name.count != 0 {
			path = path + ".\(name)"
		}
		try? FileManager.default.createDirectory(atPath: URL(fileURLWithPath: path).deletingLastPathComponent().path, withIntermediateDirectories: true, attributes: nil)
		return path
	}
    
	// return self if database can be opened
	// return nil if database doesn't exist or is corrupted
    init?(name: String) {
		path = Database.databasePath(withName: name)

		var db: sqlite3? = nil
		var rc = sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
		guard rc == SQLITE_OK,
			  let db = db
		else {
			return nil
		}
		self.db = db
		rc = sqlite3_exec(self.db, "PRAGMA foreign_keys=ON;", nil, nil, nil)
		assert(rc == SQLITE_OK)
    }

    class func delete(withName name: String) throws {
		let path = Database.databasePath(withName: name)
		if unlink(path) != 0 {
			throw DatabaseError.unlink
		}
    }

	private func SqlExec(_ command: String ) throws {
		let result = sqlite3_exec(self.db, command, nil, nil, nil)
		if result != SQLITE_OK {
			throw DatabaseError.exec(command)
		}
	}
	private func SqlPrepare(_ command: String ) throws -> sqlite3_stmt {
		var statement: sqlite3_stmt? = nil
		let result = sqlite3_prepare_v2(db, command, -1, &statement, nil)
		if result != SQLITE_OK || statement == nil {
			throw DatabaseError.prepare(command)
		}
		return statement!
	}
	private func SqlClearBindings(_ statement: sqlite3_stmt ) throws {
		if sqlite3_clear_bindings(statement) != SQLITE_OK {
			throw DatabaseError.clearBindings
		}
	}
	private func SqlReset(_ statement: sqlite3_stmt ) throws {
		if sqlite3_reset(statement) != SQLITE_OK {
			throw DatabaseError.clearBindings
		}
	}
	private func SqlBindText(_ statement: sqlite3_stmt, _ index: Int32, _ value: String?) throws {
		if sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT) != SQLITE_OK {
			throw DatabaseError.bind
		}
	}
	private func SqlBindInt32(_ statement: sqlite3_stmt, _ index: Int32, _ value: Int32) throws {
		if sqlite3_bind_int(statement, index, value) != SQLITE_OK {
			throw DatabaseError.bind
		}
	}
	private func SqlBindInt64(_ statement: sqlite3_stmt, _ index: Int32, _ value: Int64) throws {
		if sqlite3_bind_int64(statement, index, value) != SQLITE_OK {
			throw DatabaseError.bind
		}
	}
	private func SqlBindDouble(_ statement: sqlite3_stmt, _ index: Int32, _ value: Double) throws {
		if sqlite3_bind_double(statement, index, value) != SQLITE_OK {
			throw DatabaseError.bind
		}
	}
	private func SqlStep(_ statement: sqlite3_stmt, hasResult: Int32?) throws -> Bool {
		let rc = sqlite3_step(statement)
		if rc == SQLITE_DONE {
			return false
		}
		if let hasResult = hasResult,
		   rc == hasResult
		{
			return true
		}
		throw DatabaseError.step
	}
	private func SqlStep(_ statement: sqlite3_stmt) throws {
		_ = try SqlStep(statement, hasResult: nil)
	}

	func close() {
#if USE_RTREE
            if spatialInsert != nil {
                sqlite3_finalize(spatialInsert)
            }
            if spatialDelete != nil {
                sqlite3_finalize(spatialDelete)
            }
#endif
		let rc = sqlite3_close(db)
		if rc != SQLITE_OK {
			print("Database could not close: \(sqlite3_errmsg(db)!)\n")
		}
    }
    
	deinit {
		close()
    }
    
    func dropTables() {
		var rc: Int32 = 0
        rc |= sqlite3_exec(db, "drop table node_tags;", nil, nil, nil)
        rc |= sqlite3_exec(db, "drop table nodes;", nil, nil, nil)
        rc |= sqlite3_exec(db, "drop table way_tags;", nil, nil, nil)
        rc |= sqlite3_exec(db, "drop table way_nodes;", nil, nil, nil)
        rc |= sqlite3_exec(db, "drop table ways;", nil, nil, nil)
        rc |= sqlite3_exec(db, "drop table relation_tags;", nil, nil, nil)
        rc |= sqlite3_exec(db, "drop table relation_members;", nil, nil, nil)
        rc |= sqlite3_exec(db, "drop table relations;", nil, nil, nil)
#if USE_RTREE
		rc |= sqlite3_exec(db, "drop table spatial;", 0, 0, 0)
#endif
        rc |= sqlite3_exec(db, "vacuum;", nil, nil, nil) // compact database
		if rc != 0 {
			DLog("database dropTables error")
		}
	}
    
    func createTables() throws {

        // nodes
        
		try SqlExec(
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

		try SqlExec(
            """
				create table if not exists node_tags(\
					ident	int8			not null,\
					key		varchar(255)	not null,\
					value	varchar(255)	not null,\
					FOREIGN KEY(ident) REFERENCES nodes(ident) on delete cascade);
			""")

        // ways
        
		try SqlExec(
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

		try SqlExec(
            """
				create table if not exists way_nodes(\
					ident		int8	not null,\
					node_id		int8	not null,\
					node_index	int4	not null,\
					FOREIGN KEY(ident) REFERENCES ways(ident) on delete cascade);
			""")

		try SqlExec(
            """
				create table if not exists way_tags(\
					ident	int8			not null,\
					key		varchar(255)	not null,\
					value	varchar(255)	not null,\
					FOREIGN KEY(ident) REFERENCES ways(ident) on delete cascade);
			""")

        // relations
        
		try SqlExec(
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

		try SqlExec(
            """
				create table if not exists relation_members(\
					ident			int8			not null,\
					type			varchar[255]	not null,\
					ref				int8			not null,\
					role			varchar[255]	not null,\
					member_index	int4			not null,\
					FOREIGN KEY(ident) REFERENCES relations(ident) on delete cascade);
			""")

		try SqlExec(
            """
				create table if not exists relation_tags(\
					ident	int8			not null,\
					key		varchar(255)	not null,\
					value	varchar(255)	not null,\
					FOREIGN KEY(ident) REFERENCES relations(ident) on delete cascade);
			""")

        // spatial
        
#if USE_RTREE
		try SqlExec(
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
    func deleteSpatial(_ object: OsmBaseObject?) -> Bool {
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
    
    func add(toSpatial object: OsmBaseObject?) throws {
        if spatialInsert == nil {
			DbgOk( sqlite3_prepare_v2(db, "INSERT INTO spatial (ident,minX, maxX,minY, maxY) VALUES (?,?,?,?,?);", -1, &spatialInsert, nil) )
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
				SqlOk( rc, SQLITE_DONE )
				break
			}
            // tried to insert something already there. This might be an update to a later version from the server so delete what we have and retry
			try? deleteSpatial(object)
        }
    }
#endif
    
    // MARK: save
    
    func saveNodes(_ nodes: [OsmNode]) throws {

        if nodes.count == 0 {
            return
        }
        
		let nodeStatement = try SqlPrepare("INSERT INTO NODES (user,timestamp,version,changeset,uid,longitude,latitude,ident) VALUES (?,?,?,?,?,?,?,?);")
		let tagStatement = try SqlPrepare("INSERT INTO node_tags (ident,key,value) VALUES (?,?,?);")
		defer {
			sqlite3_finalize(nodeStatement)
			sqlite3_finalize(tagStatement)
		}

		for node in nodes {
			try SqlReset(nodeStatement)
			try SqlClearBindings(nodeStatement)
			try SqlBindText(nodeStatement, 1, node.user)
			try SqlBindText(nodeStatement, 2, node.timestamp)
			try SqlBindInt32(nodeStatement, 3, Int32(node.version))
			try SqlBindInt64(nodeStatement, 4, node.changeset)
			try SqlBindInt32(nodeStatement, 5, Int32(node.uid))
			try SqlBindDouble(nodeStatement, 6, node.lon)
			try SqlBindDouble(nodeStatement, 7, node.lat)
			try SqlBindInt64(nodeStatement, 8, node.ident)

			while try SqlStep(nodeStatement, hasResult: SQLITE_CONSTRAINT) {
				// tried to insert something already there. This might be an update to a later version from the server so delete what we have and retry
				print(String(format: "retry node %lld\n", node.ident))
				try? deleteNodes([node])
			}

			for (key,value) in node.tags {
				try SqlReset(tagStatement)
				try SqlClearBindings(tagStatement)
				try SqlBindInt64(tagStatement, 1, node.ident)
				try SqlBindText(tagStatement, 2, key)
				try SqlBindText(tagStatement, 3, value)
				try SqlStep(tagStatement)
			}
#if USE_RTREE
			add(toSpatial: node)
#endif
		}
    }
    
    func saveWays(_ ways: [OsmWay]) throws {
		var rc = SQLITE_OK
        
        if ways.count == 0 {
            return
        }
        
        let wayStatement = try SqlPrepare("INSERT INTO ways (ident,user,timestamp,version,changeset,uid,nodecount) VALUES (?,?,?,?,?,?,?);")
        let tagStatement = try SqlPrepare("INSERT INTO way_tags (ident,key,value) VALUES (?,?,?);")
		let nodeStatement = try SqlPrepare("INSERT INTO way_nodes (ident,node_id,node_index) VALUES (?,?,?);")
		defer {
			sqlite3_finalize(wayStatement)
			sqlite3_finalize(tagStatement)
			sqlite3_finalize(nodeStatement)
		}
		for way in ways {
			try SqlReset(wayStatement)
			try SqlClearBindings(wayStatement)
			try SqlBindInt64(wayStatement, 1, way.ident)
			try SqlBindText(wayStatement, 2, way.user)
			try SqlBindText(wayStatement, 3, way.timestamp)
			try SqlBindInt32(wayStatement, 4, Int32(way.version))
			try SqlBindInt64(wayStatement, 5, way.changeset)
			try SqlBindInt32(wayStatement, 6, Int32(way.uid))
			try SqlBindInt32(wayStatement, 7, Int32(way.nodes.count))
			while try SqlStep(wayStatement, hasResult: SQLITE_CONSTRAINT) {
				// tried to insert something already there. This might be an update to a later version from the server so delete what we have and retry
				print(String(format: "retry way %lld\n", way.ident))
				try? deleteWays([way])
			}

			for (key,value) in way.tags {
				try SqlReset(tagStatement)
				try SqlClearBindings(tagStatement)
				try SqlBindInt64(tagStatement, 1, way.ident)
				try SqlBindText(tagStatement, 2, key)
				try SqlBindText(tagStatement, 3, value)
				rc = sqlite3_step(tagStatement)
				DbgAssert(rc == SQLITE_DONE)
			}

			var index: Int32 = 0
			for node in way.nodes {
				try SqlReset(nodeStatement)
				try SqlClearBindings(nodeStatement)
				try SqlBindInt64(nodeStatement, 1, way.ident)
				try SqlBindInt64(nodeStatement, 2, node.ident)
				try SqlBindInt32(nodeStatement, 3, index)
				index += 1
				rc = sqlite3_step(nodeStatement)
				DbgAssert(rc == SQLITE_DONE)
			}
#if USE_RTREE
			add(toSpatial: way)
#endif
		}
    }
    
    func saveRelations(_ relations: [OsmRelation]) throws {
        if relations.count == 0 {
            return
        }
        
		let baseStatement = try SqlPrepare("INSERT INTO relations (ident,user,timestamp,version,changeset,uid,membercount) VALUES (?,?,?,?,?,?,?);")
		let tagStatement = try SqlPrepare("INSERT INTO relation_tags (ident,key,value) VALUES (?,?,?);")
        let memberStatement = try SqlPrepare("INSERT INTO relation_members (ident,type,ref,role,member_index) VALUES (?,?,?,?,?);")
		defer {
			sqlite3_finalize(baseStatement)
			sqlite3_finalize(tagStatement)
			sqlite3_finalize(memberStatement)
		}

		for relation in relations {
			try SqlReset(baseStatement)
			try SqlClearBindings(baseStatement)
			try SqlBindInt64(baseStatement, 1, relation.ident)
			try SqlBindText(baseStatement, 2, relation.user)
			try SqlBindText(baseStatement, 3, relation.timestamp)
			try SqlBindInt32(baseStatement, 4, Int32(relation.version))
			try SqlBindInt64(baseStatement, 5, relation.changeset)
			try SqlBindInt32(baseStatement, 6, Int32(relation.uid))
			try SqlBindInt32(baseStatement, 7, Int32(relation.members.count))
			while try SqlStep(baseStatement, hasResult: SQLITE_CONSTRAINT) {
				// tried to insert something already there. This might be an update to a later version from the server so delete what we have and retry
				print(String(format: "retry relation %lld\n", relation.ident))
				try? deleteRelations([relation])
			}

			for (key,value) in relation.tags {
				try SqlReset(tagStatement)
				try SqlClearBindings(tagStatement)
				try SqlBindInt64(tagStatement, 1, relation.ident)
				try SqlBindText(tagStatement, 2, key)
				try SqlBindText(tagStatement, 3, value)
				try SqlStep(tagStatement)
			}

			var index: Int32 = 0
			for member in relation.members {
				let ref = NSNumber(value: member.ref)
				sqlite3_reset(memberStatement)
				try SqlClearBindings(memberStatement)
				try SqlBindInt64(memberStatement, 1, relation.ident)
				try SqlBindText(memberStatement, 2, member.type)
				try SqlBindInt64(memberStatement, 3, ref.int64Value)
				try SqlBindText(memberStatement, 4, member.role)
				try SqlBindInt32(memberStatement, 5, index)
				index += 1
				try SqlStep(memberStatement)
			}
#if USE_RTREE
			add(toSpatial: relation)
#endif
		}
    }
    
    // MARK: delete

    func deleteNodes(_ nodes: [OsmNode]) throws {
		if nodes.count == 0 {
            return
        }
        
		let nodeStatement = try SqlPrepare("DELETE from NODES where ident=?;")
		defer {
			sqlite3_finalize(nodeStatement)
		}

		for node in nodes {
			try SqlReset(nodeStatement)
			try SqlClearBindings(nodeStatement)
			try SqlBindInt64(nodeStatement, 1, node.ident)
			try SqlStep(nodeStatement)
		}
    }

    func deleteWays(_ ways: [OsmWay]) throws {
        if ways.count == 0 {
            return
		}
        
		let nodeStatement = try SqlPrepare("DELETE from WAYS where ident=?;")
		defer {
			sqlite3_finalize(nodeStatement)
		}

		for way in ways {
			try SqlReset(nodeStatement)
			try SqlClearBindings(nodeStatement)
			try SqlBindInt64(nodeStatement, 1, way.ident)
			try SqlStep(nodeStatement)
		}
    }

    func deleteRelations(_ relations: [OsmRelation]) throws {
		if relations.count == 0 {
            return
        }
        
		let relationStatement = try SqlPrepare("DELETE from RELATIONS where ident=?;")
		defer {
			sqlite3_finalize(relationStatement)
		}

		for relation in relations {
			try SqlReset(relationStatement)
			try SqlClearBindings(relationStatement)
			try SqlBindInt64(relationStatement, 1, relation.ident)
			try SqlStep(relationStatement)
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
        isUpdate: Bool
			) throws
	{
#if false && DEBUG
		assert(dispatch_get_current_queue() == Database.dispatchQueue)
#endif

		try SqlExec("BEGIN")

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
			sqlite3_exec(db, "COMMIT", nil, nil, nil)
		} catch {
			sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
			throw error
		}
    }
    
    // MARK: query
    
	func queryTagTable(_ tableName: String) throws -> [OsmIdentifier:[String:String]] {

		let query = "SELECT key,value,ident FROM \(tableName)"
		let tagStatement = try SqlPrepare(query)
		defer {
			sqlite3_finalize(tagStatement)
		}

		var list = [OsmIdentifier:[String:String]]()

		try SqlReset(tagStatement)
		try SqlClearBindings(tagStatement)
		while try SqlStep(tagStatement, hasResult: SQLITE_ROW) {
			let ckey = sqlite3_column_text(tagStatement, 0)
			let cvalue = sqlite3_column_text(tagStatement, 1)
			let ident = sqlite3_column_int64(tagStatement, 2)

			#if false
			// crashes compiler
			guard let ckey = ckey,
				  let cvalue = cvalue else
			{
				throw DatabaseError.OsmError("key or value in tag is empty")
			}
			#else
			if ckey == nil || cvalue == nil {
				throw DatabaseError.OsmError("key or value in tag is empty")
			}
			#endif

			let key = String(cString: ckey!)
			let value = String(cString: cvalue!)

			if list[ident] == nil {
				list[ident] = [:]
			}
			list[ident]![key] = value
		}

		return list
    }

	func querySqliteNodes() throws -> [OsmIdentifier : OsmNode] {
		let nodeStatement = try SqlPrepare("SELECT ident,user,timestamp,version,changeset,uid,longitude,latitude FROM nodes;")
		defer {
			sqlite3_finalize(nodeStatement)
		}

		let tagDict = try queryTagTable("node_tags")

		var nodes: [OsmIdentifier : OsmNode] = [:]
        
		while try SqlStep(nodeStatement, hasResult: SQLITE_ROW) {
			let ident = sqlite3_column_int64(nodeStatement, 0)
            let user = sqlite3_column_text(nodeStatement, 1)
            let timestamp = sqlite3_column_text(nodeStatement, 2)
            let version = sqlite3_column_int(nodeStatement, 3)
            let changeset = sqlite3_column_int64(nodeStatement, 4)
			let uid = sqlite3_column_int(nodeStatement, 5)
            let longitude = sqlite3_column_double(nodeStatement, 6)
            let latitude = sqlite3_column_double(nodeStatement, 7)

			#if false
			// crashes compiler
			guard let user = user,
				  let timestamp = timestamp
			else {
				throw DatabaseError.OsmError("user or timestamp is empty")
			}
			#else
			if user == nil || timestamp == nil {
				throw DatabaseError.OsmError("user or timestamp is empty")
			}
			#endif

			let tags = tagDict[ident ] ?? [:]

			let node = OsmNode(
				withVersion: Int(version),
				changeset: Int64(changeset),
                user: String(cString: user!),
				uid: Int(uid),
                ident: ident,
                timestamp: String(cString: timestamp!),
				tags: tags)
            node.setLongitude(longitude, latitude: latitude, undo: nil)

            nodes[node.ident] = node
		}

		for (_,obj) in nodes {
			obj.setConstructed()
		}

		return nodes
	}
    
    func querySqliteWays() throws -> [OsmIdentifier : OsmWay] {

		let wayStatement = try SqlPrepare("SELECT ident,user,timestamp,version,changeset,uid,nodecount FROM ways")
		defer {
			sqlite3_finalize(wayStatement)
		}

		var ways: [OsmIdentifier : OsmWay] = [:]
		let tagDicts = try queryTagTable("way_tags")

		while try SqlStep(wayStatement, hasResult: SQLITE_ROW) {
			let ident = sqlite3_column_int64(wayStatement, 0)
            let user = sqlite3_column_text(wayStatement, 1)
            let timestamp = sqlite3_column_text(wayStatement, 2)
            let version = sqlite3_column_int(wayStatement, 3)
            let changeset = sqlite3_column_int64(wayStatement, 4)
			let uid = sqlite3_column_int(wayStatement, 5)
            let nodecount = sqlite3_column_int(wayStatement, 6)

			#if false
			// crashes the compiler
			guard let user = user,
				  let timestamp = timestamp,
				  nodecount >= 0
			else {
				throw DatabaseError.OsmError("user, timestamp or nodecount is empty")
			}
			#else
			if user == nil || timestamp == nil || nodecount < 0 {
				throw DatabaseError.OsmError("user, timestamp or nodecount is empty")
			}
			#endif

			let tags = tagDicts[ident] ?? [:]
            
			let way = OsmWay(
				withVersion: Int(version),
                changeset: changeset,
				user: String(cString: user!),
				uid: Int(uid),
                ident: ident,
                timestamp: String(cString: timestamp!),
				tags: tags)

			let nodeRefs = [NSNumber].init(repeating: NSNumber(value: -1), count: Int(nodecount))
            way.constructNodeList(nodeRefs)

			ways[way.ident] = way
		}

		try queryNodes(forWays: ways)

		return ways
    }
    
    func queryNodes(forWays ways: [OsmIdentifier : OsmWay]) throws {

		let nodeStatement = try SqlPrepare("SELECT ident,node_id,node_index FROM way_nodes")
		defer {
			sqlite3_finalize(nodeStatement)
		}

		while try SqlStep(nodeStatement, hasResult: SQLITE_ROW) {
			let ident = sqlite3_column_int64(nodeStatement, 0)
			let node_id = sqlite3_column_int64(nodeStatement, 1)
			let node_index = sqlite3_column_int(nodeStatement, 2)
            
			guard let way = ways[ident] else {
				throw DatabaseError.OsmError("way referenced by node does not exist")
			}

			way.nodeRefs![Int(node_index)] = node_id
		}
    }
    
    func querySqliteRelations() throws -> [OsmIdentifier : OsmRelation] {

		let relationStatement = try SqlPrepare("SELECT ident,user,timestamp,version,changeset,uid,membercount FROM relations")
		defer {
			sqlite3_finalize(relationStatement)
		}

		let tagsDict = try queryTagTable("relation_tags")

		var relations: [OsmIdentifier : OsmRelationBuilder] = [:]
		while try SqlStep(relationStatement, hasResult: SQLITE_ROW) {
            let ident = sqlite3_column_int64(relationStatement, 0)
            let user = sqlite3_column_text(relationStatement, 1)
            let timestamp = sqlite3_column_text(relationStatement, 2)
            let version = sqlite3_column_int(relationStatement, 3)
            let changeset = sqlite3_column_int64(relationStatement, 4)
            let uid = sqlite3_column_int(relationStatement, 5)
            let membercount = sqlite3_column_int(relationStatement, 6)

			#if false
			// crashes compiler
			guard let user = user,
				  let timestamp = timestamp
			else {
				throw DatabaseError.OsmError("user or timestamp is empty")
			}
			#else
			if user == nil || timestamp == nil {
				throw DatabaseError.OsmError("user or timestamp is empty")
			}
			#endif

			let tags = tagsDict[ ident ] ?? [:]

			let relation = OsmRelation(
				withVersion: Int(version),
                changeset: changeset,
                user: String(cString: user!),
				uid: Int(uid),
                ident: ident,
                timestamp: String(cString: timestamp!),
				tags: tags)

			let builder = OsmRelationBuilder(with: relation, memberCount: Int(membercount))
			relations[relation.ident] = builder
		}

		try queryMembers(forRelations: relations)

		return Dictionary<OsmIdentifier,OsmRelation>( uniqueKeysWithValues: zip(relations.keys, relations.values.map({ $0.relation })) )
	}
    
    func queryMembers(forRelations relations: [OsmIdentifier : OsmRelationBuilder]) throws {
		let memberStatement = try SqlPrepare("SELECT ident,type,ref,role,member_index FROM relation_members")
		defer {
			sqlite3_finalize(memberStatement)
		}

		while try SqlStep(memberStatement, hasResult: SQLITE_ROW) {
			let ident = sqlite3_column_int64(memberStatement, 0)
            let type = sqlite3_column_text(memberStatement, 1)
            let ref = sqlite3_column_int64(memberStatement, 2)
            let role = sqlite3_column_text(memberStatement, 3)
            let member_index = sqlite3_column_int(memberStatement, 4)

			guard let relation = relations[ident] else {
				throw DatabaseError.OsmError("relation referenced by relation member does not exist")
			}
			let member = OsmMember(
				type: type != nil ? String(cString: type!) : nil,
				ref: ref,
				role: role != nil ? String(cString: role!) : nil)

			relation.members[Int(member_index)] = member
        }
    }
}
