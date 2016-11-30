//
//  DisplayLink.h
//  Go Map!!
//
//  Created by Bryce Cogswell on 10/9/14.
//  Copyright (c) 2014 Bryce Cogswell. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface DisplayLink : NSObject
{
	CADisplayLink		*	_displayLink;
	NSMutableDictionary	*	_blockDict;
}
+(instancetype)shared;
-(void)addName:(NSString *)name block:(void(^)(void))block;
-(void)removeName:(NSString *)name;
-(BOOL)hasName:(NSString *)name;
-(CFTimeInterval)duration;
-(CFTimeInterval)timestamp;
@end
