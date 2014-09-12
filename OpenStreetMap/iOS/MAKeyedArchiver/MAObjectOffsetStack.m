//
//  MAObjectOffsetStack.m
//  MAKeyedArchiver
//
//  Created by Michael Ash on Thu Nov 20 2003.
//  Copyright (c) 2003 __MyCompanyName__. All rights reserved.
//

#import "MAObjectOffsetStack.h"


@implementation MAObjectOffsetStack

- init
{
	stack = calloc(10, sizeof(*stack));
	capacity = 10;
	return self;
}

- (void)dealloc
{
	free(stack);
	[super dealloc];
}

- (void)push:(ObjectOffsetPair)pair
{
	if(pair.obj == nil)
	{
		MyErrorLog(@"tried to insert nil object");
		return;
	}
	if(top >= capacity)
	{
		capacity *= 2;
		stack = realloc(stack, capacity * sizeof(*stack));
	}
	stack[top++] = pair;
	[pair.obj retain];
}

- (ObjectOffsetPair)pop
{
	if(top)
	{
		ObjectOffsetPair pair = stack[--top];
		[pair.obj autorelease];
		return pair;
	}
	else
		return MAMakeObjectOffsetPair(nil, 0);
}

- (BOOL)isEmpty
{
	return top <= 0;
}

@end
