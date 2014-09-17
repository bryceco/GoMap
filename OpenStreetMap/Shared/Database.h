//
//  Database.h
//  Go Map!!
//
//  Created by Bryce on 9/14/14.
//  Copyright (c) 2014 Bryce. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface Database : NSObject
{
	NSString		*	_path;
	struct sqlite3	*	_db;
}

-(void)dropTables;
-(void)createTables;
-(BOOL)saveNodes:(NSArray *)saveNodes saveWays:(NSArray *)saveWays deleteNodes:(NSArray *)nodes deleteWays:(NSArray *)ways isUpdate:(BOOL)isUpdate;
-(NSMutableDictionary *)querySqliteNodes;
-(NSMutableDictionary *)querySqliteWays;

@end
