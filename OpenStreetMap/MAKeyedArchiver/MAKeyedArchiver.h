//
//  MAKeyedArchiver.h
//  MAKeyedArchiver
//
//  Created by Michael Ash on Thu Nov 20 2003.
//  Copyright (c) 2003 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

@class MAStringTable;
@class MAObjectOffsetTable;
@class MAObjectSet;
@class MAObjectOffsetStack;
@class MAObjectStack;

int LengthOfType(const char *type);

@interface MAKeyedArchiver : NSCoder {
	NSMutableData *archive;
	unsigned curNonkeyedIndex;
	
	MAStringTable *stringTable;
	MAStringTable *classTable;
	
	MAObjectOffsetTable *objectOffsetTable;
	MAObjectSet *pendingEncodesTable;
	MAObjectOffsetStack *delayedEncodesTable;
	MAObjectStack *encodeStack;
}

+ (NSData *)archivedDataWithRootObject:(id)rootObject;

- (id)initForWritingWithMutableData:(NSMutableData *)mdata;

- (void)encodeValueOfObjCType:(const char *)type at:(const void *)addr;
- (void)encodeDataObject:(NSData *)data;

- (BOOL)allowsKeyedCoding;

- (void)encodeObject:(id)objv forKey:(NSString *)key;
- (void)encodeConditionalObject:(id)objv forKey:(NSString *)key;
- (void)encodeBool:(BOOL)boolv forKey:(NSString *)key;
- (void)encodeInt:(int)intv forKey:(NSString *)key;
- (void)encodeInt32:(int32_t)intv forKey:(NSString *)key;
- (void)encodeInt64:(int64_t)intv forKey:(NSString *)key;
- (void)encodeFloat:(float)realv forKey:(NSString *)key;
- (void)encodeDouble:(double)realv forKey:(NSString *)key;
- (void)encodeBytes:(const uint8_t *)bytesp length:(unsigned)lenv forKey:(NSString *)key;

- (void)finishEncoding;

@end
