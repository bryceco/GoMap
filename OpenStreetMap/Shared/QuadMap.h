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


typedef const struct QuadBoxCC * QuadBoxEnumerationType;
struct QuadBoxCC;


@interface QuadBox : NSObject <NSCoding>
{
	struct QuadBoxCC *	_cpp;
}
@property (readonly,nonatomic)	OSMRect				rect;
@property (readonly,nonatomic)	struct QuadBoxCC  *	cpp;

-(id)initWithRect:(OSMRect)rect;
-(instancetype)initWithThis:(struct QuadBoxCC *)cpp;
-(void)missingPieces:(NSMutableArray *)pieces intersectingRect:(OSMRect)target;
-(void)makeWhole:(BOOL)success;
-(void)addMember:(OsmBaseObject *)member bbox:(OSMRect)bbox;
-(BOOL)removeMember:(OsmBaseObject *)member bbox:(OSMRect)bbox;
-(instancetype)getQuadBoxMember:(OsmBaseObject *)member bbox:(OSMRect)bbox;
-(void)enumerateWithBlock:(void (^)(const struct QuadBoxCC * quad))block;
-(void)findObjectsInArea:(OSMRect)bbox block:(void (^)(OsmBaseObject * obj))block;
-(void)reset;
-(void)nullifyCpp;

// these are for purging old data:
-(BOOL)discardQuadsOlderThanDate:(NSDate *)date;
-(BOOL)pointIsCovered:(OSMPoint)point;
-(BOOL)nodesAreCovered:(NSArray *)nodeList;
-(void)deleteObjectsWithPredicate:(BOOL(^)(OsmBaseObject * obj))predicate;

@end



@interface QuadMap : NSObject <NSCoding>
{
}
@property (strong,nonatomic)	QuadBox	*	rootQuad;

-(void)mergeDerivedRegion:(QuadMap *)other success:(BOOL)success;
-(id)initWithRect:(OSMRect)rect;
-(NSArray *)newQuadsForRect:(OSMRect)newRect;
-(void)makeWhole:(QuadBox *)quad success:(BOOL)success;
-(void)findObjectsInArea:(OSMRect)bbox block:(void (^)(OsmBaseObject * obj))block;

-(void)updateMember:(OsmBaseObject *)member fromBox:(OSMRect)bbox undo:(UndoManager *)undo;
-(void)addMember:(OsmBaseObject *)member undo:(UndoManager *)undo;
-(BOOL)removeMember:(OsmBaseObject *)member undo:(UndoManager *)undo;

-(NSInteger)count;

// these are for purging old data:
-(BOOL)discardQuadsOlderThanDate:(NSDate *)date;
-(BOOL)pointIsCovered:(OSMPoint)point;
-(BOOL)nodesAreCovered:(NSArray *)nodeList;
-(void)deleteObjectsWithPredicate:(BOOL(^)(OsmBaseObject * obj))predicate;

@end
