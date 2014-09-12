//
//  MAObjectStack.m
//  MAKeyedArchiver
//
//  Created by Michael Ash on Thu Nov 20 2003.
//  Copyright (c) 2003 __MyCompanyName__. All rights reserved.
//

#import "MAObjectStack.h"


@implementation MAObjectStack

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

- (void)push:obj
{
	if(obj == nil)
	{
		MyErrorLog(@"tried to insert nil object");
		return;
	}
	if(top >= capacity)
	{
		capacity *= 2;
		stack = realloc(stack, capacity * sizeof(*stack));
	}
	stack[top++] = [obj retain];
}

- pop
{
	if(top)
		return [stack[--top] autorelease];
	else
		return nil;
}

- peek
{
	if(top)
		return stack[top - 1];
	else
		return nil;
}

- (BOOL)isEmpty
{
	return top <= 0;
}

@end
