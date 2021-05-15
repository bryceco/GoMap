//
//  QuadBox.h
//  Go Map!!
//
//  Created by Bryce Cogswell on 5/14/21.
//  Copyright © 2021 Bryce. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface QuadBox : NSObject <NSCoding>
{
	struct QuadBoxCC *	_cpp;
}
@property (readonly,nonatomic)	OSMRect						 rect;
@property (readonly,nonatomic)	struct QuadBoxCC  *	_Nonnull cpp;

-(instancetype _Nonnull)initWithRect:(OSMRect)rect;
-(instancetype _Nonnull)initWithThis:(struct QuadBoxCC * _Nonnull)cpp;
-(void)reset;
-(void)nullifyCpp;
-(void)deleteCpp;
-(NSInteger)count;

// spatial specific
-(void)addMember:(OsmBaseObject * _Nonnull)member bbox:(OSMRect)bbox;
-(BOOL)removeMember:(OsmBaseObject * _Nonnull)member bbox:(OSMRect)bbox;
-(instancetype _Nullable)getQuadBoxMember:(OsmBaseObject * _Nonnull)member bbox:(OSMRect)bbox;
-(void)findObjectsInArea:(OSMRect)bbox block:(void (^ _Nonnull)(OsmBaseObject * _Nonnull obj))block;

// region specific
-(void)missingPieces:(NSMutableArray<QuadBox *> * _Nonnull)pieces intersectingRect:(OSMRect)target;
-(void)makeWhole:(BOOL)success;

// these are for discarding old data:
-(BOOL)discardQuadsOlderThanDate:(NSDate * _Nonnull)date;
-(NSDate * _Nullable)discardOldestQuads:(double)fraction oldest:(NSDate * _Nonnull)oldest;
-(BOOL)pointIsCovered:(OSMPoint)point;
-(BOOL)nodesAreCovered:(NSArray * _Nonnull)nodeList;
-(void)deleteObjectsWithPredicate:(BOOL(^ _Nonnull)(OsmBaseObject * _Nonnull obj))predicate;

-(void)consistencyCheckObject:(OsmBaseObject * _Nonnull)object;

@end
