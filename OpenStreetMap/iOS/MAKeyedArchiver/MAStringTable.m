//
//  MAStringTable.m
//  MAKeyedArchiver
//
//  Created by Michael Ash on Thu Nov 20 2003.
//  Copyright (c) 2003 __MyCompanyName__. All rights reserved.
//

#import "MAStringTable.h"
#import "MAObjectOffsetTable.h"


@implementation MAStringTable

static void Retain(NSMapTable *table, const void *obj)
{
	[(id)obj retain];
}

static void Release(NSMapTable *table, void *obj)
{
	[(id)obj release];
}

static BOOL IsEqual(NSMapTable *table, const void *obj1, const void *obj2)
{
	return [(NSString *)obj1 isEqualToString:(NSString *)obj2];
}

static unsigned Hash(NSMapTable *table, const void *obj)
{
	return [(NSString *)obj hash];
}

- init
{
	NSMapTableKeyCallBacks keyCallbacks = {
		Hash, //hash
		IsEqual, //isEqual
		Retain,
		Release,
		NULL, //describe
		nil // not a key marker
	};
	NSMapTableValueCallBacks valueCallbacks = { NULL, NULL, NULL };
	map = NSCreateMapTable(keyCallbacks, valueCallbacks, 0);
	strings = [[NSMutableArray alloc] init];
	return self;
}

- (void)dealloc
{
	NSFreeMapTable(map);
	[strings release];
	[super dealloc];
}

- (int)offsetOfObject:obj
{
	return ((int)NSMapGet(map, obj)) - 1;
}

- (void)setOffset:(int)offset forObject:obj
{
	offset++;
	return NSMapInsert(map, obj, (void *)offset);
}

- (unsigned)indexOfString:(NSString *)str
{
	int offset = [self offsetOfObject:str];
	if(offset == -1)
	{
		offset = [strings count];
		[self setOffset:offset forObject:str];
		[strings addObject:str];
	}
	if(offset >= [strings count])
	{
		MyErrorLog(@"Bad offset for string %@", str);
		return 0;
	}
	return offset;
}

- (NSArray *)strings
{
	return strings;
}

- (unsigned)count
{
	return NSCountMapTable(map);
}


@end
