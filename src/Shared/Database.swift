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

    class func delete(withName name: String) {
        let path = Database.databasePath(withName: name)
        unlink(path)
    }

	func SqlOk(_ result: Int32) throws {
		if result != SQLITE_OK {
			throw NSError()
		}
	}

	func SqlDone(_ result: Int32) throws {
		if result != SQLITE_DONE {
			throw NSError()
		}
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
        
		try SqlOk( sqlite3_exec(
            db,
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
			""",
            nil,
			nil,
            nil))

		try SqlOk( sqlite3_exec(
            db,
            """
				create table if not exists node_tags(\
					ident	int8			not null,\
					key		varchar(255)	not null,\
					value	varchar(255)	not null,\
					FOREIGN KEY(ident) REFERENCES nodes(ident) on delete cascade);
			""",
            nil,
			nil,
			nil))

        // ways
        
		try SqlOk( sqlite3_exec(
            db,
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
			""",
            nil,
			nil,
			nil))

		try SqlOk( sqlite3_exec(
            db,
            """
				create table if not exists way_nodes(\
					ident		int8	not null,\
					node_id		int8	not null,\
					node_index	int4	not null,\
					FOREIGN KEY(ident) REFERENCES ways(ident) on delete cascade);
			""",
            nil,
			nil,
			nil))

		try SqlOk( sqlite3_exec(
            db,
            """
				create table if not exists way_tags(\
					ident	int8			not null,\
					key		varchar(255)	not null,\
					value	varchar(255)	not null,\
					FOREIGN KEY(ident) REFERENCES ways(ident) on delete cascade);
			""",
            nil,
			nil,
			nil))

        // relations
        
		try SqlOk( sqlite3_exec(
            db,
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
			""",
            nil,
			nil,
			nil))

		try SqlOk( sqlite3_exec(
            db,
            """
				create table if not exists relation_members(\
					ident			int8			not null,\
					type			varchar[255]	not null,\
					ref				int8			not null,\
					role			varchar[255]	not null,\
					member_index	int4			not null,\
					FOREIGN KEY(ident) REFERENCES relations(ident) on delete cascade);
			""",
            nil,
			nil,
			nil))

		try SqlOk( sqlite3_exec(
            db,
            """
				create table if not exists relation_tags(\
					ident	int8			not null,\
					key		varchar(255)	not null,\
					value	varchar(255)	not null,\
					FOREIGN KEY(ident) REFERENCES relations(ident) on delete cascade);
			""",
            nil,
			nil,
			nil))

        // spatial
        
#if USE_RTREE
		try SqlOk( sqlite3_exec(
			db,
			"""
				create virtual table if not exists spatial using rtree(\
					ident	int8	primary key	not null,\
					minX	double	not null,\
					maxX	double	not null,\
					minY	double	not null,\
					maxY	double	not null\
				);
			""",
			nil,
			nil,
			nil))
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
        
        var nodeStatement: sqlite3_stmt? = nil
        var tagStatement: sqlite3_stmt? = nil
		defer {
			sqlite3_finalize(nodeStatement)
			sqlite3_finalize(tagStatement)
		}

		try SqlOk(sqlite3_prepare_v2(db, "INSERT INTO NODES (user,timestamp,version,changeset,uid,longitude,latitude,ident) VALUES (?,?,?,?,?,?,?,?);", -1, &nodeStatement, nil))
		try SqlOk(sqlite3_prepare_v2(db, "INSERT INTO node_tags (ident,key,value) VALUES (?,?,?);", -1, &tagStatement, nil))

		for node in nodes {
			try SqlOk(sqlite3_clear_bindings(nodeStatement))
			try SqlOk(sqlite3_bind_text(nodeStatement, 1, node.user, -1, nil))
			try SqlOk(sqlite3_bind_text(nodeStatement, 2, node.timestamp, -1, nil))
			try SqlOk(sqlite3_bind_int(nodeStatement, 3, Int32(node.version)))
			try SqlOk(sqlite3_bind_int64(nodeStatement, 4, node.changeset))
			try SqlOk(sqlite3_bind_int(nodeStatement, 5, Int32(node.uid)))
			try SqlOk(sqlite3_bind_double(nodeStatement, 6, node.lon))
			try SqlOk(sqlite3_bind_double(nodeStatement, 7, node.lat))
			try SqlOk(sqlite3_bind_int64(nodeStatement, 8, node.ident))

			while true {
				let rc = sqlite3_step(nodeStatement)
				if rc != SQLITE_CONSTRAINT {
					try SqlDone( rc  )
					break
				}
				// tried to insert something already there. This might be an update to a later version from the server so delete what we have and retry
				print(String(format: "retry node %lld\n", node.ident))
				try? deleteNodes([node])
			}

			for (key,value) in node.tags {
				sqlite3_reset(tagStatement)
				try SqlOk(sqlite3_clear_bindings(tagStatement))
				try SqlOk(sqlite3_bind_int64(tagStatement, 1, node.ident))
				try SqlOk(sqlite3_bind_text(tagStatement, 2, key, -1, nil))
				try SqlOk(sqlite3_bind_text(tagStatement, 3, value, -1, nil))
				let rc = sqlite3_step(tagStatement)
				try SqlDone( rc )
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
        
        var wayStatement: sqlite3_stmt? = nil
        var tagStatement: sqlite3_stmt? = nil
        var nodeStatement: sqlite3_stmt? = nil
		defer {
			sqlite3_finalize(wayStatement)
			sqlite3_finalize(tagStatement)
			sqlite3_finalize(nodeStatement)
		}

		try SqlOk(sqlite3_prepare_v2(db, "INSERT INTO ways (ident,user,timestamp,version,changeset,uid,nodecount) VALUES (?,?,?,?,?,?,?);", -1, &wayStatement, nil))
		try SqlOk(sqlite3_prepare_v2(db, "INSERT INTO way_tags (ident,key,value) VALUES (?,?,?);", -1, &tagStatement, nil))
		try SqlOk(sqlite3_prepare_v2(db, "INSERT INTO way_nodes (ident,node_id,node_index) VALUES (?,?,?);", -1, &nodeStatement, nil))

		for way in ways {
			try SqlOk(sqlite3_clear_bindings(wayStatement))
			try SqlOk(sqlite3_bind_int64(wayStatement, 1, way.ident))
			try SqlOk(sqlite3_bind_text(wayStatement, 2, way.user, -1, nil))
			try SqlOk(sqlite3_bind_text(wayStatement, 3, way.timestamp, -1, nil))
			try SqlOk(sqlite3_bind_int(wayStatement, 4, Int32(way.version)))
			try SqlOk(sqlite3_bind_int64(wayStatement, 5, way.changeset))
			try SqlOk(sqlite3_bind_int(wayStatement, 6, Int32(way.uid)))
			try SqlOk(sqlite3_bind_int(wayStatement, 7, Int32(way.nodes.count)))
			while true {
				let rc = sqlite3_step(wayStatement)
				if rc != SQLITE_CONSTRAINT {
					try SqlDone(rc)
					break
				}
				// tried to insert something already there. This might be an update to a later version from the server so delete what we have and retry
				print(String(format: "retry way %lld\n", way.ident))
				try? deleteWays([way])
			}

			for (key,value) in way.tags {
				sqlite3_reset(tagStatement)
				try SqlOk(sqlite3_clear_bindings(tagStatement))
				try SqlOk(sqlite3_bind_int64(tagStatement, 1, way.ident))
				try SqlOk(sqlite3_bind_text(tagStatement, 2, key, -1, nil))
				try SqlOk(sqlite3_bind_text(tagStatement, 3, value, -1, nil))
				rc = sqlite3_step(tagStatement)
				DbgAssert(rc == SQLITE_DONE)
			}

			var index: Int32 = 0
			for node in way.nodes {
				sqlite3_reset(nodeStatement)
				try SqlOk(sqlite3_clear_bindings(nodeStatement))
				try SqlOk(sqlite3_bind_int64(nodeStatement, 1, way.ident))
				try SqlOk(sqlite3_bind_int64(nodeStatement, 2, node.ident))
				try SqlOk(sqlite3_bind_int(nodeStatement, 3, index))
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
        
        var baseStatement: sqlite3_stmt? = nil
        var tagStatement: sqlite3_stmt? = nil
        var memberStatement: sqlite3_stmt? = nil
		defer {
			sqlite3_finalize(baseStatement)
			sqlite3_finalize(tagStatement)
			sqlite3_finalize(memberStatement)
		}

		try SqlOk(sqlite3_prepare_v2(db, "INSERT INTO relations (ident,user,timestamp,version,changeset,uid,membercount) VALUES (?,?,?,?,?,?,?);", -1, &baseStatement, nil))
		try SqlOk(sqlite3_prepare_v2(db, "INSERT INTO relation_tags (ident,key,value) VALUES (?,?,?);", -1, &tagStatement, nil))
		try SqlOk(sqlite3_prepare_v2(db, "INSERT INTO relation_members (ident,type,ref,role,member_index) VALUES (?,?,?,?,?);", -1, &memberStatement, nil))

		for relation in relations {
			try SqlOk(sqlite3_clear_bindings(baseStatement))
			try SqlOk(sqlite3_bind_int64(baseStatement, 1, relation.ident))
			try SqlOk(sqlite3_bind_text(baseStatement, 2, relation.user, -1, nil))
			try SqlOk(sqlite3_bind_text(baseStatement, 3, relation.timestamp, -1, nil))
			try SqlOk(sqlite3_bind_int(baseStatement, 4, Int32(relation.version)))
			try SqlOk(sqlite3_bind_int64(baseStatement, 5, relation.changeset))
			try SqlOk(sqlite3_bind_int(baseStatement, 6, Int32(relation.uid)))
			try SqlOk(sqlite3_bind_int(baseStatement, 7, Int32(relation.members.count)))
			while true {
				let rc = sqlite3_step(baseStatement)
				if rc != SQLITE_CONSTRAINT {
					try SqlDone(rc)
					break
				}
				// tried to insert something already there. This might be an update to a later version from the server so delete what we have and retry
				print(String(format: "retry relation %lld\n", relation.ident))
				try? deleteRelations([relation])
			}

			for (key,value) in relation.tags {
				sqlite3_reset(tagStatement)
				try SqlOk(sqlite3_clear_bindings(tagStatement))
				try SqlOk(sqlite3_bind_int64(tagStatement, 1, relation.ident))
				try SqlOk(sqlite3_bind_text(tagStatement, 2, key, -1, nil))
				try SqlOk(sqlite3_bind_text(tagStatement, 3, value, -1, nil))
				let rc = sqlite3_step(tagStatement)
				try SqlDone(rc)
			}

			var index: Int32 = 0
			for member in relation.members {
				let ref = NSNumber(value: member.ref)
				sqlite3_reset(memberStatement)
				try SqlOk(sqlite3_clear_bindings(memberStatement))
				try SqlOk(sqlite3_bind_int64(memberStatement, 1, relation.ident))
				try SqlOk(sqlite3_bind_text(memberStatement, 2, member.type, -1, nil))
				try SqlOk(sqlite3_bind_int64(memberStatement, 3, ref.int64Value))
				try SqlOk(sqlite3_bind_text(memberStatement, 4, member.role, -1, nil))
				try SqlOk(sqlite3_bind_int(memberStatement, 5, index))
				index += 1
				let rc = sqlite3_step(memberStatement)
				try SqlDone( rc )
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
        
		var nodeStatement: sqlite3_stmt? = nil
		defer {
			sqlite3_finalize(nodeStatement)
		}

		try SqlOk(sqlite3_prepare_v2(db, "DELETE from NODES where ident=?;", -1, &nodeStatement, nil))
		for node in nodes {
			sqlite3_reset(nodeStatement)
			try SqlOk(sqlite3_clear_bindings(nodeStatement))
			try SqlOk(sqlite3_bind_int64(nodeStatement, 1, node.ident))
			let rc = sqlite3_step(nodeStatement)
			try SqlDone( rc )
		}
    }

    func deleteWays(_ ways: [OsmWay]) throws {
        if ways.count == 0 {
            return
		}
        
        var nodeStatement: sqlite3_stmt? = nil
		defer {
			sqlite3_finalize(nodeStatement)
		}
		try SqlOk(sqlite3_prepare_v2(db, "DELETE from WAYS where ident=?;", -1, &nodeStatement, nil))

		for way in ways {
			sqlite3_reset(nodeStatement)
			try SqlOk(sqlite3_clear_bindings(nodeStatement))
			try SqlOk(sqlite3_bind_int64(nodeStatement, 1, way.ident))
			let rc = sqlite3_step(nodeStatement)
			try SqlDone( rc )
		}
    }

    func deleteRelations(_ relations: [OsmRelation]) throws {
		if relations.count == 0 {
            return
        }
        
        var relationStatement: sqlite3_stmt? = nil
		defer {
			sqlite3_finalize(relationStatement)
		}

		try SqlOk(sqlite3_prepare_v2(db, "DELETE from RELATIONS where ident=?;", -1, &relationStatement, nil))

		for relation in relations {
			sqlite3_reset(relationStatement)
			try SqlOk(sqlite3_clear_bindings(relationStatement))
			try SqlOk(sqlite3_bind_int64(relationStatement, 1, relation.ident))
			let rc = sqlite3_step(relationStatement)
			try SqlDone( rc )
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

		try SqlOk( sqlite3_exec(db, "BEGIN", nil, nil, nil) )

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

		var tagStatement: sqlite3_stmt? = nil
		defer {
			sqlite3_finalize(tagStatement)
		}

		let query = "SELECT key,value,ident FROM \(tableName)"
		try SqlOk(sqlite3_prepare_v2(db, query, -1, &tagStatement, nil))

		var list = [OsmIdentifier:[String:String]]()

		sqlite3_reset(tagStatement)
		try SqlOk(sqlite3_clear_bindings(tagStatement))
		while true {
			let rc = sqlite3_step(tagStatement)
			if rc == SQLITE_DONE {
				break
			}
			if rc != SQLITE_ROW {
				throw NSError()
			}
			let ckey = sqlite3_column_text(tagStatement, 0)
			let cvalue = sqlite3_column_text(tagStatement, 1)
			let ident = sqlite3_column_int64(tagStatement, 2)

			#if false
			// crashes compiler
			guard let ckey = ckey,
				  let cvalue = cvalue else
			{
				throw NSError()
			}
			#else
			if ckey == nil || cvalue == nil {
				throw NSError()
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
        var nodeStatement: sqlite3_stmt? = nil
		defer {
			sqlite3_finalize(nodeStatement)
		}

		try SqlOk(sqlite3_prepare_v2(db, "SELECT ident,user,timestamp,version,changeset,uid,longitude,latitude FROM nodes", -1, &nodeStatement, nil))

		let tagDict = try queryTagTable("node_tags")

		var nodes: [OsmIdentifier : OsmNode] = [:]
        
		while true {
			let rc = sqlite3_step(nodeStatement)
			if rc == SQLITE_DONE {
				break
			} else if rc != SQLITE_ROW {
				throw NSError()
			}
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
			else { throw NSError() }
			#else
			if user == nil || timestamp == nil {
				throw NSError()
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

		var wayStatement: sqlite3_stmt? = nil
		defer {
			sqlite3_finalize(wayStatement)
		}

        var ways: [OsmIdentifier : OsmWay] = [:]
        
		try SqlOk(sqlite3_prepare_v2(db, "SELECT ident,user,timestamp,version,changeset,uid,nodecount FROM ways", -1, &wayStatement, nil))

		let tagDicts = try queryTagTable("way_tags")


		while true {

			let rc = sqlite3_step(wayStatement)
			if rc == SQLITE_DONE {
				break
			} else if rc != SQLITE_ROW {
				throw NSError()
			}
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
				throw NSError()
			}
			#else
			if user == nil || timestamp == nil || nodecount < 0 {
				throw NSError()
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

        var nodeStatement: sqlite3_stmt? = nil
		defer {
			sqlite3_finalize(nodeStatement)
		}

		try SqlOk( sqlite3_prepare_v2(db, "SELECT ident,node_id,node_index FROM way_nodes", -1, &nodeStatement, nil) )

		while true {
			let rc = sqlite3_step(nodeStatement)
			if rc == SQLITE_DONE {
				break
			} else if rc != SQLITE_ROW {
				throw NSError()
			}
            let ident = sqlite3_column_int64(nodeStatement, 0)
            let node_id = sqlite3_column_int64(nodeStatement, 1)
            let node_index = sqlite3_column_int(nodeStatement, 2)
            
			guard let way = ways[ident] else {
				throw NSError()
			}

			way.nodeRefs![Int(node_index)] = node_id
		}
    }
    
    func querySqliteRelations() throws -> [OsmIdentifier : OsmRelation] {

		var relationStatement: sqlite3_stmt? = nil
		defer {
			sqlite3_finalize(relationStatement)
		}

		try SqlOk( sqlite3_prepare_v2(db, "SELECT ident,user,timestamp,version,changeset,uid,membercount FROM relations", -1, &relationStatement, nil) )

		let tagsDict = try queryTagTable("relation_tags")

        var relations: [OsmIdentifier : OsmRelationBuilder] = [:]

		while true {
			let rc = sqlite3_step(relationStatement)
			if rc == SQLITE_DONE {
				break
			} else if rc != SQLITE_ROW {
				throw NSError()
			}
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
				throw NSError()
			}
			#else
			if user == nil || timestamp == nil {
				throw NSError()
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
		var memberStatement: sqlite3_stmt? = nil
		defer {
			sqlite3_finalize(memberStatement)
		}

		try SqlOk( sqlite3_prepare_v2(db, "SELECT ident,type,ref,role,member_index FROM relation_members", -1, &memberStatement, nil) )

		while true {
			let rc = sqlite3_step(memberStatement)
			if rc == SQLITE_DONE {
				break
			} else if rc != SQLITE_ROW {
				throw NSError()
			}
            let ident = sqlite3_column_int64(memberStatement, 0)
            let type = sqlite3_column_text(memberStatement, 1)
            let ref = sqlite3_column_int64(memberStatement, 2)
            let role = sqlite3_column_text(memberStatement, 3)
            let member_index = sqlite3_column_int(memberStatement, 4)

			guard let relation = relations[ident] else {
				throw NSError()
			}
            let member = OsmMember(
				type: type != nil ? String(cString: type!) : nil,
				ref: ref,
				role: role != nil ? String(cString: role!) : nil)

			relation.members[Int(member_index)] = member
        }
    }
}
