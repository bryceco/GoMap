//
//  OsmObjects.h
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 10/27/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import "iosapi.h"
#import <Foundation/Foundation.h>
#import "VectorMath.h"


@class CAShapeLayer;
@class CurvedTextLayer;
@class OsmBaseObject;
@class OsmMapData;
@class OsmMember;
@class OsmNode;
@class OsmRelation;
@class OsmWay;
@class TagInfo;
@class UndoManager;

NSDictionary * MergeTags(NSDictionary * myself, NSDictionary * tags);


@interface OsmBaseObject : NSObject <NSCoding,NSCopying>
{
@protected
	int32_t				_modifyCount;
	BOOL				_constructed;
	NSDictionary	*	_tags;
	NSNumber		*	_ident;
	NSArray			*	_relations;
@public
	OSMRect				_boundingBox;
}
@property (readonly,nonatomic)	BOOL					deleted;
@property (strong,nonatomic)	NSMutableDictionary	*	renderProperties;
@property (strong,nonatomic)	TagInfo				*	tagInfo;
@property (readonly,nonatomic)	int32_t					modifyCount;
@property (readonly,nonatomic)	NSArray				*	relations;

// attributes
@property (readonly,nonatomic)	NSDictionary	*	tags;
@property (readonly,nonatomic)	NSNumber		*	ident;
@property (readonly,nonatomic)	NSString		*	user;
@property (readonly,nonatomic)	NSString		*	timestamp;
@property (readonly,nonatomic)	int32_t				version;
@property (readonly,nonatomic)	OsmIdentifier		changeset;
@property (readonly,nonatomic)	int32_t				uid;
@property (readonly,nonatomic)	BOOL				visible;

// extra stuff
@property (assign,nonatomic)	NSInteger			renderPriorityCached;
@property (assign,nonatomic)	OSMRect				boundingBox;
-(OSMRect)boundingBoxCompute;

+(NSArray *)typeKeys;
+(NSDateFormatter *)rfc3339DateFormatter;

-(void)constructTag:(NSString *)tag value:(NSString *)value;
-(void)constructBaseAttributesFromXmlDict:(NSDictionary *)attributeDict;
-(void)constructAsUserCreated:(NSString *)userName;
-(void)setConstructed;
-(void)incrementModifyCount:(UndoManager *)undo;
-(void)setTags:(NSDictionary *)tags undo:(UndoManager *)undo;
-(void)setTimestamp:(NSDate *)date undo:(UndoManager *)undo;
-(void)setDeleted:(BOOL)deleted undo:(UndoManager *)undo;
-(void)resetModifyCount:(UndoManager *)undo;
-(void)serverUpdateVersion:(NSInteger)version;
-(void)serverUpdateIdent:(OsmIdentifier)ident;
-(void)serverUpdateInPlace:(OsmBaseObject *)newerVersion;
-(void)addRelation:(OsmRelation *)relation undo:(UndoManager *)undo;
-(void)removeRelation:(OsmRelation *)relation undo:(UndoManager *)undo;

-(OsmNode *)isNode;
-(OsmWay *)isWay;
-(OsmRelation *)isRelation;

-(NSDate *)dateForTimestamp;

-(NSSet *)nodeSet;
-(BOOL)overlapsBox:(OSMRect)box;
-(OSMRect)boundingBox;
-(NSString *)friendlyDescription;

-(BOOL)hasInterestingTags;

-(BOOL)isCoastline;

-(BOOL)isModified;

+(NSInteger)nextUnusedIdentifier;
@end



@interface OsmNode : OsmBaseObject <NSCoding>
{
}
@property (readonly,nonatomic)	double		lat;
@property (readonly,nonatomic)	double		lon;
@property (readonly,nonatomic)	NSInteger	wayCount;

-(void)setLongitude:(double)longitude latitude:(double)latitude undo:(UndoManager *)undo;
-(void)setWayCount:(NSInteger)wayCount undo:(UndoManager *)undo;

-(OSMPoint)location;
@end



@interface OsmWay : OsmBaseObject <NSCoding>
{
	NSMutableArray	*	_nodes;
}
@property (readonly,nonatomic)	NSArray *	nodes;

-(void)constructNode:(NSNumber *)node;
-(void)removeNodeAtIndex:(NSInteger)index undo:(UndoManager *)undo;
-(void)addNode:(OsmNode *)node atIndex:(NSInteger)index undo:(UndoManager *)undo;

-(void)resolveToMapData:(OsmMapData *)mapData;
-(OSMPoint)centerPoint;
-(OSMPoint)centerPointWithArea:(double *)area;
-(BOOL)isArea;
-(BOOL)isClosed;
-(BOOL)isOneWay;
-(BOOL)isSimpleMultipolygonOuterMember;
-(double)wayArea;
-(OSMPoint)pointOnWayForPoint:(OSMPoint)point;

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

-(BOOL)isRestriction;
-(OsmMember *)memberByRole:(NSString *)role;

-(BOOL)isMultipolygon;
-(OSMPoint)centerPoint;

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
