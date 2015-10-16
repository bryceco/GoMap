//
//  DisplayLink.m
//  Go Map!!
//
//  Created by Bryce on 10/9/14.
//  Copyright (c) 2014 Bryce. All rights reserved.
//

#import "DisplayLink.h"

@implementation DisplayLink

+(instancetype)shared
{
	static DisplayLink * g_shared;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		g_shared = [DisplayLink new];
	});
	return g_shared;
}


-(instancetype)init
{
	self = [super init];
	if ( self ) {
		_blockDict = [NSMutableDictionary new];
		_displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(update:)];
		_displayLink.paused = YES;
		[_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
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
	[_blockDict setObject:block forKey:name];
	_displayLink.paused = NO;
}

-(BOOL)hasName:(NSString *)name
{
	return _blockDict[ name ] != nil;
}

-(void)removeName:(NSString *)name;
{
	[_blockDict removeObjectForKey:name];

	if ( _blockDict.count == 0 ) {
		_displayLink.paused = YES;
	}
}

-(void)dealloc
{
	[_displayLink removeFromRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
}
@end
