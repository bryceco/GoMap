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

-(void)dropTables;
-(void)createTables;

-(BOOL)saveNodes:(NSArray *)saveNodes saveWays:(NSArray *)saveWays saveRelations:(NSArray *)saveRelations
		deleteNodes:(NSArray *)deleteNodes deleteWays:(NSArray *)deleteWays deleteRelations:(NSArray *)deleteRelations
		isUpdate:(BOOL)isUpdate;

-(NSMutableDictionary *)querySqliteNodes;
-(NSMutableDictionary *)querySqliteWays;
-(NSMutableDictionary *)querySqliteRelations;

@end
