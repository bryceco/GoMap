//
//  OsmObjects.h
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 10/27/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import "OsmBaseObject.h"

@class CAShapeLayer;
@class CurvedTextLayer;
@class OsmBaseObject;
@class OsmMapData;
@class OsmMember;
@class OsmNode;
@class OsmWay;
@class UndoManager;

BOOL IsInterestingTag(NSString * key);
NSDictionary * MergeTags(NSDictionary * myself, NSDictionary * tags, BOOL failOnConflict);


BOOL IsOsmBooleanTrue( NSString * value );
BOOL IsOsmBooleanFalse( NSString * value );

@interface OsmNode : OsmBaseObject <NSCoding>
{
}
@property (readonly,nonatomic)	double		lat;
@property (readonly,nonatomic)	double		lon;
@property (readonly,nonatomic)	NSInteger	wayCount;
@property (assign,nonatomic)	OsmWay	*	turnRestrictionParentWay;	// temporarily used during turn restriction processing

-(void)setLongitude:(double)longitude latitude:(double)latitude undo:(UndoManager *)undo;
-(void)setWayCount:(NSInteger)wayCount undo:(UndoManager *)undo;

-(OSMPoint)location;
-(BOOL)isBetterToKeepThan:(OsmNode *)node;

@end



@interface OsmWay : OsmBaseObject <NSCoding>
{
	NSMutableArray	*	_nodes;
}
@property (readonly,nonatomic)	NSArray *	nodes;

-(void)constructNode:(NSNumber *)node;
-(void)constructNodeList:(NSMutableArray *)nodes;
-(void)removeNodeAtIndex:(NSInteger)index undo:(UndoManager *)undo;
-(void)addNode:(OsmNode *)node atIndex:(NSInteger)index undo:(UndoManager *)undo;

-(void)resolveToMapData:(OsmMapData *)mapData;
-(OSMPoint)centerPoint;
-(OSMPoint)centerPointWithArea:(double *)area;
-(double)lengthInMeters;
-(ONEWAY)computeIsOneWay;
-(BOOL)sharesNodesWithWay:(OsmWay *)way;
-(BOOL)isArea;
-(BOOL)isClosed;
-(BOOL)isClockwise;
-(double)wayArea;
-(BOOL)isMultipolygonMember;
-(BOOL)isSimpleMultipolygonOuterMember;
+(BOOL)isClockwiseArrayOfNodes:(NSArray *)nodes;
+(CGPathRef)shapePathForNodes:(NSArray *)nodes forward:(BOOL)forward withRefPoint:(OSMPoint *)pRefPoint CF_RETURNS_RETAINED;
-(BOOL)hasDuplicatedNode;
-(OsmNode *)connectsToWay:(OsmWay *)way;
-(NSInteger)segmentClosestToPoint:(OSMPoint)point;
@end



@interface OsmRelation : OsmBaseObject <NSCoding>
{
	NSMutableArray	*	_members;
}
@property (readonly,nonatomic)	NSArray	*	members;

-(void)constructMember:(OsmMember *)member;

-(void)resolveToMapData:(OsmMapData *)mapData;
-(NSSet *)allMemberObjects;

-(void)removeMemberAtIndex:(NSInteger)index undo:(UndoManager *)undo;
-(void)addMember:(OsmMember *)member atIndex:(NSInteger)index undo:(UndoManager *)undo;
-(void)assignMembers:(NSArray *)members undo:(UndoManager *)undo;

-(BOOL)isMultipolygon;
-(BOOL)isRestriction;
-(BOOL)isRoute;

-(OsmMember *)memberByRole:(NSString *)role;
-(NSArray *)membersByRole:(NSString *)role;
-(OsmMember *)memberByRef:(OsmBaseObject *)ref;

-(NSMutableArray *)waysInMultipolygon;
-(NSArray *)buildMultipolygonRepairing:(BOOL)repairing;
+(NSArray *)buildMultipolygonFromMembers:(NSArray *)memberList repairing:(BOOL)repairing isComplete:(BOOL *)isComplete;

-(OSMPoint)centerPoint;

-(BOOL)containsObject:(OsmBaseObject *)object;

-(void)deresolveRefs;

@end



@interface OsmMember : NSObject <NSCoding>
{
	NSString *	_type;	// way, node, or relation: to help identify ref
	id			_ref;
	NSString *	_role;
}
@property (readonly,nonatomic)	NSString *	type;
@property (readonly,nonatomic)	id			ref;
@property (readonly,nonatomic)	NSString *	role;

-(id)initWithType:(NSString *)type ref:(NSNumber *)ref role:(NSString *)role;
-(id)initWithRef:(OsmBaseObject *)ref role:(NSString *)role;
-(void)resolveRefToObject:(OsmBaseObject *)object;

-(BOOL)isNode;
-(BOOL)isWay;
-(BOOL)isRelation;
@end
