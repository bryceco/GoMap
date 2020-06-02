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

NSDictionary * MergeTags(NSDictionary * myself, NSDictionary * tags, BOOL failOnConflict);

@interface OsmBaseObject : NSObject <NSCoding,NSCopying>
{
@protected
    int32_t                _modifyCount;
    BOOL                _constructed;
    NSDictionary<NSString *, NSString *>    *    _tags;
    NSNumber        *    _ident;
    NSArray            *    _parentRelations;

    NSNumber        *    _isOneWay;
@public
    OSMRect                _boundingBox;
    NSInteger            renderPriorityCached;
}
@property (readonly,nonatomic)    BOOL                    deleted;
@property (strong,nonatomic)    RenderInfo                *    tagInfo;
@property (readonly,nonatomic)    int32_t                    modifyCount;
@property (readonly,nonatomic)    NSArray                *    parentRelations;
@property (readonly,nonatomic)    OsmIdentifier            extendedIdentifier;
@property (readonly,nonatomic)    OSM_TYPE                extendedType;

+(OsmIdentifier)extendedIdentifierForType:(OSM_TYPE)type identifier:(OsmIdentifier)identifier;
+(void)decomposeExtendedIdentifier:(OsmIdentifier)extendedIdentifier type:(OSM_TYPE *)pType ident:(OsmIdentifier *)pIdent;


// attributes
@property (readonly,nonatomic)    NSDictionary<NSString *, NSString *>    *    tags;
@property (readonly,nonatomic)    NSNumber        *    ident;
@property (readonly,nonatomic)    NSString        *    user;
@property (readonly,nonatomic)    NSString        *    timestamp;
@property (readonly,nonatomic)    int32_t                version;
@property (readonly,nonatomic)    OsmIdentifier        changeset;
@property (readonly,nonatomic)    int32_t                uid;
@property (readonly,nonatomic)    BOOL                visible;

// extra stuff
@property (readonly,nonatomic)    OSMRect                boundingBox;
@property (strong,nonatomic)    NSArray            *    shapeLayers;
@property (readonly,nonatomic)    ONEWAY                isOneWay;
@property (assign,nonatomic)    TRISTATE            isShown;

+(NSDictionary *)featureKeys;
+(NSDateFormatter *)rfc3339DateFormatter;

-(void)constructTag:(NSString *)tag value:(NSString *)value;
-(void)constructBaseAttributesWithVersion:(int32_t)version changeset:(int64_t)changeset user:(NSString *)user uid:(int32_t)uid ident:(int64_t)ident timestamp:(NSString *)timestmap;
-(void)constructBaseAttributesFromXmlDict:(NSDictionary *)attributeDict;
-(void)constructAsUserCreated:(NSString *)userName;
-(void)setConstructed;
-(void)serverUpdateVersion:(NSInteger)version;
-(void)serverUpdateChangeset:(OsmIdentifier)changeset;
-(void)serverUpdateIdent:(OsmIdentifier)ident;
-(void)serverUpdateInPlace:(OsmBaseObject *)newerVersion;

-(void)incrementModifyCount:(UndoManager *)undo;
-(void)resetModifyCount:(UndoManager *)undo;
-(void)setTags:(NSDictionary<NSString *, NSString *> *)tags undo:(UndoManager *)undo;
-(void)setTimestamp:(NSDate *)date undo:(UndoManager *)undo;
-(void)setDeleted:(BOOL)deleted undo:(UndoManager *)undo;

-(void)addRelation:(OsmRelation *)relation undo:(UndoManager *)undo;
-(void)removeRelation:(OsmRelation *)relation undo:(UndoManager *)undo;

-(void)clearCachedProperties;

-(OsmNode *)isNode;
-(OsmWay *)isWay;
-(OsmRelation *)isRelation;

-(OSMPoint)selectionPoint;
-(OSMPoint)pointOnObjectForPoint:(OSMPoint)target;
-(CGPathRef)linePathForObjectWithRefPoint:(OSMPoint *)refPoint CF_RETURNS_RETAINED;
-(CGPathRef)shapePathForObjectWithRefPoint:(OSMPoint *)pRefPoint CF_RETURNS_RETAINED;

-(NSDate *)dateForTimestamp;

-(NSSet *)nodeSet;
-(NSArray *)extendedKeysForKey:(NSString *)key;
-(void)computeBoundingBox;
-(BOOL)overlapsBox:(OSMRect)box;
-(OSMRect)boundingBox;
-(double)distanceToLineSegment:(OSMPoint)point1 point:(OSMPoint)point2;
-(NSString *)friendlyDescription;
-(NSString *)friendlyDescriptionWithDetails;

-(NSString *)geometryName;

-(BOOL)hasInterestingTags;

-(BOOL)isCoastline;

-(BOOL)isModified;

+(NSInteger)nextUnusedIdentifier;
@end
