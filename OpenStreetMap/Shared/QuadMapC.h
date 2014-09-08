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

class QuadBoxCC;

@interface QuadBoxC : NSObject <NSCoding>
{
	QuadBoxCC * _cpp;
}
@property (readonly,nonatomic)	OSMRect		rect;

-(id)initWithRect:(OSMRect)rect;
-(void)addMember:(OsmBaseObject *)member undo:(UndoManager *)undo;
-(BOOL)removeMember:(OsmBaseObject *)member undo:(UndoManager *)undo;
-(void)findObjectsInArea:(OSMRect)bbox block:(void (^)(OsmBaseObject *))block;
-(NSInteger)quadCount;
-(NSInteger)memberCount;
-(void)reset;

@end



@interface QuadMapC : NSObject <NSCoding>
{
}
@property (readonly,nonatomic)	QuadBoxC	*	rootQuad;

-(void)mergeDerivedRegion:(QuadMapC *)other success:(BOOL)success;
-(id)initWithRect:(OSMRect)rect;
-(NSArray *)newQuadsForRect:(OSMRect)newRect;
-(void)makeWhole:(QuadBoxC *)quad success:(BOOL)success;
-(NSInteger)count;
//-(void)enumerateWithBlock:(void (^)(QuadBoxC * quad))block;
-(void)addMember:(OsmBaseObject *)member;
-(void)removeMember:(OsmBaseObject *)member;
-(void)findObjectsInArea:(OSMRect)bbox block:(void (^)(OsmBaseObject *))block;

@end
