//
//  OsmBaseObject.h
//  Go Map!!
//
//  Created by Wolfgang Timme on 1/18/20.
//  Copyright © 2020 Bryce. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "VectorMath.h"
#import "iosapi.h"

@class RenderInfo;
@class UndoManager;
@class OsmNode;
@class OsmWay;
@class OsmRelation;

extern const double PATH_SCALING;

#define GEOMETRY_AREA @"area"
#define GEOMETRY_WAY @"line"
#define GEOMETRY_NODE @"point"
#define GEOMETRY_VERTEX @"vertex"

typedef enum {
    OSM_TYPE_NODE        = 1,
    OSM_TYPE_WAY        = 2,
    OSM_TYPE_RELATION    = 3
} OSM_TYPE;

typedef enum {
    ONEWAY_BACKWARD    = -1,
    ONEWAY_NONE        = 0,
    ONEWAY_FORWARD    = 1,
} ONEWAY;

typedef enum {
    TRISTATE_UNKNOWN,
    TRISTATE_YES,
    TRISTATE_NO
} TRISTATE;

BOOL IsInterestingKey(NSString * _Nonnull key);

NSDictionary * _Nullable MergeTags(NSDictionary * _Nullable myself, NSDictionary * _Nullable tags, BOOL failOnConflict);

@interface OsmBaseObject : NSObject <NSCoding,NSCopying>
{
@protected
	int32_t                						_modifyCount;
	BOOL                						_constructed;
	NSDictionary<NSString *, NSString *>    *	_tags;
	NSNumber        						*  	_ident;
	NSArray						            *  	_parentRelations;

	NSNumber        						*	_isOneWay;
@public
	OSMRect                						_boundingBox;
	NSInteger						           	renderPriorityCached;
}
@property (readonly,nonatomic)  BOOL               	deleted;
@property (strong,nonatomic)    RenderInfo		* _Nullable	renderInfo;
@property (readonly,nonatomic)  int32_t         	modifyCount;
@property (readonly,nonatomic)	NSArray     	* _Nullable	parentRelations;
@property (readonly,nonatomic)  OsmIdentifier    	extendedIdentifier;
@property (readonly,nonatomic)	OSM_TYPE     		extendedType;

+(OsmIdentifier)extendedIdentifierForType:(OSM_TYPE)type identifier:(OsmIdentifier)identifier;
+(void)decomposeExtendedIdentifier:(OsmIdentifier)extendedIdentifier type:(OSM_TYPE *_Nonnull)pType ident:(OsmIdentifier *_Nonnull)pIdent;

// attributes
@property (readonly,nonatomic)	NSDictionary<NSString *, NSString *>    * _Nullable   tags;
@property (readonly,nonatomic)  NSNumber        * _Nonnull  ident;
@property (readonly,nonatomic)  NSString        * _Nullable user;
@property (readonly,nonatomic)  NSString        * _Nullable timestamp;
@property (readonly,nonatomic)  int32_t     	  			version;
@property (readonly,nonatomic)  OsmIdentifier        		changeset;
@property (readonly,nonatomic)  int32_t              		uid;
@property (readonly,nonatomic)  BOOL                 		visible;

// extra stuff
@property (readonly,nonatomic)  OSMRect						boundingBox;
@property (strong,nonatomic)    NSArray<CALayer<LayerPropertiesProviding> *> * _Nullable 	shapeLayers;
@property (readonly,nonatomic)  ONEWAY               		isOneWay;
@property (assign,nonatomic)    TRISTATE            		isShown;

+(NSDateFormatter * _Nonnull)rfc3339DateFormatter;

-(void)constructTag:(NSString *_Nonnull)tag value:(NSString *_Nonnull)value;
-(void)constructBaseAttributesWithVersion:(int32_t)version changeset:(int64_t)changeset user:(NSString *_Nullable)user uid:(int32_t)uid ident:(int64_t)ident timestamp:(NSString *_Nullable)timestmap;
-(void)constructBaseAttributesFromXmlDict:(NSDictionary *_Nonnull)attributeDict;
-(void)constructAsUserCreated:(NSString *_Nullable)userName;
-(void)setConstructed;
-(void)serverUpdateVersion:(NSInteger)version;
-(void)serverUpdateChangeset:(OsmIdentifier)changeset;
-(void)serverUpdateIdent:(OsmIdentifier)ident;
-(void)serverUpdateInPlace:(OsmBaseObject *_Nonnull)newerVersion;

-(void)incrementModifyCount:(UndoManager *_Nullable)undo;
-(void)resetModifyCount:(UndoManager *_Nullable)undo;
-(void)setTags:(NSDictionary<NSString *, NSString *> *_Nullable)tags undo:(UndoManager *_Nullable)undo;
-(void)setTimestamp:(NSDate *_Nonnull)date undo:(UndoManager *_Nullable)undo;
-(void)setDeleted:(BOOL)deleted undo:(UndoManager *_Nullable)undo;

-(void)addParentRelation:(OsmRelation *_Nonnull)relation undo:(UndoManager *_Nullable)undo;
-(void)removeParentRelation:(OsmRelation *_Nullable)relation undo:(UndoManager *_Nullable)undo;

-(void)clearCachedProperties;

-(OsmNode *_Nullable)isNode;
-(OsmWay *_Nullable)isWay;
-(OsmRelation *_Nullable)isRelation;

-(OSMPoint)selectionPoint;
-(OSMPoint)pointOnObjectForPoint:(OSMPoint)target;
-(CGPathRef _Nonnull)linePathForObjectWithRefPoint:(OSMPoint *_Nullable)refPoint CF_RETURNS_RETAINED;
-(CGPathRef _Nonnull)shapePathForObjectWithRefPoint:(OSMPoint *_Nullable)pRefPoint CF_RETURNS_RETAINED;

-(NSDate *_Nullable)dateForTimestamp;

-(NSSet *_Nonnull)nodeSet;
-(NSArray *_Nullable)extendedKeysForKey:(NSString *_Nullable)key;
-(void)computeBoundingBox;
-(BOOL)overlapsBox:(OSMRect)box;
-(OSMRect)boundingBox;
-(double)distanceToLineSegment:(OSMPoint)point1 point:(OSMPoint)point2;
-(NSString *_Nonnull)givenName;
-(NSString *_Nonnull)friendlyDescription;
-(NSString *_Nonnull)friendlyDescriptionWithDetails;

-(NSString *_Nonnull)geometryName;

-(BOOL)hasInterestingTags;

-(BOOL)isCoastline;

-(BOOL)isModified;

+(NSInteger)nextUnusedIdentifier;
@end
