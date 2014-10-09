//
//  DisplayLink.h
//  Go Map!!
//
//  Created by Bryce on 10/9/14.
//  Copyright (c) 2014 Bryce. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface DisplayLink : NSObject
{
	CADisplayLink		*	_displayLink;
	NSMutableDictionary	*	_blockDict;
}
-(void)addName:(NSString *)name block:(void(^)(void))block;
-(void)removeName:(NSString *)name;
-(CFTimeInterval)duration;
-(CFTimeInterval)timestamp;
@end
