//
//  Database.h
//  Go Map!!
//
//  Created by Bryce Cogswell on 9/14/14.
//  Copyright (c) 2014 Bryce Cogswell. All rights reserved.
//

#import <Foundation/Foundation.h>

@class OsmNode;
@class OsmWay;
@class OsmRelation;

@interface Database : NSObject
{
	NSString			*	_path;
	struct sqlite3		*	_db;

	struct sqlite3_stmt	*	_spatialInsert;
	struct sqlite3_stmt	*	_spatialDelete;
}
@property (class,readonly,nonatomic)	dispatch_queue_t _Nonnull	dispatchQueue;

+(NSString *_Nonnull)databasePathWithName:(NSString *_Nullable)name;
+(void)deleteDatabaseWithName:(NSString *_Nullable)name;

-(instancetype _Nullable )initWithName:(NSString *_Nullable)name;
-(NSString *_Nonnull)path;
-(void)close;

-(void)createTables;
-(void)dropTables;

-(BOOL)saveNodes:(NSArray<OsmNode *> *_Nonnull)saveNodes
        saveWays:(NSArray<OsmWay *> *_Nonnull)saveWays
   saveRelations:(NSArray<OsmRelation *> *_Nonnull)saveRelations
     deleteNodes:(NSArray<OsmNode *> *_Nonnull)deleteNodes
      deleteWays:(NSArray<OsmWay *> *_Nonnull)deleteWays
 deleteRelations:(NSArray<OsmRelation *> *_Nonnull)deleteRelations
        isUpdate:(BOOL)isUpdate;

-(NSMutableDictionary<NSNumber *, OsmNode *> *_Nullable)querySqliteNodes;
-(NSMutableDictionary<NSNumber *, OsmWay *> *_Nullable)querySqliteWays;
-(NSMutableDictionary<NSNumber *, OsmRelation *> *_Nullable)querySqliteRelations;

@end
