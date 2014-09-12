//
//  MAObjectSet.h
//  MAKeyedArchiver
//
//  Created by Michael Ash on Thu Nov 20 2003.
//  Copyright (c) 2003 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface MAObjectSet : NSObject {
	NSHashTable *table;
}

- (BOOL)containsObject:obj;
- (void)addObject:obj;
- (void)removeObject:obj;

@end
