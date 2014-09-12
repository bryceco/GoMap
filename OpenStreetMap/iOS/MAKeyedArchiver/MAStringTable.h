//
//  MAStringTable.h
//  MAKeyedArchiver
//
//  Created by Michael Ash on Thu Nov 20 2003.
//  Copyright (c) 2003 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>


@class MAObjectOffsetTable;

@interface MAStringTable : NSObject {
	NSMapTable *map;
	NSMutableArray *strings;
}

- (unsigned)indexOfString:(NSString *)str;
- (NSArray *)strings;
- (unsigned)count;

@end
