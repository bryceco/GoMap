//
//  OsmBaseObject.m
//  Go Map!!
//
//  Created by Wolfgang Timme on 1/18/20.
//  Copyright © 2020 Bryce. All rights reserved.
//

#import "OsmBaseObject.h"

#import "DLog.h"

@implementation OsmBaseObject
@synthesize deleted = _deleted;
@synthesize tags = _tags;
@synthesize modifyCount = _modifyCount;
@synthesize ident = _ident;
@synthesize parentRelations = _parentRelations;
@synthesize boundingBox = _boundingBox;

-(NSString *)description
{
    NSMutableString * text = [NSMutableString stringWithFormat:@"id=%@ constructed=%@ deleted=%@ modifyCount=%d",
            _ident,
            _constructed ? @"Yes" : @"No",
            self.deleted ? @"Yes" : @"No",
            _modifyCount];
    [_tags enumerateKeysAndObjectsUsingBlock:^(NSString * key, NSString * value, BOOL *stop) {
        [text appendFormat:@"\n  '%@' = '%@'", key, value];
    }];
    return text;
}



BOOL IsInterestingTag(NSString * key)
{
    if ( [key isEqualToString:@"attribution"] )
        return NO;
    if ( [key isEqualToString:@"created_by"] )
        return NO;
    if ( [key isEqualToString:@"source"] )
        return NO;
    if ( [key isEqualToString:@"odbl"] )
        return NO;
    if ( [key rangeOfString:@"tiger:"].location == 0 )
        return NO;
    return YES;
}

-(BOOL)hasInterestingTags
{
    for ( NSString * key in self.tags ) {
        if ( IsInterestingTag(key) )
            return YES;
    }
    return NO;
}

-(BOOL)isCoastline
{
    NSString * natural = _tags[@"natural"];
    if ( natural ) {
        if ( [natural isEqualToString:@"coastline"] )
            return YES;
        if ( [natural isEqualToString:@"water"] ) {
            if ( !self.isRelation && _parentRelations.count == 0 )
                return NO;    // its a lake or something
            return YES;
        }
    }
    return NO;
}


-(OsmNode *)isNode
{
    return nil;
}
-(OsmWay *)isWay
{
    return nil;
}
-(OsmRelation *)isRelation
{
    return nil;
}
-(OSMRect)boundingBox
{
    if ( _boundingBox.origin.x == 0 && _boundingBox.origin.y == 0 && _boundingBox.size.width == 0 && _boundingBox.size.height == 0 )
        [self computeBoundingBox];
    return _boundingBox;
}
-(void)computeBoundingBox
{
    assert(NO);
    _boundingBox = OSMRectMake(0, 0, 0, 0);
}

-(double)distanceToLineSegment:(OSMPoint)point1 point:(OSMPoint)point2
{
    assert(NO);
    return 1000000.0;
}

-(OSMPoint)selectionPoint
{
    assert(NO);
    return OSMPointMake(0, 0);
}

-(OSMPoint)pointOnObjectForPoint:(OSMPoint)target
{
    assert(NO);
    return OSMPointMake(0, 0);
}


// suitable for drawing outlines for highlighting, but doesn't correctly connect relation members into loops
-(CGPathRef)linePathForObjectWithRefPoint:(OSMPoint *)refPoint CF_RETURNS_RETAINED
{
    NSArray * wayList = self.isWay ? @[ self ] : self.isRelation ? self.isRelation.waysInMultipolygon : nil;
    if ( wayList == nil )
        return nil;

    CGMutablePathRef    path        = CGPathCreateMutable();
    OSMPoint            initial        = { 0, 0 };
    BOOL                haveInitial    = NO;

    for ( OsmWay * way in wayList ) {

        BOOL first = YES;
        for ( OsmNode * node in way.nodes ) {
            OSMPoint pt = MapPointForLatitudeLongitude( node.lat, node.lon );
            if ( isinf(pt.x) )
                break;
            if ( !haveInitial ) {
                initial = pt;
                haveInitial = YES;
            }
            pt.x -= initial.x;
            pt.y -= initial.y;
            pt.x *= PATH_SCALING;
            pt.y *= PATH_SCALING;
            if ( first ) {
                CGPathMoveToPoint(path, NULL, pt.x, pt.y);
                first = NO;
            } else {
                CGPathAddLineToPoint(path, NULL, pt.x, pt.y);
            }
        }
    }

    if ( refPoint && haveInitial ) {
        // place refPoint at upper-left corner of bounding box so it can be the origin for the frame/anchorPoint
        CGRect bbox    = CGPathGetPathBoundingBox( path );
        if ( !isinf(bbox.origin.x) ) {
            CGAffineTransform tran = CGAffineTransformMakeTranslation( -bbox.origin.x, -bbox.origin.y );
            CGPathRef path2 = CGPathCreateCopyByTransformingPath( path, &tran );
            CGPathRelease( path );
            path = (CGMutablePathRef)path2;
            *refPoint = OSMPointMake( initial.x + (double)bbox.origin.x/PATH_SCALING, initial.y + (double)bbox.origin.y/PATH_SCALING );
        } else {
#if DEBUG
            DLog(@"bad path: %@", self);
#endif
        }
    }
    return path;
}


// suitable for drawing polygon areas with holes, etc.
-(CGPathRef)shapePathForObjectWithRefPoint:(OSMPoint *)pRefPoint CF_RETURNS_RETAINED
{
    assert(NO);
    return nil;
}


static NSInteger _nextUnusedIdentifier = 0;

+(NSInteger)nextUnusedIdentifier
{
    if ( _nextUnusedIdentifier == 0 ) {
        _nextUnusedIdentifier = [[NSUserDefaults standardUserDefaults] integerForKey:@"nextUnusedIdentifier"];
    }
    --_nextUnusedIdentifier;
    [[NSUserDefaults standardUserDefaults] setInteger:_nextUnusedIdentifier forKey:@"nextUnusedIdentifier"];
    return _nextUnusedIdentifier;
}


NSDictionary * MergeTags( NSDictionary * ourTags, NSDictionary * otherTags, BOOL allowConflicts )
{
    if ( ourTags.count == 0 )
        return otherTags ? [otherTags copy] : @{};

    __block NSMutableDictionary * merged = [ourTags mutableCopy];
    [otherTags enumerateKeysAndObjectsUsingBlock:^(NSString * otherKey, NSString * otherValue, BOOL * stop) {
        NSString * ourValue = merged[otherKey];
        if ( ![ourValue isEqualToString:otherValue] ) {
            if ( !allowConflicts ) {
                if ( IsInterestingTag(otherKey) ) {
                    *stop = YES;
                    merged = nil;
                }
            } else {
                merged[otherKey] = otherValue;
            }
        }
    }];
    if ( merged == nil )
        return nil;    // conflict
    return [NSDictionary dictionaryWithDictionary:merged];
}

#pragma mark Construction

-(void)constructBaseAttributesWithVersion:(int32_t)version changeset:(int64_t)changeset user:(NSString *)user uid:(int32_t)uid ident:(int64_t)ident timestamp:(NSString *)timestmap
{
    assert( !_constructed );
    _version        = version;
    _changeset        = changeset;
    _user            = user;
    _uid            = uid;
    _visible        = YES;
    _ident            = @(ident);
    _timestamp        = timestmap;
}

-(void)constructBaseAttributesFromXmlDict:(NSDictionary *)attributeDict
{
    int32_t        version        = (int32_t) [[attributeDict objectForKey:@"version"] integerValue];
    int64_t        changeset    = [[attributeDict objectForKey:@"changeset"] longLongValue];
    NSString *    user        = [attributeDict objectForKey:@"user"];
    int32_t        uid            = (int32_t) [[attributeDict objectForKey:@"uid"] integerValue];
    int64_t        ident        = [[attributeDict objectForKey:@"id"] longLongValue];
    NSString *    timestamp    = [attributeDict objectForKey:@"timestamp"];

    [self constructBaseAttributesWithVersion:version changeset:changeset user:user uid:uid ident:ident timestamp:timestamp];
}

-(void)constructTag:(NSString *)tag value:(NSString *)value
{
    // drop deprecated tags
    if ( [tag isEqualToString:@"created_by"] )
        return;

    assert( !_constructed );
    if ( _tags == nil ) {
        _tags = [NSMutableDictionary dictionaryWithObject:value forKey:tag];
    } else {
        [((NSMutableDictionary *)_tags) setValue:value forKey:tag];
    }
}

-(BOOL)constructed
{
    return _constructed;
}
-(void)setConstructed
{
    if ( _user == nil )
        _user = @"";    // some old objects don't have users attached to them
    _constructed = YES;
    _modifyCount = 0;
}

+(NSDateFormatter *)rfc3339DateFormatter
{
    static NSDateFormatter * rfc3339DateFormatter = nil;
    if ( rfc3339DateFormatter == nil ) {
        rfc3339DateFormatter = [[NSDateFormatter alloc] init];
        assert(rfc3339DateFormatter != nil);
        NSLocale * enUSPOSIXLocale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        assert(enUSPOSIXLocale != nil);
        [rfc3339DateFormatter setLocale:enUSPOSIXLocale];
        [rfc3339DateFormatter setDateFormat:@"yyyy'-'MM'-'dd'T'HH':'mm':'ss'Z'"];
        [rfc3339DateFormatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
    }
    return rfc3339DateFormatter;
}
-(NSDate *)dateForTimestamp
{
    NSDate * date = [[OsmBaseObject rfc3339DateFormatter] dateFromString:_timestamp];
    assert(date);
    return date;
}
-(void)setTimestamp:(NSDate *)date undo:(UndoManager *)undo
{
    if ( _constructed ) {
        assert(undo);
        [undo registerUndoWithTarget:self selector:@selector(setTimestamp:undo:) objects:@[[self dateForTimestamp],undo]];
    }
    _timestamp = [[OsmBaseObject rfc3339DateFormatter] stringFromDate:date];
    assert(_timestamp);
}

-(void)clearCachedProperties
{
    _tagInfo                    = nil;
    renderPriorityCached        = 0;
    _isOneWay                    = nil;
    _isShown                    = TRISTATE_UNKNOWN;
    _boundingBox                = OSMRectZero();

    for ( CALayer * layer in _shapeLayers ) {
        [layer removeFromSuperlayer];
    }
    _shapeLayers            = nil;
}

-(BOOL)isModified
{
    return _modifyCount > 0;
}
-(void)incrementModifyCount:(UndoManager *)undo
{
    assert( _modifyCount >= 0 );
    if ( _constructed ) {
        assert(undo);
        // [undo registerUndoWithTarget:self selector:@selector(incrementModifyCount:) objects:@[undo]];
    }
    if ( undo.isUndoing )
        --_modifyCount;
    else
        ++_modifyCount;
    assert( _modifyCount >= 0 );

    // update cached values
    [self clearCachedProperties];
}
-(void)resetModifyCount:(UndoManager *)undo
{
    assert(undo);
    _modifyCount = 0;

    [self clearCachedProperties];
}

-(void)serverUpdateVersion:(NSInteger)version
{
    _version = (int32_t)version;
}
-(void)serverUpdateChangeset:(OsmIdentifier)changeset
{
    _changeset = changeset;
}
-(void)serverUpdateIdent:(OsmIdentifier)ident
{
    assert( _ident.longLongValue < 0 && ident > 0 );
    _ident = @(ident);
}
-(void)serverUpdateInPlace:(OsmBaseObject *)newerVersion
{
    assert( [self.ident isEqualToNumber:newerVersion.ident] );
    assert( self.version < newerVersion.version );
    _tags        = newerVersion.tags;
    _user        = newerVersion.user;
    _timestamp    = newerVersion.timestamp;
    _version    = newerVersion.version;
    _changeset    = newerVersion.changeset;
    _uid        = newerVersion.uid;
    // derived data
    [self clearCachedProperties];
}


-(ONEWAY)isOneWay
{
    if ( _isOneWay == nil )
        _isOneWay = @(self.isWay.computeIsOneWay);
    return (ONEWAY)_isOneWay.intValue;
}

-(BOOL)deleted
{
    return _deleted;
}
-(void)setDeleted:(BOOL)deleted undo:(UndoManager *)undo
{
    if ( _constructed ) {
        assert(undo);
        [self incrementModifyCount:undo];
        [undo registerUndoWithTarget:self selector:@selector(setDeleted:undo:) objects:@[@((BOOL)self.deleted),undo]];
    }
    _deleted = deleted;
}

-(NSDictionary<NSString *, NSString *> *)tags
{
    return _tags;
}
-(void)setTags:(NSDictionary<NSString *, NSString *> *)tags undo:(UndoManager *)undo
{
    if ( _constructed ) {
        assert(undo);
        [self incrementModifyCount:undo];
        [undo registerUndoWithTarget:self selector:@selector(setTags:undo:) objects:@[_tags?:[NSNull null],undo]];
    }
    _tags = tags;
    [self clearCachedProperties];
}

// get all keys that contain another part, like "restriction:conditional"
-(NSArray *)extendedKeysForKey:(NSString *)key
{
    NSArray * keys = nil;
    for ( NSString * tag in _tags ) {
        if ( [tag hasPrefix:key]  &&  [tag characterAtIndex:key.length] == ':' ) {
            if ( keys == nil ) {
                keys = @[ tag ];
            } else {
                keys = [keys arrayByAddingObject:tag];
            }
        }
    }
    return keys;
}

-(NSSet *)nodeSet
{
    assert(NO);
    return nil;
}
-(BOOL)overlapsBox:(OSMRect)box
{
    return OSMRectIntersectsRect( self.boundingBox, box );
}

+(NSDictionary *)featureKeys
{
    static NSDictionary * keyDict = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        keyDict = @{
                        @"building" : @YES,
                        @"landuse" : @YES,
                        @"highway" : @YES,
                        @"railway" : @YES,
                        @"amenity" : @YES,
                        @"shop" : @YES,
                        @"natural" : @YES,
                        @"waterway" : @YES,
                        @"power" : @YES,
                        @"barrier" : @YES,
                        @"leisure" : @YES,
                        @"man_made" : @YES,
                        @"tourism" : @YES,
                        @"boundary" : @YES,
                        @"public_transport" : @YES,
                        @"sport" : @YES,
                        @"emergency" : @YES,
                        @"historic" : @YES,
                        @"route" : @YES,
                        @"aeroway" : @YES,
                        @"place" : @YES,
                        @"craft" : @YES,
                        @"entrance" : @YES,
                        @"playground" : @YES,
                        @"aerialway" : @YES,
                        @"healthcare" : @YES,
                        @"military" : @YES,
                        @"building:part" : @YES,
                        @"training" : @YES,
                        @"traffic_sign" : @YES,
                        @"xmas:feature" : @YES,
                        @"seamark:type" : @YES,
                        @"waterway:sign" : @YES,
                        @"university" : @YES,
                        @"pipeline" : @YES,
                        @"club" : @YES,
                        @"golf" : @YES,
                        @"junction" : @YES,
                        @"office" : @YES,
                        @"piste:type" : @YES,
                        @"harbour" : @YES,
                        };
    });
    return keyDict;
}

-(NSString *)friendlyDescription
{
    NSString * name = [_tags objectForKey:@"name"];
    if ( name.length )
        return name;

    NSString * featureName = [CommonTagList featureNameForObjectDict:self.tags geometry:self.geometryName];
    if ( featureName ) {
        CommonTagFeature * feature = [CommonTagFeature commonTagFeatureWithName:featureName];
        name = feature.friendlyName;
        if ( name.length > 0 )
            return name;
    }

    if ( self.isRelation ) {
        NSString * restriction = self.tags[@"restriction"];
        if ( restriction == nil ) {
            NSArray * a = [self extendedKeysForKey:@"restriction"];
            if ( a.count ) {
                NSString * key = a.lastObject;
                restriction = self.tags[ key ];
            }
        }
        if ( restriction ) {
            if ( [restriction hasPrefix:@"no_left_turn"] )        return @"No Left Turn restriction";
            if ( [restriction hasPrefix:@"no_right_turn"] )        return @"No Right Turn restriction";
            if ( [restriction hasPrefix:@"no_straight_on"] )    return @"No Straight On restriction";
            if ( [restriction hasPrefix:@"only_left_turn"] )    return @"Only Left Turn restriction";
            if ( [restriction hasPrefix:@"only_right_turn"] )    return @"Only Right Turn restriction";
            if ( [restriction hasPrefix:@"only_straight_on"] )    return @"Only Straight On restriction";
            if ( [restriction hasPrefix:@"no_u_turn"] )            return @"No U-Turn restriction";
            return [NSString stringWithFormat:@"Restriction: %@",restriction];
        } else {
            return [NSString stringWithFormat:@"Relation: %@",self.tags[@"type"]];
        }
    }

#if DEBUG
    NSString * indoor = self.tags[ @"indoor" ];
    if ( indoor ) {
        NSString * text = [NSString stringWithFormat:@"Indoor %@",indoor];
        NSString * level = self.tags[ @"level" ];
        if ( level )
            text = [text stringByAppendingFormat:@", level %@",level];
        return text;
    }
#endif

    // if the object has any tags that aren't throw-away tags then use one of them
    NSSet * ignoreTags = [OsmMapData tagsToAutomaticallyStrip];
    
    __block NSString * tagDescription = nil;
    NSDictionary * featureKeys = [OsmBaseObject featureKeys];
    // look for feature key
    [_tags enumerateKeysAndObjectsUsingBlock:^(NSString * key, NSString * value, BOOL * stop) {
        if ( featureKeys[key] ) {
            *stop = YES;
            tagDescription = [NSString stringWithFormat:@"%@ = %@",key,value];
        }
    }];
    if ( tagDescription == nil ) {
        // any non-ignored key
        [_tags enumerateKeysAndObjectsUsingBlock:^(NSString * key, NSString * value, BOOL * stop) {
            if ( ![ignoreTags containsObject:key] ) {
                *stop = YES;
                tagDescription = [NSString stringWithFormat:@"%@ = %@",key,value];
            }
        }];
    }
    if ( tagDescription )
        return tagDescription;

    if ( self.isNode && self.isNode.wayCount > 0 )
        return NSLocalizedString(@"(node in way)",nil);

    if ( self.isNode )
        return NSLocalizedString(@"(node)",nil);

    if ( self.isWay )
        return NSLocalizedString(@"(way)",nil);

    if ( self.isRelation ) {
        OsmRelation * relation = self.isRelation;
        NSString * type = relation.tags[@"type"];
        if ( type.length ) {
            name = relation.tags[type];
            if ( name.length ) {
                return [NSString stringWithFormat:@"%@ (%@)", type, name];
            } else {
                return [NSString stringWithFormat:NSLocalizedString(@"%@ (relation)",nil),type];
            }
        }
        return [NSString stringWithFormat:NSLocalizedString(@"(relation %@)",nil), self.ident];
    }

    return NSLocalizedString(@"other object",nil);
}


- (id)copyWithZone:(NSZone *)zone
{
    return self;
}

-(void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:_ident                    forKey:@"ident"];
    [coder encodeObject:_user                    forKey:@"user"];
    [coder encodeObject:_timestamp                forKey:@"timestamp"];
    [coder encodeInteger:_version                forKey:@"version"];
    [coder encodeInteger:(NSInteger)_changeset    forKey:@"changeset"];
    [coder encodeInteger:_uid                    forKey:@"uid"];
    [coder encodeBool:_visible                    forKey:@"visible"];
    [coder encodeObject:_tags                    forKey:@"tags"];
    [coder encodeBool:_deleted                    forKey:@"deleted"];
    [coder encodeInt32:_modifyCount                forKey:@"modified"];
}
-(id)initWithCoder:(NSCoder *)coder
{
    self = [super init];
    if ( self ) {
        _ident            = [coder decodeObjectForKey:@"ident"];
        _user            = [coder decodeObjectForKey:@"user"];
        _timestamp        = [coder decodeObjectForKey:@"timestamp"];
        _version        = [coder decodeInt32ForKey:@"version"];
        _changeset        = [coder decodeIntegerForKey:@"changeset"];
        _uid            = [coder decodeInt32ForKey:@"uid"];
        _visible        = [coder decodeBoolForKey:@"visible"];
        _tags            = [coder decodeObjectForKey:@"tags"];
        _deleted        = [coder decodeBoolForKey:@"deleted"];
        _modifyCount    = [coder decodeInt32ForKey:@"modified"];
    }
    return self;
}

-(id)init
{
    self = [super init];
    if ( self ) {
    }
    return self;
}

-(void)constructAsUserCreated:(NSString *)userName
{
    // newly created by user
    assert( !_constructed );
    _ident = @( [OsmBaseObject nextUnusedIdentifier] );
    _visible = YES;
    _user = userName ?: @"";
    _version = 1;
    _changeset = 0;
    _uid = 0;
    _deleted = YES;
    [self setTimestamp:[NSDate date] undo:nil];
}


-(void)addRelation:(OsmRelation *)relation undo:(UndoManager *)undo
{
    if ( _constructed && undo ) {
        [undo registerUndoWithTarget:self selector:@selector(removeRelation:undo:) objects:@[relation,undo]];
    }

    if ( _parentRelations ) {
        if ( ![_parentRelations containsObject:relation] )
            _parentRelations = [_parentRelations arrayByAddingObject:relation];
    } else {
        _parentRelations = @[ relation ];
    }
}
-(void)removeRelation:(OsmRelation *)relation undo:(UndoManager *)undo
{
    if ( _constructed && undo ) {
        [undo registerUndoWithTarget:self selector:@selector(addRelation:undo:) objects:@[relation,undo]];
    }
    NSInteger index = [_parentRelations indexOfObject:relation];
    if ( index == NSNotFound ) {
        DLog(@"missing relation");
        return;
    }
    if ( _parentRelations.count == 1 ) {
        _parentRelations = nil;
    } else {
        NSMutableArray * a = [_parentRelations mutableCopy];
        [a removeObjectAtIndex:index];
        _parentRelations = [NSArray arrayWithArray:a];
    }
}



-(NSString *)geometryName
{
    if ( self.isWay ) {
        if ( self.isWay.isArea )
            return GEOMETRY_AREA;
        else
            return GEOMETRY_WAY;
    } else if ( self.isNode ) {
        if ( self.isNode.wayCount > 0 )
            return GEOMETRY_VERTEX;
        else
            return GEOMETRY_NODE;
    } else if ( self.isRelation ) {
        if ( self.isRelation.isMultipolygon )
            return GEOMETRY_AREA;
        else
            return GEOMETRY_WAY;
    }
    return @"unknown";
}

-(OSM_TYPE)extendedType
{
    return self.isNode ? OSM_TYPE_NODE : self.isWay ? OSM_TYPE_WAY : OSM_TYPE_RELATION;
}

+(OsmIdentifier)extendedIdentifierForType:(OSM_TYPE)type identifier:(OsmIdentifier)identifier
{
    return (identifier & (((uint64_t)1 << 62)-1)) | ((uint64_t)type << 62);
}

-(OsmIdentifier)extendedIdentifier
{
    OSM_TYPE type = self.extendedType;
    return _ident.longLongValue | ((uint64_t)type << 62);
}

+(void)decomposeExtendedIdentifier:(OsmIdentifier)extendedIdentifier type:(OSM_TYPE *)pType ident:(OsmIdentifier *)pIdent
{
    *pType  = extendedIdentifier >> 62 & 3;
    int64_t ident = extendedIdentifier & (((uint64_t)1 << 62)-1);
    ident = (ident << 2) >> 2;    // sign extend
    *pIdent = ident;
}

@end
