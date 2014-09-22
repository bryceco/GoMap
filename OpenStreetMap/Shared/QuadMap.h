//
//  QuadMap.h
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 10/10/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <Foundation/Foundation.h>


typedef enum {
	QUAD_NW,
	QUAD_SW,
	QUAD_SE,
	QUAD_NE,
	QUAD_LAST = 3
} QUAD_ENUM;

@class OsmBaseObject;


@interface QuadBox : NSObject <NSCoding>
{
	@public
	QuadBox			*	_children[ 4 ];
	QuadBox			*	_parent;
	BOOL				_whole;				// fully downloaded
	BOOL				_busy;				// currently downloading
	NSMutableArray	*	_members;
	BOOL				_isSplit;
}
@property (readonly,nonatomic)	OSMRect		rect;

-(id)initWithRect:(OSMRect)rect parent:(QuadBox *)parent;
-(void)findObjectsInArea:(OSMRect)bbox block:(void (^)(OsmBaseObject * obj))block;
-(NSInteger)quadCount;
-(NSInteger)memberCount;
-(void)reset;

@end



@interface QuadMap : NSObject <NSCoding>
{
}
@property (strong,nonatomic)	QuadBox	*	rootQuad;

-(void)mergeDerivedRegion:(QuadMap *)other success:(BOOL)success;
-(id)initWithRect:(OSMRect)rect;
-(NSArray *)newQuadsForRect:(OSMRect)newRect;
-(void)makeWhole:(QuadBox *)quad success:(BOOL)success;
-(NSInteger)count;
-(void)enumerateWithBlock:(void (^)(QuadBox * quad))block;
-(void)findObjectsInArea:(OSMRect)bbox block:(void (^)(OsmBaseObject * obj))block;

-(void)updateMember:(OsmBaseObject *)member fromBox:(OSMRect)bbox undo:(UndoManager *)undo;
-(void)addMember:(OsmBaseObject *)member undo:(UndoManager *)undo;
-(BOOL)removeMember:(OsmBaseObject *)member undo:(UndoManager *)undo;

@end
