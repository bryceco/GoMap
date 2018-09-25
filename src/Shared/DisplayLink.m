//
//  DisplayLink.m
//  Go Map!!
//
//  Created by Bryce Cogswell on 10/9/14.
//  Copyright (c) 2014 Bryce Cogswell. All rights reserved.
//

#import "DisplayLink.h"

#if !TARGET_OS_IPHONE
#define CADisplayLink void
#endif


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
#if TARGET_OS_IPHONE
		_displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(update:)];
		_displayLink.paused = YES;
		[_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
#else
		CGDirectDisplayID   displayID = CGMainDisplayID();
		CVDisplayLinkCreateWithCGDisplay(displayID, &_displayLink);
		CVDisplayLinkSetOutputCallback(_displayLink, displayLinkCallback, (__bridge void *)self);
#endif
	}
	return self;
}

-(void)update:(CADisplayLink *)displayLink
{
	[_blockDict enumerateKeysAndObjectsUsingBlock:^(NSString * name, void (^block)(void), BOOL *stop) {
		block();
	}];
}

#if TARGET_OS_IPHONE
#else
CVReturn displayLinkCallback(	CVDisplayLinkRef CV_NONNULL displayLink,
								const CVTimeStamp * CV_NONNULL inNow,
								const CVTimeStamp * CV_NONNULL inOutputTime,
								CVOptionFlags flagsIn,
								CVOptionFlags * CV_NONNULL flagsOut,
								void * CV_NULLABLE displayLinkContext )
{
	DisplayLink * myself = (__bridge DisplayLink *)displayLinkContext;
	[myself update:nil];
}
#endif

-(double)duration
{
#if TARGET_OS_IPHONE
	return _displayLink.duration;
#else
	return CVDisplayLinkGetActualOutputVideoRefreshPeriod(_displayLink);
#endif
}
-(CFTimeInterval)timestamp
{
#if TARGET_OS_IPHONE
	return _displayLink.timestamp;
#else
	return CACurrentMediaTime();
#endif
}

-(void)addName:(NSString *)name block:(void(^)(void))block;
{
	[_blockDict setObject:block forKey:name];
#if TARGET_OS_IPHONE
	_displayLink.paused = NO;
#else
	CVDisplayLinkStart(_displayLink);
#endif
}

-(BOOL)hasName:(NSString *)name
{
	return _blockDict[ name ] != nil;
}

-(void)removeName:(NSString *)name;
{
	[_blockDict removeObjectForKey:name];

	if ( _blockDict.count == 0 ) {
#if TARGET_OS_IPHONE
		_displayLink.paused = YES;
#else
		CVDisplayLinkStop(_displayLink);
#endif
	}
}

-(void)dealloc
{
#if TARGET_OS_IPHONE
	[_displayLink removeFromRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
#else
	CVDisplayLinkRelease(_displayLink);
#endif
}
@end
