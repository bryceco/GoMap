//
//  MAObjectSet.m
//  MAKeyedArchiver
//
//  Created by Michael Ash on Thu Nov 20 2003.
//  Copyright (c) 2003 __MyCompanyName__. All rights reserved.
//

#import "MAObjectSet.h"


@implementation MAObjectSet

static void Retain(NSHashTable *table, const void *obj)
{
	[(id)obj retain];
}

static void Release(NSHashTable *table, void *obj)
{
	[(id)obj release];
}

- init
{
	NSHashTableCallBacks callbacks = {
		NULL, // hash
		NULL, // isEqual
		Retain,
		Release,
		NULL // description
	};
	table = NSCreateHashTable(callbacks, 0);
	return self;
}

- (void)dealloc
{
	NSFreeHashTable(table);
	[super dealloc];
}

- (BOOL)containsObject:obj
{
	return NSHashGet(table, obj) ? YES : NO;
}

- (void)addObject:obj
{
	NSHashInsert(table, obj);
}

- (void)removeObject:obj
{
	NSHashRemove(table, obj);
}

@end
