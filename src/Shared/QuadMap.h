//
//  QuadMap.h
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 10/10/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef enum {
	QUAD_SE = 0,
	QUAD_SW = 1,
	QUAD_NE = 2,
	QUAD_NW = 3,
	QUAD_LAST = 3
} QUAD_ENUM;

@class OsmBaseObject;
struct QuadBoxCC;


@interface QuadBox : NSObject <NSCoding>
{
	struct QuadBoxCC *	_cpp;
}
@property (readonly,nonatomic)	OSMRect				rect;
@property (readonly,nonatomic)	struct QuadBoxCC  *	cpp;

-(id)initWithRect:(OSMRect)rect;
-(instancetype)initWithThis:(struct QuadBoxCC *)cpp;
-(void)reset;
-(void)nullifyCpp;
-(void)deleteCpp;
-(NSInteger)count;

// spatial specific
-(void)addMember:(OsmBaseObject *)member bbox:(OSMRect)bbox;
-(BOOL)removeMember:(OsmBaseObject *)member bbox:(OSMRect)bbox;
-(instancetype)getQuadBoxMember:(OsmBaseObject *)member bbox:(OSMRect)bbox;
-(void)findObjectsInArea:(OSMRect)bbox block:(void (^)(OsmBaseObject * obj))block;

// region specific
-(void)missingPieces:(NSMutableArray *)pieces intersectingRect:(OSMRect)target;
-(void)makeWhole:(BOOL)success;

// these are for discarding old data:
-(BOOL)discardQuadsOlderThanDate:(NSDate *)date;
-(NSDate *)discardOldestQuads:(double)fraction oldest:(NSDate *)oldest;
-(BOOL)pointIsCovered:(OSMPoint)point;
-(BOOL)nodesAreCovered:(NSArray *)nodeList;
-(void)deleteObjectsWithPredicate:(BOOL(^)(OsmBaseObject * obj))predicate;

-(void)consistencyCheckObject:(OsmBaseObject *)object;

@end



@interface QuadMap : NSObject <NSCoding>
@property (strong,nonatomic)	QuadBox	*	rootQuad;

-(NSInteger)count;
-(id)initWithRect:(OSMRect)rect;

// Region
-(NSArray *)newQuadsForRect:(OSMRect)newRect;
-(void)mergeDerivedRegion:(QuadMap *)other success:(BOOL)success;
-(void)makeWhole:(QuadBox *)quad success:(BOOL)success;

// Spatial
-(void)updateMember:(OsmBaseObject *)member fromBox:(OSMRect)bbox undo:(UndoManager *)undo;
-(void)addMember:(OsmBaseObject *)member undo:(UndoManager *)undo;
-(BOOL)removeMember:(OsmBaseObject *)member undo:(UndoManager *)undo;
-(void)findObjectsInArea:(OSMRect)bbox block:(void (^)(OsmBaseObject * obj))block;

// these are for purging old data:
-(BOOL)discardQuadsOlderThanDate:(NSDate *)date;
-(NSDate *)discardOldestQuads:(double)fraction oldest:(NSDate *)oldest;
-(BOOL)pointIsCovered:(OSMPoint)point;
-(BOOL)nodesAreCovered:(NSArray *)nodeList;
-(void)deleteObjectsWithPredicate:(BOOL(^)(OsmBaseObject * obj))predicate;

-(void)consistencyCheckNodes:(NSArray *)nodes ways:(NSArray *)ways relations:(NSArray *)relations;

@end
