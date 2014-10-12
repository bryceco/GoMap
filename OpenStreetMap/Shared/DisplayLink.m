//
//  DisplayLink.m
//  Go Map!!
//
//  Created by Bryce on 10/9/14.
//  Copyright (c) 2014 Bryce. All rights reserved.
//

#import "DisplayLink.h"

@implementation DisplayLink

-(instancetype)init
{
	self = [super init];
	if ( self ) {
		_blockDict = [NSMutableDictionary new];
	}
	return self;
}

-(void)update:(CADisplayLink *)displayLink
{
	[_blockDict enumerateKeysAndObjectsUsingBlock:^(NSString * name, void (^block)(void), BOOL *stop) {
		block();
	}];
}

-(double)duration
{
	return _displayLink.duration;
}
-(CFTimeInterval)timestamp
{
	return _displayLink.timestamp;
}

-(void)addName:(NSString *)name block:(void(^)(void))block;
{
	if ( _displayLink == nil ) {
		_displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(update:)];
		[_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
	}

	[_blockDict setObject:block forKey:name];
}

-(void)removeName:(NSString *)name;
{
	[_blockDict removeObjectForKey:name];

	if ( _blockDict.count == 0 ) {
		[_displayLink removeFromRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
		_displayLink = nil;
	}
}

-(void)dealloc
{
	for ( NSString * name in _blockDict.allKeys ) {
		[self removeName:name];
	}
}
@end
