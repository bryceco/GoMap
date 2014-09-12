//
//  MAObjectOffsetStack.h
//  MAKeyedArchiver
//
//  Created by Michael Ash on Thu Nov 20 2003.
//  Copyright (c) 2003 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>


typedef struct
{
	id obj; unsigned offset;
} ObjectOffsetPair;

static inline ObjectOffsetPair MAMakeObjectOffsetPair(id obj, int offset)
	{ ObjectOffsetPair pair = { obj, offset }; return pair; }

@interface MAObjectOffsetStack : NSObject {
	ObjectOffsetPair *stack;
	unsigned top;
	unsigned capacity;
}

- (void)push:(ObjectOffsetPair)pair;
- (ObjectOffsetPair)pop;
- (BOOL)isEmpty;

@end
