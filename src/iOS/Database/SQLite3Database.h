//
//  SQLite3Database.h
//  Go Map!!
//
//  Created by Bryce Cogswell on 9/14/14.
//  Copyright (c) 2014 Bryce Cogswell. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface SQLite3Database : NSObject <Database>
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

-(BOOL)saveNodes:(NSArray *)saveNodes saveWays:(NSArray *)saveWays saveRelations:(NSArray *)saveRelations
		deleteNodes:(NSArray *)deleteNodes deleteWays:(NSArray *)deleteWays deleteRelations:(NSArray *)deleteRelations
		isUpdate:(BOOL)isUpdate;

@end
