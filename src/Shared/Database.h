//
//  Database.h
//  Go Map!!
//
//  Created by Bryce Cogswell on 9/14/14.
//  Copyright (c) 2014 Bryce Cogswell. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface Database : NSObject
{
	NSString			*	_path;
	struct sqlite3		*	_db;

	struct sqlite3_stmt	*	_spatialInsert;
	struct sqlite3_stmt	*	_spatialDelete;
}
@property (class,readonly,nonatomic)	dispatch_queue_t	dispatchQueue;

+(NSString *)databasePathWithName:(NSString *)name;
+(void)deleteDatabaseWithName:(NSString *)name;

-(instancetype)initWithName:(NSString *)name;
-(NSString *)path;

-(void)createTables;
-(void)dropTables;

-(BOOL)saveNodes:(NSArray<OsmNode *> *)saveNodes saveWays:(NSArray<OsmWay *> *)saveWays saveRelations:(NSArray<OsmRelation *> *)saveRelations
		deleteNodes:(NSArray *)deleteNodes deleteWays:(NSArray *)deleteWays deleteRelations:(NSArray *)deleteRelations
		isUpdate:(BOOL)isUpdate;

-(NSMutableDictionary<NSNumber *, OsmNode *> *)querySqliteNodes;
-(NSMutableDictionary<NSNumber *, OsmWay *> *)querySqliteWays;
-(NSMutableDictionary<NSNumber *, OsmRelation *> *)querySqliteRelations;

@end
