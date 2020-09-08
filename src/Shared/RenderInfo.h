//
//  RenderInfo.h
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 10/4/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <Foundation/Foundation.h>

@class OsmBaseObject;

static const NSInteger RenderInfoMaxPriority = (33+1)*3;


@interface RenderInfo : NSObject
{
	NSInteger	_renderPriority;
}
@property (strong,nonatomic)	NSString	*	key;
@property (strong,nonatomic)	NSString	*	value;
@property (strong,nonatomic)	NSColor		*	lineColor;
@property (assign,nonatomic)	CGFloat			lineWidth;
@property (strong,nonatomic)	NSColor		*	areaColor;

-(BOOL)isAddressPoint;

-(NSInteger)renderPriorityForObject:(OsmBaseObject *)object;

@end



@interface RenderInfoDatabase : NSObject
{
	NSArray				*	_allFeatures;
	NSMutableDictionary *	_keyDict;
}
+(RenderInfoDatabase *)sharedRenderInfoDatabase;

-(RenderInfo *)renderInfoForObject:(OsmBaseObject *)object;

@end
