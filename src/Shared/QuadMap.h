//
//  QuadMap.h
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 10/10/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "QuadBox.h"

@class OsmBaseObject;

@interface QuadMap : NSObject <NSCoding>
@property (strong,nonatomic)	QuadBox	*	rootQuad;

-(NSInteger)count;
-(id)initWithRect:(OSMRect)rect;

// Region
-(NSArray *)newQuadsForRect:(OSMRect)newRect;
-(void)mergeDerivedRegion:(QuadMap *)other success:(BOOL)success;
-(void)makeWhole:(QuadBox *)quad success:(BOOL)success;

// Spatial
-(void)updateMember:(OsmBaseObject *)member fromBox:(OSMRect)bbox undo:(MyUndoManager *)undo;
-(void)addMember:(OsmBaseObject *)member undo:(MyUndoManager *)undo;
-(BOOL)removeMember:(OsmBaseObject *)member undo:(MyUndoManager *)undo;
-(void)findObjectsInArea:(OSMRect)bbox block:(void (^)(OsmBaseObject * obj))block;

// these are for purging old data:
-(BOOL)discardQuadsOlderThanDate:(NSDate *)date;
-(NSDate *)discardOldestQuads:(double)fraction oldest:(NSDate *)oldest;
-(BOOL)pointIsCovered:(OSMPoint)point;
-(BOOL)nodesAreCovered:(NSArray *)nodeList;
-(void)deleteObjectsWithPredicate:(BOOL(^)(OsmBaseObject * obj))predicate;

-(void)consistencyCheckNodes:(NSArray *)nodes ways:(NSArray *)ways relations:(NSArray *)relations;

@end
