//
//  QuadMap.m
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 10/10/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import "QuadMap.h"
#import "UndoManager.h"


static const OSMRect MAP_RECT = { -180, -90, 360, 180 };


@implementation QuadMap

#pragma mark Common

-(instancetype)initWithRect:(OSMRect)rect
{
	self = [super init];
	if ( self ) {
		_rootQuad = [[QuadBox alloc] initWithRect:rect];
	}
	return self;
}

-(instancetype)init
{
	return [self initWithRect:MAP_RECT];
}

-(void)dealloc
{
	[_rootQuad deleteCpp];	// cpp has a strong reference to this so we need to reset it manually
}

-(NSInteger)count
{
	return [_rootQuad count];
}

-(void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeObject:_rootQuad forKey:@"rootQuad"];
}

-(id)initWithCoder:(NSCoder *)coder
{
	self = [super init];
	if ( self ) {
		_rootQuad	= [coder decodeObjectForKey:@"rootQuad"];
	}
	return self;
}


#pragma mark Regions

-(void)mergeDerivedRegion:(QuadMap *)other success:(BOOL)success
{
	assert( other.count == 1 );
	[self makeWhole:other->_rootQuad success:success];
}

-(NSArray *)newQuadsForRect:(OSMRect)newRect
{
	NSMutableArray * quads = [NSMutableArray new];

	assert( newRect.origin.x >= -180.0 && newRect.origin.x <= 180.0 );
	if ( newRect.origin.x + newRect.size.width > 180 ) {
		OSMRect half;
		half.origin.x = -180;
		half.size.width = newRect.origin.x + newRect.size.width - 180;
		half.origin.y = newRect.origin.y;
		half.size.height = newRect.size.height;
		[_rootQuad missingPieces:quads intersectingRect:half];
		newRect.size.width = 180 - newRect.origin.x;
	}
	[_rootQuad missingPieces:quads intersectingRect:newRect];
	return quads;
}

-(void)makeWhole:(QuadBox *)quad success:(BOOL)success
{
	[quad makeWhole:success];
}

#pragma mark Spatial

-(void)addMember:(OsmBaseObject *)member undo:(UndoManager *)undo
{
	if ( undo ) {
		[undo registerUndoWithTarget:self selector:@selector(removeMember:undo:) objects:@[member,undo]];
	}
	[self.rootQuad addMember:member bbox:member.boundingBox];
}
-(BOOL)removeMember:(OsmBaseObject *)member undo:(UndoManager *)undo
{
	BOOL ok = [self.rootQuad removeMember:member bbox:member.boundingBox];
	if ( ok && undo ) {
		[undo registerUndoWithTarget:self selector:@selector(addMember:undo:) objects:@[member,undo]];
	}
	return ok;
}
-(void)updateMember:(OsmBaseObject *)member toBox:(OSMRect)toBox fromBox:(OSMRect)fromBox undo:(UndoManager *)undo
{
	QuadBox * fromQuad = [_rootQuad getQuadBoxMember:member bbox:fromBox];
	if ( fromQuad ) {
		if ( OSMRectContainsRect( fromQuad.rect, toBox ) ) {
			// It fits in its current box. It might fit into a child, but this path is rare and not worth optimizing.
			return;
		}
		[fromQuad removeMember:member bbox:fromBox];
		[_rootQuad addMember:member bbox:toBox];
		if ( undo ) {
			NSData * toData = [NSData dataWithBytes:&toBox length:sizeof toBox];
			NSData * fromData = [NSData dataWithBytes:&fromBox length:sizeof fromBox];
			[undo registerUndoWithTarget:self selector:@selector(updateMemberBoxed:toBox:fromBox:undo:) objects:@[member,fromData,toData,undo]];
		}
	} else {
		[_rootQuad addMember:member bbox:toBox];
		if ( undo ) {
			[undo registerUndoWithTarget:self selector:@selector(removeMember:undo:) objects:@[member,undo]];
		}
	}
}
// This is just like updateMember but allows boxed arguments so the undo manager can call it
-(void)updateMemberBoxed:(OsmBaseObject *)member toBox:(NSData *)toBox fromBox:(NSData *)fromBox undo:(UndoManager *)undo
{
	const OSMRect * to = (const OSMRect *)toBox.bytes;
	const OSMRect * from = (const OSMRect *)fromBox.bytes;
	[self updateMember:member toBox:*to fromBox:*from undo:undo];
}
-(void)updateMember:(OsmBaseObject *)member fromBox:(OSMRect)bbox undo:(UndoManager *)undo
{
	[self updateMember:member toBox:member.boundingBox fromBox:bbox undo:undo];
}

-(void)findObjectsInArea:(OSMRect)bbox block:(void (^)(OsmBaseObject *))block
{
	[_rootQuad findObjectsInArea:bbox block:block];
}


#pragma mark Purge objects

-(BOOL)discardQuadsOlderThanDate:(NSDate *)date
{
	return [_rootQuad discardQuadsOlderThanDate:date];
}
-(NSDate *)discardOldestQuads:(double)fraction oldest:(NSDate *)oldest
{
	return [_rootQuad discardOldestQuads:fraction oldest:oldest];
}

-(BOOL)pointIsCovered:(OSMPoint)point
{
	return [_rootQuad pointIsCovered:point];
}
-(BOOL)nodesAreCovered:(NSArray *)nodeList
{
	return [_rootQuad nodesAreCovered:nodeList];
}
-(void)deleteObjectsWithPredicate:(BOOL(^)(OsmBaseObject * obj))predicate
{
	[_rootQuad deleteObjectsWithPredicate:predicate];
}


@end
