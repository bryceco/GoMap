//
//  MAObjectOffsetTable.h
//  MAKeyedArchiver
//
//  Created by Michael Ash on Thu Nov 20 2003.
//  Copyright (c) 2003 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface MAObjectOffsetTable : NSObject {
	NSMapTable *map;
}

- (int)offsetOfObject:obj;
- (void)setOffset:(int)offset forObject:obj;

@end
