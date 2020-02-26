//
//  Database.m
//  Go Map!!
//
//  Created by Bryce Cogswell on 9/14/14.
//  Copyright (c) 2014 Bryce Cogswell. All rights reserved.
//

#import <sqlite3.h>

#import "DLog.h"
#import "Database.h"
#import "OsmMember.h"


#define DoAssert(condition)	\
if (!(condition)) {		\
[[NSAssertionHandler currentHandler] handleFailureInMethod:_cmd object:self file:[NSString stringWithUTF8String:__FILE__] lineNumber:__LINE__ description:@"SQL error: %s",sqlite3_errmsg(_db)]; \
} else (void)0

#define SqlCheck(e)	DoAssert((rc=(e)) == SQLITE_OK)



#if DEBUG && 0
#define USE_RTREE	1
#else
#define USE_RTREE	0
#endif


@implementation Database

#pragma mark initialize

+(NSString *)databasePathWithName:(NSString *)name
{
	NSArray *paths = NSSearchPathForDirectoriesInDomains( NSCachesDirectory, NSUserDomainMask, YES );
	if ( [paths count] ) {
		NSString * bundleName = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleIdentifier"];
		NSString * path = [[[paths objectAtIndex:0]
							stringByAppendingPathComponent:bundleName]
						   stringByAppendingPathComponent:@"data.sqlite3"];
		if ( name.length ) {
			path = [path stringByAppendingFormat:@".%@",name];
		}
		[[NSFileManager defaultManager] createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:NULL error:NULL];
//		DLog(@"sql = %@",path);
		return path;
	}
	return nil;
}

-(instancetype)initWithName:(NSString *)name
{
	self = [super init];
	if ( self ) {
		_path = [Database databasePathWithName:name];
		int rc = sqlite3_open_v2( _path.UTF8String, &_db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, NULL );
		if ( rc == SQLITE_OK ) {
			rc = sqlite3_exec(_db, "PRAGMA foreign_keys=ON;", NULL, NULL, NULL );
			assert( rc == SQLITE_OK );
//			rc = sqlite3_exec(_db, "PRAGMA journal_mode=WAL;", NULL, NULL, NULL );
//			assert( rc == SQLITE_OK );
		} else {
			_db = NULL;
		}
	}
	return self;
}

-(instancetype)init
{
	return [self initWithName:nil];
}

+(dispatch_queue_t)dispatchQueue
{
	static dispatch_queue_t _dispatchQueue;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		dispatch_queue_attr_t attr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_DEFAULT, 0);
		_dispatchQueue = dispatch_queue_create("com.bryceco.gomap.database", attr );
	});
	return _dispatchQueue;
}

+(void)deleteDatabaseWithName:(NSString *)name
{
	NSString * path = [Database databasePathWithName:name];
	unlink( path.UTF8String );
}

-(NSString *)path
{
	return _path;
}

-(void)dealloc
{
#if USE_RTREE
	if ( _spatialInsert ) {
		sqlite3_finalize(_spatialInsert);
	}
	if ( _spatialDelete ) {
		sqlite3_finalize(_spatialDelete);
	}
#endif
	if ( _db ) {
		int rc = sqlite3_close(_db);
		if ( rc != SQLITE_OK ) {
			NSLog(@"Database could not close: %s\n", sqlite3_errmsg(_db) );
		}
	}
}

-(void)dropTables
{
	int rc = 0;
	rc |= sqlite3_exec(_db, "drop table node_tags;",			0, 0, 0 );
	rc |= sqlite3_exec(_db, "drop table nodes;",				0, 0, 0 );
	rc |= sqlite3_exec(_db, "drop table way_tags;",			0, 0, 0 );
	rc |= sqlite3_exec(_db, "drop table way_nodes;",			0, 0, 0 );
	rc |= sqlite3_exec(_db, "drop table ways;",				0, 0, 0 );
	rc |= sqlite3_exec(_db, "drop table relation_tags;",		0, 0, 0 );
	rc |= sqlite3_exec(_db, "drop table relation_members;",	0, 0, 0 );
	rc |= sqlite3_exec(_db, "drop table relations;",			0, 0, 0 );
#if USE_RTREE
	rc |= sqlite3_exec(_db, "drop table spatial;",			0, 0, 0 );
#endif
	rc |= sqlite3_exec(_db, "vacuum;",						0, 0, 0 );	// compact database
	(void)rc;
}

-(void)createTables
{
	int rc;

	// nodes

	rc = sqlite3_exec(_db, "CREATE TABLE IF NOT EXISTS nodes("
					  "	IDENT		INT8	unique PRIMARY KEY	NOT NULL,"
					  "	USER        varchar(255)		NOT NULL,"
					  "	TIMESTAMP   varchar(255)		NOT NULL,"
					  "	VERSION     INT					NOT NULL,"
					  "	CHANGESET   INT8				NOT NULL,"
					  "	UID         INT					NOT NULL,"
					  "	longitude   real				NOT NULL,"
					  "	latitude	real				NOT NULL"
					  ");",
					  0, 0, 0);
	DbgAssert(rc == SQLITE_OK);

	rc = sqlite3_exec(_db, "create table if not exists node_tags("
					  "ident	int8			not null,"
					  "key		varchar(255)	not null,"
					  "value	varchar(255)	not null,"
					  "FOREIGN KEY(ident) REFERENCES nodes(ident) on delete cascade);",
					  0, 0, 0);
	DbgAssert(rc == SQLITE_OK);

	// ways

	rc = sqlite3_exec(_db, "CREATE TABLE IF NOT EXISTS ways("
					  "	IDENT		INT8	unique PRIMARY KEY	NOT NULL,"
					  "	USER        varchar(255)		NOT NULL,"
					  "	TIMESTAMP   varchar(255)		NOT NULL,"
					  "	VERSION     INT					NOT NULL,"
					  "	CHANGESET   INT8				NOT NULL,"
					  "	UID         INT					NOT NULL,"
					  "	nodecount   INT					NOT NULL"
					  ");",
					  0, 0, 0);
	DbgAssert(rc == SQLITE_OK);

	rc = sqlite3_exec(_db, "create table if not exists way_nodes("
					  "ident		int8	not null,"
					  "node_id		int8	not null,"
					  "node_index	int4	not null,"
					  "FOREIGN KEY(ident) REFERENCES ways(ident) on delete cascade);",
					  0, 0, 0);
	DbgAssert(rc == SQLITE_OK);

	rc = sqlite3_exec(_db, "create table if not exists way_tags("
					  "ident	int8			not null,"
					  "key		varchar(255)	not null,"
					  "value	varchar(255)	not null,"
					  "FOREIGN KEY(ident) REFERENCES ways(ident) on delete cascade);",
					  0, 0, 0);
	DbgAssert(rc == SQLITE_OK);

	// relations

	rc = sqlite3_exec(_db, "CREATE TABLE IF NOT EXISTS relations("
					  "	IDENT		INT8	unique PRIMARY KEY	NOT NULL,"
					  "	USER        varchar(255)		NOT NULL,"
					  "	TIMESTAMP   varchar(255)		NOT NULL,"
					  "	VERSION     INT					NOT NULL,"
					  "	CHANGESET   INT8				NOT NULL,"
					  "	UID         INT					NOT NULL,"
					  "	membercount INT					NOT NULL"
					  ");",
					  0, 0, 0);
	DbgAssert(rc == SQLITE_OK);

	rc = sqlite3_exec(_db, "create table if not exists relation_members("
					  "ident		int8			not null,"
					  "type			varchar[255]	not null,"
					  "ref			int8			not null,"
					  "role			varchar[255]	not null,"
					  "member_index	int4			not null,"
					  "FOREIGN KEY(ident) REFERENCES relations(ident) on delete cascade);",
					  0, 0, 0);
	DbgAssert(rc == SQLITE_OK);

	rc = sqlite3_exec(_db, "create table if not exists relation_tags("
					  "ident	int8			not null,"
					  "key		varchar(255)	not null,"
					  "value	varchar(255)	not null,"
					  "FOREIGN KEY(ident) REFERENCES relations(ident) on delete cascade);",
					  0, 0, 0);
	DbgAssert(rc == SQLITE_OK);

	// spatial

#if USE_RTREE
	rc = sqlite3_exec(_db, "create virtual table if not exists spatial using rtree("
					  "ident	int8		primary key	not null,"
					  "minX		double		not null,"
					  "maxX		double		not null,"
					  "minY		double		not null,"
					  "maxY		double		not null"
					  ");",
					  0, 0, 0);
	DbgAssert(rc == SQLITE_OK);
#endif
}


#pragma mark spatial

#if USE_RTREE
-(BOOL)deleteSpatial:(OsmBaseObject *)object
{
	int rc;
	if ( _spatialDelete == NULL ) {
		rc = sqlite3_prepare_v2( _db, "INSERT INTO spatial (ident) VALUES (?,?);", -1, &_spatialDelete, nil );
		if ( rc != SQLITE_OK ) {
			DbgAssert(NO);
			return NO;
		}
	}

	sqlite3_reset(_spatialDelete);
	SqlCheck( sqlite3_clear_bindings(_spatialDelete) );
	SqlCheck( sqlite3_bind_int64(_spatialDelete, 1, TaggedObjectIdent(object)));
	rc = sqlite3_step(_spatialDelete);
	return rc == SQLITE_DONE;
}

-(BOOL)addToSpatial:(OsmBaseObject *)object
{
	int rc;
	if ( _spatialInsert == NULL ) {
		rc = sqlite3_prepare_v2( _db, "INSERT INTO spatial (ident,minX, maxX,minY, maxY) VALUES (?,?,?,?,?);", -1, &_spatialInsert, nil );
		if ( rc != SQLITE_OK ) {
			DbgAssert(NO);
			return NO;
		}
	}

	OSMRect bbox = object.boundingBox;
	sqlite3_reset(_spatialInsert);
	SqlCheck( sqlite3_clear_bindings(_spatialInsert) );
	SqlCheck( sqlite3_bind_int64(_spatialInsert,	1, TaggedObjectIdent(object)));
	SqlCheck( sqlite3_bind_double(_spatialInsert,	2, bbox.origin.x));
	SqlCheck( sqlite3_bind_double(_spatialInsert,	3, bbox.origin.x+bbox.size.width));
	SqlCheck( sqlite3_bind_double(_spatialInsert,	4, bbox.origin.y));
	SqlCheck( sqlite3_bind_double(_spatialInsert,	5, bbox.origin.y+bbox.size.height));
retry:
	rc = sqlite3_step(_spatialInsert);
	if ( rc == SQLITE_CONSTRAINT ) {
		// tried to insert something already there. This might be an update to a later version from the server so delete what we have and retry
		[self deleteSpatial:object];
		goto retry;
	}

	DbgAssert(rc == SQLITE_DONE);
	return rc == SQLITE_DONE;
}
#endif

#pragma mark save

-(BOOL)saveNodes:(NSArray<OsmNode *> *)nodes
{
	__block int rc = SQLITE_OK;

	if ( nodes.count == 0 )
		return YES;

	sqlite3_stmt * nodeStatement = NULL;
	sqlite3_stmt * tagStatement = NULL;

	@try {
		
		SqlCheck( sqlite3_prepare_v2( _db, "INSERT INTO NODES (user,timestamp,version,changeset,uid,longitude,latitude,ident) VALUES (?,?,?,?,?,?,?,?);", -1, &nodeStatement, nil ));
		SqlCheck( sqlite3_prepare_v2( _db, "INSERT INTO node_tags (ident,key,value) VALUES (?,?,?);", -1, &tagStatement, nil ));

		for ( OsmNode * node in nodes ) {
		retry:
			sqlite3_reset(nodeStatement);
			SqlCheck( sqlite3_clear_bindings(nodeStatement));
			SqlCheck( sqlite3_bind_text(nodeStatement,		1, node.user.UTF8String, -1, NULL));
			SqlCheck( sqlite3_bind_text(nodeStatement,		2, node.timestamp.UTF8String, -1, NULL));
			SqlCheck( sqlite3_bind_int(nodeStatement,		3, node.version));
			SqlCheck( sqlite3_bind_int64(nodeStatement,		4, node.changeset));
			SqlCheck( sqlite3_bind_int(nodeStatement,		5, node.uid));
			SqlCheck( sqlite3_bind_double(nodeStatement,	6, node.lon));
			SqlCheck( sqlite3_bind_double(nodeStatement,	7, node.lat));
			SqlCheck( sqlite3_bind_int64(nodeStatement,		8, node.ident.longLongValue));

			rc = sqlite3_step(nodeStatement);
			if ( rc == SQLITE_CONSTRAINT ) {
				// tried to insert something already there. This might be an update to a later version from the server so delete what we have and retry
				NSLog(@"retry node %@\n",node.ident);
				[self deleteNodes:@[node]];
				goto retry;
			}
			if ( rc != SQLITE_DONE ) {
				DbgAssert(NO);
				continue;
			}

			[node.tags enumerateKeysAndObjectsUsingBlock:^(NSString * key, NSString * value, BOOL *stop) {
				sqlite3_reset(tagStatement);
				SqlCheck( sqlite3_clear_bindings(tagStatement));
				SqlCheck( sqlite3_bind_int64(tagStatement,	1, node.ident.longLongValue));
				SqlCheck( sqlite3_bind_text(tagStatement,	2, key.UTF8String, -1, NULL));
				SqlCheck( sqlite3_bind_text(tagStatement,	3, value.UTF8String, -1, NULL));
				rc = sqlite3_step(tagStatement);
				if ( rc != SQLITE_DONE ) {
					DbgAssert(NO);
				}
			}];
	#if USE_RTREE
			[self addToSpatial:node];
	#endif
		}
	} @catch (id exception) {
		rc = SQLITE_ERROR;
	} @finally {
		sqlite3_finalize(nodeStatement);
		sqlite3_finalize(tagStatement);
	}
	
	return rc == SQLITE_OK || rc == SQLITE_DONE;
}

-(BOOL)saveWays:(NSArray<OsmWay *> *)ways
{
	__block int rc = SQLITE_OK;

	if ( ways.count == 0 )
		return YES;

	sqlite3_stmt * wayStatement = NULL;
	sqlite3_stmt * tagStatement = NULL;
	sqlite3_stmt * nodeStatement = NULL;

	@try {
		SqlCheck( sqlite3_prepare_v2( _db, "INSERT INTO ways (ident,user,timestamp,version,changeset,uid,nodecount) VALUES (?,?,?,?,?,?,?);", -1, &wayStatement, nil ));
		SqlCheck( sqlite3_prepare_v2( _db, "INSERT INTO way_tags (ident,key,value) VALUES (?,?,?);", -1, &tagStatement, nil ));
		SqlCheck( sqlite3_prepare_v2( _db, "INSERT INTO way_nodes (ident,node_id,node_index) VALUES (?,?,?);", -1, &nodeStatement, nil ));

		for ( OsmWay * way in ways ) {
		retry:
			// update way
			sqlite3_reset(wayStatement);
			SqlCheck( sqlite3_clear_bindings(wayStatement));
			SqlCheck( sqlite3_bind_int64(wayStatement,	1, way.ident.longLongValue));
			SqlCheck( sqlite3_bind_text(wayStatement,	2, way.user.UTF8String, -1, NULL));
			SqlCheck( sqlite3_bind_text(wayStatement,	3, way.timestamp.UTF8String, -1, NULL));
			SqlCheck( sqlite3_bind_int(wayStatement,	4, way.version));
			SqlCheck( sqlite3_bind_int64(wayStatement,	5, way.changeset));
			SqlCheck( sqlite3_bind_int(wayStatement,	6, way.uid));
			SqlCheck( sqlite3_bind_int(wayStatement,	7, (int)way.nodes.count));

			rc = sqlite3_step(wayStatement);
			if ( rc == SQLITE_CONSTRAINT ) {
				// tried to insert something already there. This might be an update to a later version from the server so delete what we have and retry
				NSLog(@"retry way %@\n",way.ident);
				[self deleteWays:@[ way ]];
				goto retry;
			}
			if ( rc != SQLITE_DONE ) {
				DbgAssert(NO);
				continue;
			}

			[way.tags enumerateKeysAndObjectsUsingBlock:^(NSString * key, NSString * value, BOOL *stop) {
				sqlite3_reset(tagStatement);
				SqlCheck( sqlite3_clear_bindings(tagStatement));
				SqlCheck( sqlite3_bind_int64(tagStatement,	1, way.ident.longLongValue));
				SqlCheck( sqlite3_bind_text(tagStatement,	2, key.UTF8String, -1, NULL));
				SqlCheck( sqlite3_bind_text(tagStatement,	3, value.UTF8String, -1, NULL));
				rc = sqlite3_step(tagStatement);
				DbgAssert(rc == SQLITE_DONE);
			}];

			int index = 0;
			for ( OsmNode * node in way.nodes ) {
				sqlite3_reset(nodeStatement);
				SqlCheck( sqlite3_clear_bindings(nodeStatement));
				SqlCheck( sqlite3_bind_int64(nodeStatement,	1, way.ident.longLongValue));
				SqlCheck( sqlite3_bind_int64(nodeStatement,	2, node.ident.longLongValue));
				SqlCheck( sqlite3_bind_int(nodeStatement,	3, index++));
				rc = sqlite3_step(nodeStatement);
				DbgAssert(rc == SQLITE_DONE);
			}
	#if USE_RTREE
			[self addToSpatial:way];
	#endif
		}
	} @catch (id exception) {
		rc = SQLITE_ERROR;
	} @finally {
		sqlite3_finalize(wayStatement);
		sqlite3_finalize(tagStatement);
		sqlite3_finalize(nodeStatement);
	}
	return rc == SQLITE_OK || rc == SQLITE_DONE;
}


-(BOOL)saveRelations:(NSArray<OsmRelation *> *)relations
{
	__block int rc = SQLITE_OK;

	if ( relations.count == 0 )
		return YES;

	sqlite3_stmt * baseStatement = NULL;
	sqlite3_stmt * tagStatement = NULL;
	sqlite3_stmt * memberStatement = NULL;

	@try {
		SqlCheck( sqlite3_prepare_v2( _db, "INSERT INTO relations (ident,user,timestamp,version,changeset,uid,membercount) VALUES (?,?,?,?,?,?,?);", -1, &baseStatement, nil ));
		SqlCheck( sqlite3_prepare_v2( _db, "INSERT INTO relation_tags (ident,key,value) VALUES (?,?,?);", -1, &tagStatement, nil ));
		SqlCheck( sqlite3_prepare_v2( _db, "INSERT INTO relation_members (ident,type,ref,role,member_index) VALUES (?,?,?,?,?);", -1, &memberStatement, nil ));

		for ( OsmRelation * relation in relations ) {
		retry:
			// update way
			sqlite3_reset(baseStatement);
			SqlCheck( sqlite3_clear_bindings(baseStatement));
			SqlCheck( sqlite3_bind_int64(baseStatement,	1, relation.ident.longLongValue));
			SqlCheck( sqlite3_bind_text(baseStatement,	2, relation.user.UTF8String, -1, NULL));
			SqlCheck( sqlite3_bind_text(baseStatement,	3, relation.timestamp.UTF8String, -1, NULL));
			SqlCheck( sqlite3_bind_int(baseStatement,	4, relation.version));
			SqlCheck( sqlite3_bind_int64(baseStatement,	5, relation.changeset));
			SqlCheck( sqlite3_bind_int(baseStatement,	6, relation.uid));
			SqlCheck( sqlite3_bind_int(baseStatement,	7, (int)relation.members.count));
			rc = sqlite3_step(baseStatement);
			if ( rc == SQLITE_CONSTRAINT ) {
				// tried to insert something already there. This might be an update to a later version from the server so delete what we have and retry
				NSLog(@"retry relation %@\n",relation.ident);
				[self deleteRelations:@[ relation ]];
				goto retry;
			}
			if ( rc != SQLITE_DONE ) {
				DbgAssert(NO);
				continue;
			}

			[relation.tags enumerateKeysAndObjectsUsingBlock:^(NSString * key, NSString * value, BOOL *stop) {
				sqlite3_reset(tagStatement);
				SqlCheck( sqlite3_clear_bindings(tagStatement));
				SqlCheck( sqlite3_bind_int64(tagStatement,	1, relation.ident.longLongValue));
				SqlCheck( sqlite3_bind_text(tagStatement,	2, key.UTF8String, -1, NULL));
				SqlCheck( sqlite3_bind_text(tagStatement,	3, value.UTF8String, -1, NULL));
				rc = sqlite3_step(tagStatement);
				DbgAssert(rc == SQLITE_DONE);
			}];

			int index = 0;
			for ( OsmMember * member in relation.members ) {
				NSNumber * ref = [member.ref isKindOfClass:[OsmBaseObject class]] ? ((OsmBaseObject *)member.ref).ident : member.ref;
				sqlite3_reset(memberStatement);
				SqlCheck( sqlite3_clear_bindings(memberStatement));
				SqlCheck( sqlite3_bind_int64(memberStatement,	1, relation.ident.longLongValue));
				SqlCheck( sqlite3_bind_text(memberStatement,	2, member.type.UTF8String, -1, NULL));
				SqlCheck( sqlite3_bind_int64(memberStatement,	3, ref.longLongValue));
				SqlCheck( sqlite3_bind_text(memberStatement,	4, member.role.UTF8String, -1, NULL));
				SqlCheck( sqlite3_bind_int(memberStatement,		5, index++));
				rc = sqlite3_step(memberStatement);
				DbgAssert(rc == SQLITE_DONE);
			}
	#if USE_RTREE
			[self addToSpatial:relation];
	#endif
		}
	} @catch (id exception) {
		rc = SQLITE_ERROR;
	} @finally {
		sqlite3_finalize(baseStatement);
		sqlite3_finalize(tagStatement);
		sqlite3_finalize(memberStatement);
	}
	
	return rc == SQLITE_OK || rc == SQLITE_DONE;
}


#pragma mark delete

-(BOOL)deleteNodes:(NSArray<OsmNode *> *)nodes
{
	if ( nodes.count == 0 )
		return YES;

	int rc;
	sqlite3_stmt * nodeStatement = NULL;
	
	@try {
		
		SqlCheck( sqlite3_prepare_v2( _db, "DELETE from NODES where ident=?;", -1, &nodeStatement, nil ));
		for ( OsmNode * node in nodes ) {
			sqlite3_reset(nodeStatement);
			SqlCheck( sqlite3_clear_bindings(nodeStatement));
			SqlCheck( sqlite3_bind_int64(nodeStatement, 1, node.ident.longLongValue));
			rc = sqlite3_step(nodeStatement);
			DbgAssert(rc == SQLITE_DONE);
		}
	} @catch (id exception) {
		rc = SQLITE_ERROR;
	} @finally {
		sqlite3_finalize(nodeStatement);
	}
	return rc == SQLITE_OK || rc == SQLITE_DONE;
}

-(BOOL)deleteWays:(NSArray *)ways
{
	if ( ways.count == 0 )
		return YES;

	int rc;
	sqlite3_stmt * nodeStatement = NULL;
	
	@try {
		SqlCheck( sqlite3_prepare_v2( _db, "DELETE from WAYS where ident=?;", -1, &nodeStatement, nil ));

		for ( OsmWay * way in ways ) {
			sqlite3_reset(nodeStatement);
			SqlCheck( sqlite3_clear_bindings(nodeStatement));
			SqlCheck( sqlite3_bind_int64(nodeStatement, 1, way.ident.longLongValue));
			rc = sqlite3_step(nodeStatement);
			DbgAssert(rc == SQLITE_DONE);
		}
	} @catch (id exception) {
		rc = SQLITE_ERROR;
	} @finally {
		sqlite3_finalize(nodeStatement);
	}
	return rc == SQLITE_OK || rc == SQLITE_DONE;
}

-(BOOL)deleteRelations:(NSArray *)relations
{
	if ( relations.count == 0 )
		return YES;

	int rc;
	sqlite3_stmt * relationStatement = NULL;
	
	@try {
		SqlCheck( sqlite3_prepare_v2( _db, "DELETE from RELATIONS where ident=?;", -1, &relationStatement, nil ));

		for ( OsmRelation * relation in relations ) {
			sqlite3_reset(relationStatement);
			SqlCheck( sqlite3_clear_bindings(relationStatement));
			SqlCheck( sqlite3_bind_int64(relationStatement, 1, relation.ident.longLongValue));
			rc = sqlite3_step(relationStatement);
			DbgAssert(rc == SQLITE_DONE);
		}
	} @catch (id exception) {
		rc = SQLITE_ERROR;
	} @finally {
		sqlite3_finalize(relationStatement);
	}
	return rc == SQLITE_OK || rc == SQLITE_DONE;
}

#pragma mark update

-(BOOL)saveNodes:(NSArray<OsmNode *> *)saveNodes saveWays:(NSArray<OsmWay *> *)saveWays saveRelations:(NSArray<OsmRelation *> *)saveRelations
		deleteNodes:(NSArray<OsmNode *> *)deleteNodes deleteWays:(NSArray *)deleteWays deleteRelations:(NSArray *)deleteRelations
		isUpdate:(BOOL)isUpdate
{
#if 0 && DEBUG
	assert( dispatch_get_current_queue() == Database.dispatchQueue );
#endif
	
	int rc = sqlite3_exec(_db, "BEGIN", 0, 0, 0);
	if ( rc != SQLITE_OK )
		return NO;
	
	BOOL ok = YES;
	if ( isUpdate ) {
		ok = ok && [self deleteNodes:saveNodes];
		ok = ok && [self deleteWays:saveWays];
		ok = ok && [self deleteRelations:saveRelations];
	}
	ok = ok && [self saveNodes:saveNodes];
	ok = ok && [self saveWays:saveWays];
	ok = ok && [self saveRelations:saveRelations];
	ok = ok && [self deleteNodes:deleteNodes];
	ok = ok && [self deleteWays:deleteWays];
	ok = ok && [self deleteRelations:deleteRelations];
	
	if ( ok ) {
		rc = sqlite3_exec(_db, "COMMIT", 0, 0, 0);
		ok = rc == SQLITE_OK;
	} else {
		sqlite3_exec(_db, "ROLLBACK", 0, 0, 0);
	}

	return ok;
}


#pragma mark query

-(BOOL)queryTagTable:(NSString *)tableName forObjects:(NSDictionary *)objectDict
{
	int rc = SQLITE_OK;

	sqlite3_stmt * tagStatement = NULL;
	@try {
		NSString * query = [NSString stringWithFormat:@"SELECT key,value,ident FROM %@", tableName];
		SqlCheck( sqlite3_prepare_v2( _db, query.UTF8String, -1, &tagStatement, nil ));

		sqlite3_reset(tagStatement);
		SqlCheck( sqlite3_clear_bindings(tagStatement));
		while ( (rc = sqlite3_step(tagStatement)) == SQLITE_ROW) {
			const uint8_t * ckey	= sqlite3_column_text(tagStatement, 0);
			const uint8_t * cvalue	= sqlite3_column_text(tagStatement, 1);
			int64_t			ident	= sqlite3_column_int64(tagStatement, 2);

			NSString * key = [NSString stringWithUTF8String:(char *)ckey];
			NSString * value = [NSString stringWithUTF8String:(char *)cvalue];

			OsmBaseObject * obj = objectDict[ @(ident) ];
			if ( obj == nil ) {
				rc = SQLITE_ERROR;
				break;
			}
			NSMutableDictionary * tags = (id)obj.tags;
			if ( tags == nil ) {
				tags = [NSMutableDictionary new];
				[obj setTags:tags undo:nil];
			}
			[tags setObject:value forKey:key];
		}
		if ( rc == SQLITE_DONE )
			rc = SQLITE_OK;

		[objectDict enumerateKeysAndObjectsUsingBlock:^(id key, OsmBaseObject * obj, BOOL *stop) {
			[obj setConstructed];
		}];
	} @catch (id exception) {
		rc = SQLITE_ERROR;
	} @finally {
		sqlite3_finalize(tagStatement);
	}
	return rc == SQLITE_OK;
}

-(NSMutableDictionary<NSNumber *, OsmNode *> *)querySqliteNodes
{
	if ( _db == NULL )
		return nil;

	int rc = SQLITE_OK;
	sqlite3_stmt * nodeStatement = NULL;
	rc = sqlite3_prepare_v2( _db, "SELECT ident,user,timestamp,version,changeset,uid,longitude,latitude FROM nodes", -1, &nodeStatement, nil );
	if ( rc != SQLITE_OK )
		return nil;

	NSMutableDictionary<NSNumber *, OsmNode *> * nodes = [NSMutableDictionary new];
	
	while ( (rc = sqlite3_step(nodeStatement)) == SQLITE_ROW )  {
		int64_t			ident		= sqlite3_column_int64(nodeStatement, 0);
		const uint8_t *	user		= sqlite3_column_text(nodeStatement, 1);
		const uint8_t *	timestamp	= sqlite3_column_text(nodeStatement, 2);
		int32_t			version		= sqlite3_column_int(nodeStatement, 3);
		int32_t			changeset	= sqlite3_column_int(nodeStatement, 4);
		int32_t			uid			= sqlite3_column_int(nodeStatement, 5);
		double			longitude	= sqlite3_column_double(nodeStatement, 6);
		double			latitude	= sqlite3_column_double(nodeStatement, 7);

		OsmNode * node = [[OsmNode alloc] init];
		[node constructBaseAttributesWithVersion:version
									   changeset:changeset
											user:[NSString stringWithUTF8String:(const char *)user]
											 uid:uid
										   ident:ident
									   timestamp:[NSString stringWithUTF8String:(const char *)timestamp]];
		[node setLongitude:longitude latitude:latitude undo:nil];

		[nodes setObject:node forKey:node.ident];
	}
	if ( rc == SQLITE_DONE || rc == SQLITE_OK ) {
		BOOL ok = [self queryTagTable:@"node_tags" forObjects:nodes];
		rc = ok ? SQLITE_OK : SQLITE_ERROR;
	}
	sqlite3_finalize(nodeStatement);

	return rc == SQLITE_OK ? nodes : nil;
}

-(NSMutableDictionary<NSNumber *, OsmWay *> *)querySqliteWays
{
	if ( _db == NULL )
		return nil;

	int rc = SQLITE_OK;
	sqlite3_stmt * wayStatement = NULL;
	NSMutableDictionary<NSNumber *, OsmWay *> * ways = [NSMutableDictionary new];

	rc = sqlite3_prepare_v2( _db, "SELECT ident,user,timestamp,version,changeset,uid,nodecount FROM ways", -1, &wayStatement, nil );
	if ( rc != SQLITE_OK )
		return nil;

	while ( (rc = sqlite3_step(wayStatement)) == SQLITE_ROW )  {
		int64_t			ident		= sqlite3_column_int64(wayStatement, 0);
		const uint8_t *	user		= sqlite3_column_text(wayStatement, 1);
		const uint8_t *	timestamp	= sqlite3_column_text(wayStatement, 2);
		int32_t			version		= sqlite3_column_int(wayStatement, 3);
		int32_t			changeset	= sqlite3_column_int(wayStatement, 4);
		int32_t			uid			= sqlite3_column_int(wayStatement, 5);
		int32_t			nodecount	= sqlite3_column_int(wayStatement, 6);

		if ( nodecount < 0 ) {
			rc = SQLITE_ERROR;
			break;
		}

		OsmWay * way = [[OsmWay alloc] init];
		[way  constructBaseAttributesWithVersion:version
									   changeset:changeset
											user:[NSString stringWithUTF8String:(const char *)user]
											 uid:uid
										   ident:ident
									   timestamp:[NSString stringWithUTF8String:(const char *)timestamp]];
		NSMutableArray * nodes = [NSMutableArray arrayWithCapacity:nodecount];
		for ( NSInteger i = 0; i < nodecount; ++i )
			[nodes addObject:@(-1LL)];
		[way constructNodeList:nodes];
		[ways setObject:way forKey:way.ident];
	}
	if ( rc == SQLITE_DONE )
		rc = SQLITE_OK;
	sqlite3_finalize(wayStatement);

	if ( rc == SQLITE_OK ) {
		BOOL ok = [self queryTagTable:@"way_tags" forObjects:ways];
		if ( ok ) {
			ok = [self queryNodesForWays:ways];
		}
		if ( !ok )
			rc = SQLITE_ERROR;
	}

	return rc == SQLITE_OK ? ways : nil;
}

-(BOOL)queryNodesForWays:(NSDictionary *)ways
{
	int rc = SQLITE_OK;

	sqlite3_stmt * nodeStatement = NULL;
	rc = sqlite3_prepare_v2( _db, "SELECT ident,node_id,node_index FROM way_nodes", -1, &nodeStatement, nil );
	if ( rc != SQLITE_OK )
		return NO;
	
	while ( (rc = sqlite3_step(nodeStatement)) == SQLITE_ROW) {
		int64_t		ident		= sqlite3_column_int64(nodeStatement, 0);
		int64_t		node_id		= sqlite3_column_int64(nodeStatement, 1);
		int			node_index	= sqlite3_column_int(nodeStatement, 2);

		OsmWay * way = ways[ @(ident) ];
		NSMutableArray * list = (id)way.nodes;
		DbgAssert( list );
		list[node_index] = @(node_id);
	}

	sqlite3_finalize(nodeStatement);

	return rc == SQLITE_DONE || rc == SQLITE_OK;
}


-(NSMutableDictionary<NSNumber *, OsmRelation *> *)querySqliteRelations
{
	if ( _db == NULL )
		return nil;

	int rc = SQLITE_OK;

	sqlite3_stmt * relationStatement = NULL;
	rc = sqlite3_prepare_v2( _db, "SELECT ident,user,timestamp,version,changeset,uid,membercount FROM relations", -1, &relationStatement, nil );
	if ( rc != SQLITE_OK )
		return nil;

	NSMutableDictionary<NSNumber *, OsmRelation *> * relations = [NSMutableDictionary new];
	while ( (rc = sqlite3_step(relationStatement)) == SQLITE_ROW )  {
		int64_t			ident		= sqlite3_column_int64(relationStatement, 0);
		const uint8_t *	user		= sqlite3_column_text(relationStatement, 1);
		const uint8_t *	timestamp	= sqlite3_column_text(relationStatement, 2);
		int32_t			version		= sqlite3_column_int(relationStatement, 3);
		int32_t			changeset	= sqlite3_column_int(relationStatement, 4);
		int32_t			uid			= sqlite3_column_int(relationStatement, 5);
		int32_t			membercount	= sqlite3_column_int(relationStatement, 6);

		OsmRelation * relation = [[OsmRelation alloc] init];
		[relation  constructBaseAttributesWithVersion:version
									   changeset:changeset
											user:[NSString stringWithUTF8String:(const char *)user]
											 uid:uid
										   ident:ident
									   timestamp:[NSString stringWithUTF8String:(const char *)timestamp]];
		for ( NSInteger i = 0; i < membercount; ++i ) {
			[relation constructMember:(OsmMember *)[NSNull null]];
		}
		[relations setObject:relation forKey:relation.ident];
	}
	sqlite3_finalize(relationStatement);

	if ( rc == SQLITE_DONE || rc == SQLITE_OK) {
		BOOL ok = [self queryTagTable:@"relation_tags" forObjects:relations];
		if ( ok ) {
			ok = [self queryMembersForRelations:relations];
		}
		rc = ok ? SQLITE_OK : SQLITE_ERROR;
	}
	return rc == SQLITE_OK ? relations : nil;
}

-(BOOL)queryMembersForRelations:(NSDictionary *)relations
{
	sqlite3_stmt * memberStatement = NULL;

	int rc = sqlite3_prepare_v2( _db, "SELECT ident,type,ref,role,member_index FROM relation_members", -1, &memberStatement, nil );
	if ( rc != SQLITE_OK )
		return NO;

	while ( (rc = sqlite3_step(memberStatement)) == SQLITE_ROW) {
		int64_t			ident			= sqlite3_column_int64(memberStatement, 0);
		const uint8_t * type			= sqlite3_column_text(memberStatement, 1);
		int64_t			ref				= sqlite3_column_int64(memberStatement, 2);
		const uint8_t * role			= sqlite3_column_text(memberStatement, 3);
		int				member_index	= sqlite3_column_int(memberStatement, 4);

		OsmRelation * relation = relations[ @(ident) ];
		OsmMember * member = [[OsmMember alloc] initWithType:[NSString stringWithUTF8String:(const char *)type] ref:@(ref) role:[NSString stringWithUTF8String:(const char *)role]];
		NSMutableArray * list = (id)relation.members;
		DbgAssert( list );
		list[member_index] = member;
	}

	sqlite3_finalize(memberStatement);

	return rc == SQLITE_DONE || rc == SQLITE_OK;
}

@end
