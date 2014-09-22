//
//  Database.m
//  Go Map!!
//
//  Created by Bryce on 9/14/14.
//  Copyright (c) 2014 Bryce. All rights reserved.
//

#import <sqlite3.h>

#import "Database.h"
#import "OsmObjects.h"

#if DEBUG
#define DbgAssert(x)	assert(x)
#else
#define DbgAssert(x)	(void)0
#endif

@implementation Database

- (NSString *)databasePath
{
	NSArray *paths = NSSearchPathForDirectoriesInDomains( NSCachesDirectory, NSUserDomainMask, YES );
	if ( [paths count] ) {
		NSString * bundleName = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleIdentifier"];
		NSString * path = [[[paths objectAtIndex:0]
							stringByAppendingPathComponent:bundleName]
						   stringByAppendingPathComponent:@"data.sqlite3"];
		[[NSFileManager defaultManager] createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:NULL error:NULL];
		return path;
	}
	return nil;
}


-(instancetype)init
{
	self = [super init];
	if ( self ) {
		_path = [self databasePath];
		int rc = sqlite3_open_v2( _path.UTF8String, &_db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, NULL );
		if ( rc == SQLITE_OK ) {
			rc = sqlite3_exec(_db, "PRAGMA foreign_keys=ON", NULL, NULL, NULL );
			assert( rc == SQLITE_OK );
		} else {
			_db = NULL;
		}
	}
	return self;
}

-(void)dealloc
{
	if ( _db ) {
		sqlite3_close(_db);
	}
}

-(void)dropTables
{
	int rc;
	rc = sqlite3_exec(_db, "drop table node_tags;",		0, 0, 0);
	rc = sqlite3_exec(_db, "drop table nodes;",			0, 0, 0);
	rc = sqlite3_exec(_db, "drop table way_tags;",		0, 0, 0);
	rc = sqlite3_exec(_db, "drop table way_nodes;",		0, 0, 0);
	rc = sqlite3_exec(_db, "drop table ways;",			0, 0, 0);
}

-(void)createTables
{
	int rc;

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
					  "ident int8 not null,"
					  "key varchar(255) not null,"
					  "value varchar(255) not null,"
					  "FOREIGN KEY(ident) REFERENCES ways(ident) on delete cascade);",
					  0, 0, 0);
	DbgAssert(rc == SQLITE_OK);
}


-(BOOL)saveNodes:(NSArray *)nodes
{
	if ( nodes.count == 0 )
		return YES;

	sqlite3_stmt * nodeStatement;
	__block int rc = sqlite3_prepare_v2( _db, "INSERT INTO NODES (user,timestamp,version,changeset,uid,longitude,latitude,ident) VALUES (?,?,?,?,?,?,?,?);", -1, &nodeStatement, nil );
	if ( rc != SQLITE_OK ) {
		DbgAssert(NO);
		return NO;
	}

	sqlite3_stmt * tagStatement;
	rc = sqlite3_prepare_v2( _db, "INSERT INTO node_tags (ident,key,value) VALUES (?,?,?);", -1, &tagStatement, nil );
	if ( rc != SQLITE_OK ) {
		DbgAssert(NO);
		return NO;
	}

	for ( OsmNode * node in nodes ) {
	retry:
		rc = sqlite3_reset(nodeStatement);
		rc = sqlite3_clear_bindings(nodeStatement);
		rc = sqlite3_bind_text(nodeStatement,	1, node.user.UTF8String, -1, NULL);
		rc = sqlite3_bind_text(nodeStatement,	2, node.timestamp.UTF8String, -1, NULL);
		rc = sqlite3_bind_int(nodeStatement,	3, node.version);
		rc = sqlite3_bind_int64(nodeStatement,	4, node.changeset);
		rc = sqlite3_bind_int(nodeStatement,	5, node.uid);
		rc = sqlite3_bind_double(nodeStatement,	6, node.lon);
		rc = sqlite3_bind_double(nodeStatement,	7, node.lat);
		rc = sqlite3_bind_int64(nodeStatement,	8, node.ident.longLongValue);
		rc = sqlite3_step(nodeStatement);
		if ( rc == SQLITE_CONSTRAINT ) {
			// tried to insert something already there. This might be an update to a later version from the server so delete what we have and retry
			[self deleteNodes:@[node]];
			goto retry;
		}
		if ( rc != SQLITE_DONE ) {
			DbgAssert(NO);
			continue;
		}

		[node.tags enumerateKeysAndObjectsUsingBlock:^(NSString * key, NSString * value, BOOL *stop) {
			int rc2;
			rc2 = sqlite3_reset(tagStatement);
			rc2 = sqlite3_clear_bindings(tagStatement);
			rc2 = sqlite3_bind_int64(tagStatement,	1, node.ident.longLongValue);
			rc2 = sqlite3_bind_text(tagStatement,	2, key.UTF8String, -1, NULL);
			rc2 = sqlite3_bind_text(tagStatement,	3, value.UTF8String, -1, NULL);
			rc2 = sqlite3_step(tagStatement);
			if ( rc2 != SQLITE_DONE ) {
				DbgAssert(NO);
			}
		}];
	}

	sqlite3_finalize(nodeStatement);
	sqlite3_finalize(tagStatement);

	return rc == SQLITE_OK || rc == SQLITE_DONE;
}

-(BOOL)saveWays:(NSArray *)ways
{
	if ( ways.count == 0 )
		return YES;

	sqlite3_stmt * wayStatement;
	int rc = sqlite3_prepare_v2( _db, "INSERT INTO ways (ident,user,timestamp,version,changeset,uid,nodecount) VALUES (?,?,?,?,?,?,?);", -1, &wayStatement, nil );
	if ( rc != SQLITE_OK) {
		DbgAssert(NO);
		return NO;
	}

	sqlite3_stmt * tagStatement;
	rc = sqlite3_prepare_v2( _db, "INSERT INTO way_tags (ident,key,value) VALUES (?,?,?);", -1, &tagStatement, nil );
	if ( rc != SQLITE_OK ) {
		DbgAssert(NO);
		return NO;
	}

	sqlite3_stmt * nodeStatement;
	rc = sqlite3_prepare_v2( _db, "INSERT INTO way_nodes (ident,node_id,node_index) VALUES (?,?,?);", -1, &nodeStatement, nil );
	DbgAssert(rc == SQLITE_OK);

	for ( OsmWay * way in ways ) {
	retry:
		// update way
		rc = sqlite3_reset(wayStatement);
		rc = sqlite3_clear_bindings(wayStatement);
		rc = sqlite3_bind_int64(wayStatement,	1, way.ident.longLongValue);
		rc = sqlite3_bind_text(wayStatement,	2, way.user.UTF8String, -1, NULL);
		rc = sqlite3_bind_text(wayStatement,	3, way.timestamp.UTF8String, -1, NULL);
		rc = sqlite3_bind_int(wayStatement,		4, way.version);
		rc = sqlite3_bind_int64(wayStatement,	5, way.changeset);
		rc = sqlite3_bind_int(wayStatement,		6, way.uid);
		rc = sqlite3_bind_int(wayStatement,		7, (int)way.nodes.count);
		rc = sqlite3_step(wayStatement);
		if ( rc == SQLITE_CONSTRAINT ) {
			// tried to insert something already there. This might be an update to a later version from the server so delete what we have and retry
			[self deleteWays:@[ way ]];
			goto retry;
		}
		if ( rc != SQLITE_DONE ) {
			DbgAssert(NO);
			continue;
		}

		[way.tags enumerateKeysAndObjectsUsingBlock:^(NSString * key, NSString * value, BOOL *stop) {
			int rc2;
			rc2 = sqlite3_reset(tagStatement);
			rc2 = sqlite3_clear_bindings(tagStatement);
			rc2 = sqlite3_bind_int64(tagStatement,	1, way.ident.longLongValue);
			rc2 = sqlite3_bind_text(tagStatement,	2, key.UTF8String, -1, NULL);
			rc2 = sqlite3_bind_text(tagStatement,	3, value.UTF8String, -1, NULL);
			rc2 = sqlite3_step(tagStatement);
			DbgAssert(rc2 == SQLITE_DONE);
		}];

		int index = 0;
		for ( OsmNode * node in way.nodes ) {
			int rc2;
			rc2 = sqlite3_reset(nodeStatement);
			rc2 = sqlite3_clear_bindings(nodeStatement);
			rc2 = sqlite3_bind_int64(nodeStatement,	1, way.ident.longLongValue);
			rc2 = sqlite3_bind_int64(nodeStatement,	2, node.ident.longLongValue);
			rc2 = sqlite3_bind_int(nodeStatement,	3, index++);
			rc2 = sqlite3_step(nodeStatement);
			DbgAssert(rc2 == SQLITE_DONE);
		}
	}

	sqlite3_finalize(wayStatement);
	sqlite3_finalize(tagStatement);
	sqlite3_finalize(nodeStatement);

	return rc == SQLITE_OK || rc == SQLITE_DONE;
}

-(BOOL)deleteNodes:(NSArray *)nodes
{
	if ( nodes.count == 0 )
		return YES;

	sqlite3_stmt * nodeStatement;
	int rc = sqlite3_prepare_v2( _db, "DELETE from NODES where ident=?;", -1, &nodeStatement, nil );
	if ( rc != SQLITE_OK ) {
		DbgAssert(NO);
		return NO;
	}

	for ( OsmNode * node in nodes ) {
		rc = sqlite3_reset(nodeStatement);
		rc = sqlite3_clear_bindings(nodeStatement);
		rc = sqlite3_bind_int64(nodeStatement, 1, node.ident.longLongValue);
		rc = sqlite3_step(nodeStatement);
		DbgAssert(rc == SQLITE_DONE);
	}
	sqlite3_finalize(nodeStatement);
	return rc == SQLITE_OK || rc == SQLITE_DONE;
}

-(BOOL)deleteWays:(NSArray *)ways
{
	if ( ways.count == 0 )
		return YES;

	sqlite3_stmt * nodeStatement;
	int rc = sqlite3_prepare_v2( _db, "DELETE from WAYS where ident=?;", -1, &nodeStatement, nil );
	if ( rc != SQLITE_OK ) {
		DbgAssert(NO);
		return NO;
	}

	for ( OsmWay * way in ways ) {
		rc = sqlite3_reset(nodeStatement);
		rc = sqlite3_clear_bindings(nodeStatement);
		rc = sqlite3_bind_int64(nodeStatement, 1, way.ident.longLongValue);
		rc = sqlite3_step(nodeStatement);
		DbgAssert(rc == SQLITE_DONE);
	}
	sqlite3_finalize(nodeStatement);
	return rc == SQLITE_OK || rc == SQLITE_DONE;
}

-(BOOL)saveNodes:(NSArray *)saveNodes saveWays:(NSArray *)saveWays deleteNodes:(NSArray *)deleteNodes deleteWays:(NSArray *)deleteWays isUpdate:(BOOL)isUpdate
{
	int rc;
	rc = sqlite3_exec(_db, "BEGIN", 0, 0, 0);
	DbgAssert(rc == SQLITE_OK );
	if ( isUpdate ) {
		[self deleteNodes:saveNodes];
		[self deleteWays:saveWays];
	}
	[self saveNodes:saveNodes];
	[self saveWays:saveWays];
	[self deleteNodes:deleteNodes];
	[self deleteWays:deleteWays];
	rc = sqlite3_exec(_db, "COMMIT", 0, 0, 0);
	DbgAssert(rc == SQLITE_OK);

	return rc == SQLITE_OK;
}




-(NSMutableDictionary *)querySqliteNodes
{
	if ( _db == NULL )
		return nil;

	sqlite3_stmt * nodeStatement = NULL;
	int rc = sqlite3_prepare_v2( _db, "SELECT ident,user,timestamp,version,changeset,uid,longitude,latitude FROM nodes", -1, &nodeStatement, nil );
	if ( rc != SQLITE_OK ) {
		DbgAssert(NO);
		return nil;
	}

	NSMutableDictionary * nodes = [NSMutableDictionary new];
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

	[self queryTagTable:@"node_tags" forObjects:nodes];

	DbgAssert(rc == SQLITE_DONE || rc == SQLITE_OK);
	sqlite3_finalize(nodeStatement);
	return nodes;
}

-(NSMutableDictionary *)querySqliteWays
{
	if ( _db == NULL )
		return nil;

	sqlite3_stmt * wayStatement = NULL;
	int rc = sqlite3_prepare_v2( _db, "SELECT ident,user,timestamp,version,changeset,uid,nodecount FROM ways", -1, &wayStatement, nil );
	if ( rc != SQLITE_OK ) {
		DbgAssert(NO);
		return nil;
	}

	NSMutableDictionary * ways = [NSMutableDictionary new];
	while ( (rc = sqlite3_step(wayStatement)) == SQLITE_ROW )  {
		int64_t			ident		= sqlite3_column_int64(wayStatement, 0);
		const uint8_t *	user		= sqlite3_column_text(wayStatement, 1);
		const uint8_t *	timestamp	= sqlite3_column_text(wayStatement, 2);
		int32_t			version		= sqlite3_column_int(wayStatement, 3);
		int32_t			changeset	= sqlite3_column_int(wayStatement, 4);
		int32_t			uid			= sqlite3_column_int(wayStatement, 5);
		int32_t			nodecount	= sqlite3_column_int(wayStatement, 6);

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
	DbgAssert(rc == SQLITE_DONE || rc == SQLITE_OK);
	sqlite3_finalize(wayStatement);

	[self queryTagTable:@"way_tags" forObjects:ways];
	[self queryNodesForWays:ways];

	return ways;
}


-(void)queryNodesForWays:(NSDictionary *)ways
{
	sqlite3_stmt * nodeStatement = NULL;
	int rc = sqlite3_prepare_v2( _db, "SELECT ident,node_id,node_index FROM way_nodes", -1, &nodeStatement, nil );
	if ( rc != SQLITE_OK) {
		DbgAssert(NO);
		return;
	}

	while ( (rc = sqlite3_step(nodeStatement)) == SQLITE_ROW) {
		int64_t		ident		= sqlite3_column_int64(nodeStatement, 0);
		int64_t		node_id		= sqlite3_column_int64(nodeStatement, 1);
		int64_t		node_index	= sqlite3_column_int(nodeStatement, 2);

		OsmWay * way = ways[ @(ident) ];
		NSMutableArray * list = (id)way.nodes;
		DbgAssert( list );
		list[node_index] = @(node_id);
	}
	DbgAssert(rc == SQLITE_DONE || rc == SQLITE_OK);

	sqlite3_finalize(nodeStatement);
}


-(BOOL)queryTagTable:(NSString *)tableName forObjects:(NSDictionary *)objectDict
{
	NSString * query = [NSString stringWithFormat:@"SELECT key,value,ident FROM %@", tableName];
	sqlite3_stmt * tagStatement = NULL;
	int rc = sqlite3_prepare_v2( _db, query.UTF8String, -1, &tagStatement, nil );
	if ( rc != SQLITE_OK ) {
		DbgAssert(NO);
		return NO;
	}

	rc = sqlite3_reset(tagStatement);
	rc = sqlite3_clear_bindings(tagStatement);
	DbgAssert(rc == SQLITE_OK);
	while ( (rc = sqlite3_step(tagStatement)) == SQLITE_ROW) {
		const uint8_t * ckey	= sqlite3_column_text(tagStatement, 0);
		const uint8_t * cvalue	= sqlite3_column_text(tagStatement, 1);
		int64_t			ident	= sqlite3_column_int64(tagStatement, 2);

		NSString * key = [NSString stringWithUTF8String:(char *)ckey];
		NSString * value = [NSString stringWithUTF8String:(char *)cvalue];

		OsmBaseObject * obj = objectDict[ @(ident) ];
		assert( obj );
		NSMutableDictionary * tags = (id)obj.tags;
		if ( tags == nil ) {
			tags = [NSMutableDictionary new];
			[obj setTags:tags undo:nil];
		}
		[tags setObject:value forKey:key];
	}
	DbgAssert(rc == SQLITE_DONE || rc == SQLITE_OK);

	[objectDict enumerateKeysAndObjectsUsingBlock:^(id key, OsmBaseObject * obj, BOOL *stop) {
		[obj setConstructed];
	}];

	sqlite3_finalize(tagStatement);
	return YES;
}


@end
