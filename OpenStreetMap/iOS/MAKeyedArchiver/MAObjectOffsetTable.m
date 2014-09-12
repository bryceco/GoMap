//
//  MAObjectOffsetTable.m
//  MAKeyedArchiver
//
//  Created by Michael Ash on Thu Nov 20 2003.
//  Copyright (c) 2003 __MyCompanyName__. All rights reserved.
//

#import "MAObjectOffsetTable.h"


@implementation MAObjectOffsetTable

static void Retain(NSMapTable *table, const void *obj)
{
	[(id)obj retain];
}

static void Release(NSMapTable *table, void *obj)
{
	[(id)obj release];
}

- init
{
	NSMapTableKeyCallBacks keyCallbacks = {
		NULL, //hash
		NULL, //isEqual
		Retain,
		Release,
		NULL, //describe
		nil // not a key marker
	};
	NSMapTableValueCallBacks valueCallbacks = { NULL, NULL, NULL };
	map = NSCreateMapTable(keyCallbacks, valueCallbacks, 0);
	return self;
}

- (void)dealloc
{
	NSFreeMapTable(map);
	[super dealloc];
}

- (int)offsetOfObject:obj
{
	return (int)NSMapGet(map, obj);
}

- (void)setOffset:(int)offset forObject:obj
{
	return NSMapInsert(map, obj, (void *)offset);
}

@end
