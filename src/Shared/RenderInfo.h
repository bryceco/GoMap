//
//  RenderInfo.h
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 10/4/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <Foundation/Foundation.h>

@class OsmBaseObject;

@interface RenderInfo : NSObject
{
	NSInteger	_renderPriority;
}
@property (strong,nonatomic)	NSString	*	key;
@property (strong,nonatomic)	NSString	*	value;
@property (strong,nonatomic)	NSString	*	geometry;
@property (strong,nonatomic)	NSColor		*	lineColor;
@property (assign,nonatomic)	CGFloat			lineWidth;
@property (strong,nonatomic)	NSColor		*	areaColor;

-(BOOL)isAddressPoint;

-(NSInteger)renderPriority:(OsmBaseObject *)object;

@end



@interface RenderInfoDatabase : NSObject
{
	NSArray				*	_allTags;
	NSMutableDictionary *	_keyDict;
}
+(RenderInfoDatabase *)sharedRenderInfoDatabase;

-(RenderInfo *)renderInfoForObject:(OsmBaseObject *)object;

@end
