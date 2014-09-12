//
//  MAKeyedUnarchiver.m
//  MAKeyedArchiver
//
//  Created by Michael Ash on Thu Nov 20 2003.
//  Copyright (c) 2003 __MyCompanyName__. All rights reserved.
//

#import <openssl/md5.h>
#import "MAKeyedUnarchiver.h"
#import "MAKeyedArchiver.h"
#import "MAObjectStack.h"
#import "MANSDataAdditions.h"


/*
 
 Basic decoding strategy:
 
 First, load the class and string tables into memory.
 
 Then decode the root 'object', which in turn decodes everything else.
 
 Context is kept in a stack; when decoding an object, new context for that object is pushed.
 Context needs to hold the string table for that object, the nonKeyedIndex.
 
 */

@interface MAKeyedUnarchiverContext : NSObject {
	NSMutableDictionary *lengths;
	NSMutableDictionary *offsets;
	int nonKeyedIndex;
}

- (void)addKey:(NSString *)key atOffset:(int)offset ofLength:(int)length;
- (int)lengthForKey:(NSString *)key;
- (int)offsetForKey:(NSString *)key;
- (int)nextNonKeyedIndex;

@end

@implementation MAKeyedUnarchiverContext

- init
{
	lengths = [[NSMutableDictionary alloc] init];
	offsets = [[NSMutableDictionary alloc] init];
	return self;
}

- (void)dealloc
{
	[lengths release];
	[offsets release];
	[super dealloc];
}

- (void)addKey:(NSString *)key atOffset:(int)offset ofLength:(int)length
{
	[lengths setObject:[NSNumber numberWithInt:length] forKey:key];
	[offsets setObject:[NSNumber numberWithInt:offset] forKey:key];
}

- (int)lengthForKey:(NSString *)key
{
	return [[lengths objectForKey:key] intValue];
}

- (int)offsetForKey:(NSString *)key
{
	return [[offsets objectForKey:key] intValue];
}

- (int)nextNonKeyedIndex
{
	return nonKeyedIndex++;
}

@end



@interface MAKeyedUnarchiverClass : NSObject {
	Class class;
	int version;
}

+ classWithClass:(Class)c version:(int)v;
- (Class)repClass;
- (int)version;

@end

@implementation MAKeyedUnarchiverClass

+ classWithClass:(Class)c version:(int)v
{
	MAKeyedUnarchiverClass *obj = [[self alloc] init];
	obj->class = c;
	obj->version = v;
	return [obj autorelease];
}

- (Class)repClass
{
	return class;
}

- (int)version
{
	return version;
}

@end


@interface MAKeyedUnarchiver (Private)

- (void)pushContextForDataAtOffset:(int)offset;
- (long long)_decodeIntTypeForKey:(NSString *)key;
- (double)_decodeDoubleTypeForKey:(NSString *)key;

// Jaguar compatibility
- (NSArray *)_decodeArrayOfObjectsForKey:(NSString *)key;

@end

@implementation MAKeyedUnarchiver (Private)

- (void)pushContextForDataAtOffset:(int)offset
{
	int stringOffset;
	id context = [[MAKeyedUnarchiverContext alloc] init];
	while( (stringOffset = *((int *)([archive bytes] + offset))) != -1) // -1 means stop
	{
		NSString *key = [stringTable objectAtIndex:stringOffset];
		offset += 4; // get past string index
		int length = *((int *)([archive bytes] + offset));
		length &= 0x0FFFFFFF; // top four bits are reserved, mask them off
		offset += 4; // get past length
		
		[context addKey:key atOffset:offset ofLength:length];
		
		offset += length; // go to next piece of data;
	}
	[contextStack push:context];
	// don't release here, the stack doesn't retain stuff
}	

- (long long)_decodeIntTypeForKey:(NSString *)key
{
	long long val = 0;
	id context = [contextStack peek];
	int len = [context lengthForKey:key];
	if(len == 0)
		return 0;
	int offset = [context offsetForKey:key];
	memcpy( ((void *)&val) + (sizeof(val) - len), [archive bytes] + offset, len);
	return val;
}

- (double)_decodeDoubleTypeForKey:(NSString *)key
{
	id context = [contextStack peek];
	int len = [context lengthForKey:key];
	int offset = [context offsetForKey:key];
	if(len == 0)
		return 0.0;
	else if(len == 4)
		return *((float *)([archive bytes] + offset));
	else if(len == 8)
		return *((double *)([archive bytes] + offset));
	else
	{
		MyErrorLog(@"bad floating-point size %d", len);
	}
	return 0.0;
}

- (NSArray *)_decodeArrayOfObjectsForKey:(NSString *)key
{
	NSMutableArray *array = [NSMutableArray array];
	int count = 0;
	id obj;
	do {
		obj = [self decodeObjectForKey:[NSString stringWithFormat:@"NS.object.%d", count]];
		if(obj) [array addObject:obj];
		count++;
	} while(obj);
	return array;
}

@end


@implementation MAKeyedUnarchiver

+ unarchiveObjectWithData:(NSData *)data
{
	MAKeyedUnarchiver *unarchiver = [[self alloc] initForReadingWithData:data];
	id obj = [[unarchiver decodeObject] retain];
	[unarchiver finishDecoding];
	[unarchiver release];
	return [obj autorelease];
}

- (id)initForReadingWithData:(NSData *)data
{
	if((self = [super init]))
	{
#define BAD_DATA_ABORT do { [self release]; [NSException raise:@"MAKeyedUnarchiverBadFileFormat" format:NSLocalizedString(@"File is corrupt or of the wrong format.", @"unarchiver error")]; } while (0)
		// first, verify archive
		if([data length] < MD5_DIGEST_LENGTH + 4)
			BAD_DATA_ABORT;
		const int *magicCookie = [data bytes] + MD5_DIGEST_LENGTH;
		if(*magicCookie != 'MAkA')
			BAD_DATA_ABORT;
		NSData *compressedData = [data subdataWithRange:NSMakeRange(MD5_DIGEST_LENGTH + 4, [data length] - MD5_DIGEST_LENGTH - 4)];
		char md5[MD5_DIGEST_LENGTH];
		MD5([compressedData bytes], [compressedData length], md5);
		if(memcmp(md5, [data bytes], MD5_DIGEST_LENGTH) != 0) // MD5 doesn't match
			BAD_DATA_ABORT;			

		archive = [[compressedData zlibDecompressed] retain];
		if(!archive)
			BAD_DATA_ABORT;
		
		contextStack = [[MAObjectStack alloc] init];
		stringTable = [[NSMutableArray alloc] init];
		classTable = [[NSMutableArray alloc] init];
		classDictionary = [[NSMutableDictionary alloc] init];
		objectDictionary = [[NSMutableDictionary alloc] init];
		
		int classTableOffset = *((int *)([archive bytes]));
		int stringTableOffset = *((int *)([archive bytes] + 4));
		int offset;
		
		if(classTableOffset >= [archive length] || stringTableOffset >= [archive length])
		{
			MyErrorLog(@"Bad class table offset (%d) or string table offset (%d) with archive length of %d", classTableOffset, stringTableOffset, [archive length]);
		}
		
		
		// load the string table first, we need it to make the class table
		offset = stringTableOffset;
		while(offset < [archive length])
		{
			[stringTable addObject:[NSString stringWithUTF8String:[archive bytes] + offset]];
			offset += strlen([archive bytes] + offset) + 1;
		}
		
		// load the class table
		offset = classTableOffset;
		while(offset < stringTableOffset)
		{
			int classStringIndex = *((int *)([archive bytes] + offset));
			int classVersion = *((int *)([archive bytes] + offset + 4));
			NSString *className = [stringTable objectAtIndex:classStringIndex];
			id classRep = [MAKeyedUnarchiverClass classWithClass:NSClassFromString(className) version:classVersion];
			[classTable addObject:classRep];
			[classDictionary setObject:classRep forKey:className];
			offset += 8;
		}
		
		// now load root-level data
		[self pushContextForDataAtOffset:8]; // root data starts aftertable offsets
	}
	return self;
}

- (void)dealloc
{
	[archive release];
	if(contextStack)
		while(![contextStack isEmpty])
			[[contextStack pop] release];
	[contextStack release];
	[stringTable release];
	[classTable release];
	[classDictionary release];
	[objectDictionary release];
	[super dealloc];
}

- (void)decodeValueOfObjCType:(const char *)type at:(void *)data
{
	id context = [contextStack peek];
	NSString *key = [NSString stringWithFormat:@"MA__%d", [context nextNonKeyedIndex]];
	switch(type[0])
	{
		case '@': // object
		case '#': // class, can it be the same?
			*((id *)data) = [[self decodeObjectForKey:key] retain];
			break;
		case ':': // SEL
			*((SEL *)data) = NSSelectorFromString([self decodeObjectForKey:key]);
			break;
		default: // non-object data
			{
				int offset = [context offsetForKey:key];
				int len = [context lengthForKey:key];
				if(len != LengthOfType(type))
				{
					MyErrorLog(@"length of stored data does not match length of requested type");
				}
				memcpy(data, [archive bytes] + offset, len);
			}
			break;
	}
}

- (NSData *)decodeDataObject
{
	id context = [contextStack peek];
	NSString *key = [NSString stringWithFormat:@"MA__%d", [context nextNonKeyedIndex]];
	int offset = [context offsetForKey:key];
	int len = [context lengthForKey:key];
	return [archive subdataWithRange:NSMakeRange(offset, len)];
}

- (unsigned)versionForClassName:(NSString *)className
{
	MAKeyedUnarchiverClass *classRep = [classDictionary objectForKey:className];
	return [classRep version];
}

- (BOOL)allowsKeyedCoding
{
	return YES;
}

- (BOOL)containsValueForKey:(NSString *)key
{
	return [[contextStack peek] offsetForKey:key] != 0;
}

- (id)decodeObjectForKey:(NSString *)key
{
	id context = [contextStack peek];
	int offset = [context offsetForKey:key];
	int len = [context lengthForKey:key];
	if(len == 0)
		return nil;
	if(len != 4)
	{
		MyErrorLog(@"bad length");
	}
	int objectOffset = *((int *)([archive bytes] + offset));
	
	// if it's nil, return nil
	if(objectOffset == 0) return nil;
	
	// if it's already been decoded, return the object
	id obj = [objectDictionary objectForKey:[NSNumber numberWithInt:objectOffset]];
	if(obj) return obj;
	
	int classIndex = *((int *)([archive bytes] + objectOffset));
	Class class = [[classTable objectAtIndex:classIndex] repClass];
	[self pushContextForDataAtOffset:objectOffset + 4]; // skip the class info
	
	// this is really evil, but necessary.
	// the object must be entered in the table *before* initWithCoder is called, otherwise
	// some (all?) cycles are not detected
	// of course, we can't hang on to the temporary object, so we have to reset
	// the entry in the table after everything is done
	obj = [class alloc];
	[objectDictionary setObject:obj forKey:[NSNumber numberWithInt:objectOffset]];
	
	// reciprocal evil Jaguar compatibility hack
	if(class == [NSString class] || class == [NSMutableString class] || class == [NSData class] || class == [NSMutableData class])
	{
		const void *data;
		unsigned length;
		data = [self decodeBytesForKey:@"__MA plist types hack" returnedLength:&length];
		if(class == [NSString class] || class == [NSMutableString class])
			obj = [obj initWithData:[NSData dataWithBytes:data length:length] encoding:NSUTF8StringEncoding];
		else
			obj = [obj initWithBytes:data length:length];
	}
	else
	{
		obj = [obj initWithCoder:self];
		obj = [obj awakeAfterUsingCoder:self];
	}
	[objectDictionary setObject:obj forKey:[NSNumber numberWithInt:objectOffset]];
	[[contextStack pop] release];
	return [obj autorelease];
}

#define INTEGER_BODY return [self _decodeIntTypeForKey:key]
- (BOOL)decodeBoolForKey:(NSString *)key
{
	INTEGER_BODY;
}

- (int)decodeIntForKey:(NSString *)key
{
	INTEGER_BODY;
}

- (int32_t)decodeInt32ForKey:(NSString *)key
{
	INTEGER_BODY;
}

- (int64_t)decodeInt64ForKey:(NSString *)key
{
	INTEGER_BODY;
}

#define FLOAT_BODY return [self _decodeDoubleTypeForKey:key]

- (float)decodeFloatForKey:(NSString *)key
{
	FLOAT_BODY;
}

- (double)decodeDoubleForKey:(NSString *)key
{
	FLOAT_BODY;
}

- (const uint8_t *)decodeBytesForKey:(NSString *)key returnedLength:(unsigned *)lengthp
{
	id context = [contextStack peek];
	int offset = [context offsetForKey:key];
	int len = [context lengthForKey:key];
	if(lengthp)
		*lengthp = len;
	return [[archive subdataWithRange:NSMakeRange(offset, len)] bytes];
}

- (void)finishDecoding
{
	
}

@end
