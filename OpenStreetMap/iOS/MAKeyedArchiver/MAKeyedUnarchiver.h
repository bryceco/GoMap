//
//  MAKeyedUnarchiver.h
//  MAKeyedArchiver
//
//  Created by Michael Ash on Thu Nov 20 2003.
//  Copyright (c) 2003 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>


@class MAObjectStack;

@interface MAKeyedUnarchiver : NSCoder {
	MAObjectStack *contextStack;
	NSData *archive;
	NSMutableArray *stringTable;
	NSMutableArray *classTable;
	NSMutableDictionary *classDictionary;
	NSMutableDictionary *objectDictionary;
}

+ unarchiveObjectWithData:(NSData *)data;
- (id)initForReadingWithData:(NSData *)data;

- (void)decodeValueOfObjCType:(const char *)type at:(void *)data;
- (NSData *)decodeDataObject;
- (unsigned)versionForClassName:(NSString *)className;

- (BOOL)allowsKeyedCoding;

- (BOOL)containsValueForKey:(NSString *)key;
- (id)decodeObjectForKey:(NSString *)key;
- (BOOL)decodeBoolForKey:(NSString *)key;
- (int)decodeIntForKey:(NSString *)key;
- (int32_t)decodeInt32ForKey:(NSString *)key;
- (int64_t)decodeInt64ForKey:(NSString *)key;
- (float)decodeFloatForKey:(NSString *)key;
- (double)decodeDoubleForKey:(NSString *)key;
- (const uint8_t *)decodeBytesForKey:(NSString *)key returnedLength:(unsigned *)lengthp;

- (void)finishDecoding;

@end
