//
//  MANSDataAdditions.m
//  Creatures
//
//  Created by Michael Ash on Thu Nov 20 2003.
//  Copyright (c) 2003 __MyCompanyName__. All rights reserved.
//

#import <zlib.h>
#import "MANSDataAdditions.h"


@implementation NSData (MANSDataAdditions)

- (NSData *)zlibCompressed
{
	NSMutableData *outData = [NSMutableData data];
	[outData setLength:[self length] + ([self length] - 1) / 1000 + 1 + 12]; // 0.1% larger plus 12 bytes
	uLongf destLen = [outData length];
	if(compress2([outData mutableBytes], &destLen, [self bytes], [self length], Z_DEFAULT_COMPRESSION) != Z_OK)
		return nil;
	
	[outData setLength:destLen]; // truncate to what's used
	
	unsigned sourceLength = [self length];
	[outData appendBytes:&sourceLength length:sizeof(sourceLength)]; // we need the original length, so stick it on the end
	return outData;
}

- (NSData *)zlibDecompressed
{
	uLongf originalLength = *((int *)([self bytes] + [self length] - 4));
	NSMutableData *outData = [NSMutableData dataWithLength:originalLength];
	if(uncompress([outData mutableBytes], &originalLength, [self bytes], [self length] - 4) != Z_OK)
		return nil;
	
	return outData;
}

@end
