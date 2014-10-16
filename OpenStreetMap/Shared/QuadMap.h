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

#define USE_QUAD_C 1

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

-(id)initWithRect:(OSMRect)rect;
-(void)findObjectsInArea:(OSMRect)bbox block:(void (^)(OsmBaseObject * obj))block;
-(void)reset;

@end

#if USE_QUAD_C
#define QuadBox QuadBoxC
typedef const struct QuadBoxCC * QuadBoxEnumerationType;
#else
typedef QuadBox * QuadBoxEnumerationType;
#endif


struct QuadBoxCC;

@interface QuadBoxC : NSObject <NSCoding>
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
@end
