//
//  OsmRelation.m
//  Go Map!!
//
//  Created by Wolfgang Timme on 1/18/20.
//  Copyright © 2020 Bryce. All rights reserved.
//

#import "OsmRelation.h"

#import "OsmMember.h"

@implementation OsmRelation

-(NSString *)description
{
    return [NSString stringWithFormat:@"OsmRelation %@", [super description]];
}

-(void)constructMember:(OsmMember *)member
{
    assert( !_constructed );
    if ( _members == nil ) {
        _members = [NSMutableArray arrayWithObject:member];
    } else {
        [_members addObject:member];
    }
}

-(OsmRelation *)isRelation
{
    return self;
}

-(void)forAllMemberObjectsRecurse:(void(^)(OsmBaseObject *))callback relations:(NSMutableSet *)relations
{
    for ( OsmMember * member in _members ) {
        OsmBaseObject * obj = member.ref;
        if ( [obj isKindOfClass:[OsmBaseObject class]] ) {
            if ( obj.isRelation ) {
                if ( [relations containsObject:obj] ) {
                    // skip
                } else {
                    callback(obj);
                    [relations addObject:obj];
                    [obj.isRelation forAllMemberObjectsRecurse:callback relations:relations];
                }
            } else {
                callback(obj);
            }
        }
    }
}
-(void)forAllMemberObjects:(void(^)(OsmBaseObject *))callback
{
    NSMutableSet * relations = [NSMutableSet setWithObject:self];
    [self forAllMemberObjectsRecurse:callback relations:relations];
}
-(NSSet *)allMemberObjects
{
    __block NSMutableSet * objects = [NSMutableSet new];
    [self forAllMemberObjects:^(OsmBaseObject * obj) {
        [objects addObject:obj];
    }];
    return objects;
}




-(void)resolveToMapData:(OsmMapData *)mapData
{
    BOOL needsRedraw = NO;
    for ( OsmMember * member in _members ) {
        id ref = member.ref;
        if ( ![ref isKindOfClass:[NSNumber class]] )
            // already resolved
            continue;

        if ( member.isWay ) {
            OsmWay * way = [mapData wayForRef:ref];
            if ( way ) {
                [member resolveRefToObject:way];
                [way addRelation:self undo:nil];
                needsRedraw = YES;
            } else {
                // way is not in current view
            }
        } else if ( member.isNode ) {
            OsmNode * node = [mapData nodeForRef:ref];
            if ( node ) {
                [member resolveRefToObject:node];
                [node addRelation:self undo:nil];
                needsRedraw = YES;
            } else {
                // node is not in current view
            }
        } else if ( member.isRelation ) {
            OsmRelation * rel = [mapData relationForRef:ref];
            if ( rel ) {
                [member resolveRefToObject:rel];
                [rel addRelation:self undo:nil];
                needsRedraw = YES;
            } else {
                // relation is not in current view
            }
        } else {
            assert(NO);
        }
    }
    if ( needsRedraw ) {
        [self clearCachedProperties];
    }
}

// convert references to objects back to NSNumber
-(void)deresolveRefs
{
    for ( OsmMember * member in _members ) {
        OsmBaseObject * ref = member.ref;
        if ( [ref isKindOfClass:[OsmBaseObject class]] ) {
            [ref removeRelation:self undo:nil];
            [member resolveRefToObject:(OsmBaseObject *)ref.ident];
        }
    }
}



-(void)assignMembers:(NSArray *)members undo:(UndoManager *)undo
{
    if ( _constructed ) {
        assert(undo);
        [self incrementModifyCount:undo];
        [undo registerUndoWithTarget:self selector:@selector(assignMembers:undo:) objects:@[_members,undo]];
    }

    // figure out which members changed and update their relation parents
#if 1
    NSMutableSet * old = [NSMutableSet new];
    NSMutableSet * new = [NSMutableSet new];
    for ( OsmMember * m in _members ) {
        if ( [m.ref isKindOfClass:[OsmBaseObject class]] ) {
            [old addObject:m.ref];
        }
    }
    for ( OsmMember * m in members ) {
        if ( [m.ref isKindOfClass:[OsmBaseObject class]] ) {
            [new addObject:m.ref];
        }
    }
    NSMutableSet * common = [new mutableCopy];
    [common intersectSet:old];
    [new minusSet:common];    // added items
    [old minusSet:common];    // removed items
    for ( OsmBaseObject * obj in old ) {
        [obj removeRelation:self undo:nil];
    }
    for ( OsmBaseObject * obj in new ) {
        [obj addRelation:self undo:nil];
    }
#else
    NSArray * old = [_members sortedArrayUsingComparator:^NSComparisonResult(OsmMember * obj1, OsmMember * obj2) {
        NSNumber * r1 = [obj1.ref isKindOfClass:[OsmBaseObject class]] ? ((OsmBaseObject *)obj1.ref).ident : obj1.ref;
        NSNumber * r2 = [obj2.ref isKindOfClass:[OsmBaseObject class]] ? ((OsmBaseObject *)obj2.ref).ident : obj2.ref;
        return [r1 compare:r2];
    }];
    NSArray * new = [members sortedArrayUsingComparator:^NSComparisonResult(OsmMember * obj1, OsmMember * obj2) {
        NSNumber * r1 = [obj1.ref isKindOfClass:[OsmBaseObject class]] ? ((OsmBaseObject *)obj1.ref).ident : obj1.ref;
        NSNumber * r2 = [obj2.ref isKindOfClass:[OsmBaseObject class]] ? ((OsmBaseObject *)obj2.ref).ident : obj2.ref;
        return [r1 compare:r2];
    }];
#endif

    _members = [members mutableCopy];
}

-(void)removeMemberAtIndex:(NSInteger)index undo:(UndoManager *)undo
{
    assert(undo);
    OsmMember * member = _members[index];
    [self incrementModifyCount:undo];
    [undo registerUndoWithTarget:self selector:@selector(addMember:atIndex:undo:) objects:@[member,@(index),undo]];
    [_members removeObjectAtIndex:index];
    OsmBaseObject * obj = member.ref;
    if ( [obj isKindOfClass:[OsmBaseObject class]] ) {
        [obj removeRelation:self undo:nil];
    }
}
-(void)addMember:(OsmMember *)member atIndex:(NSInteger)index undo:(UndoManager *)undo
{
    if ( _constructed ) {
        assert(undo);
        [self incrementModifyCount:undo];
        [undo registerUndoWithTarget:self selector:@selector(removeMemberAtIndex:undo:) objects:@[@(index),undo]];
    }
    if ( _members == nil ) {
        _members = [NSMutableArray new];
    }
    [_members insertObject:member atIndex:index];
    OsmBaseObject * obj = member.ref;
    if ( [obj isKindOfClass:[OsmBaseObject class]] ) {
        [obj addRelation:self undo:nil];
    }
}


-(void)serverUpdateInPlace:(OsmRelation *)newerVersion
{
    [super serverUpdateInPlace:newerVersion];
    _members = [newerVersion.members mutableCopy];
}


-(void)computeBoundingBox
{
    BOOL first = YES;
    OSMRect box = { 0, 0, 0, 0 };
    NSSet * objects = [self allMemberObjects];
    for ( OsmBaseObject * obj in objects ) {
        OSMRect rc = obj.boundingBox;
        if ( rc.origin.x == 0 && rc.origin.y == 0 && rc.size.height == 0 && rc.size.width == 0 ) {
            // skip
        } else if ( first ) {
            box = rc;
            first = NO;
        } else {
            box = OSMRectUnion(box,rc);
        }
    }
    _boundingBox = box;
}

-(NSSet *)nodeSet
{
    NSMutableSet * set = [NSMutableSet set];
    for ( OsmMember * member in _members ) {
        if ( [member.ref isKindOfClass:[NSNumber class]] )
            continue;    // unresolved reference

        if ( member.isNode ) {
            OsmNode * node = member.ref;
            [set addObject:node];
        } else if ( member.isWay ) {
            OsmWay * way = member.ref;
            [set addObjectsFromArray:way.nodes];
        } else if ( member.isRelation ) {
            OsmRelation * relation = member.ref;
            for ( OsmNode * node in [relation nodeSet] ) {
                [set addObject:node];
            }
        } else {
            assert(NO);
        }
    }
    return set;
}

-(OsmMember *)memberByRole:(NSString *)role
{
    for ( OsmMember * member in _members ) {
        if ( [member.role isEqualToString:role] ) {
            return member;
        }
    }
    return nil;
}
-(NSArray *)membersByRole:(NSString *)role
{
    NSMutableArray * a = [NSMutableArray new];
    for ( OsmMember * member in _members ) {
        if ( [member.role isEqualToString:role] ) {
            [a addObject:member];
        }
    }
    return a;
}
-(OsmMember *)memberByRef:(OsmBaseObject *)ref
{
    for ( OsmMember * member in _members ) {
        if ( member.ref == ref )
            return member;
    }
    return nil;
}

-(BOOL)isMultipolygon
{
    return [_tags[@"type"] isEqualToString:@"multipolygon"];
}

-(BOOL)isRoute
{
    return [_tags[@"type"] isEqualToString:@"route"];
}

-(BOOL)isRestriction
{
    NSString * type = self.tags[ @"type" ];
    if ( type ) {
        if ( [type isEqualToString:@"restriction"] )
            return YES;
        if ( [type hasPrefix:@"restriction:"] )
            return YES;
    }
    return NO;
}


-(NSMutableArray *)waysInMultipolygon
{
    if ( !self.isMultipolygon )
        return nil;
    NSMutableArray * a = [NSMutableArray arrayWithCapacity:_members.count];
    for ( OsmMember * mem in _members ) {
        NSString * role = mem.role;
        if ( [role isEqualToString:@"outer"] || [role isEqualToString:@"inner"] ) {
            if ( [mem.ref isKindOfClass:[OsmWay class]] ) {
                [a addObject:mem.ref];
            }
        }
    }
    return a;
}


+(NSArray *)buildMultipolygonFromMembers:(NSArray *)memberList repairing:(BOOL)repairing isComplete:(BOOL *)isComplete
{
    NSMutableArray    *    loopList = [NSMutableArray new];
    NSMutableArray    *    loop = nil;
    NSMutableArray    *    members = [memberList mutableCopy];
    [members filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(OsmMember * member, NSDictionary<NSString *,id> * bindings) {
        return [member.ref isKindOfClass:[OsmWay class]] && ([member.role isEqualToString:@"outer"] || [member.role isEqualToString:@"inner"]);
    }]];
    BOOL isInner = NO;
    BOOL foundAdjacent = NO;

    *isComplete = members.count == memberList.count;

    while ( members.count ) {
        if ( loop == nil ) {
            // add a member to loop
            OsmMember * member = members.lastObject;
            [members removeObjectAtIndex:members.count-1];
            isInner = [member.role isEqualToString:@"inner"];
            OsmWay * way = member.ref;
            loop = [way.nodes mutableCopy];
            foundAdjacent = YES;
        } else {
            // find adjacent way
            foundAdjacent = NO;
            for ( NSInteger i = 0; i < members.count; ++i ) {
                OsmMember * member = members[i];
                if ( [member.role isEqualToString:@"inner"] != isInner )
                    continue;
                OsmWay * way = member.ref;
                NSEnumerator * enumerator = way.nodes[0] == loop.lastObject ? way.nodes.objectEnumerator
                                              : way.nodes.lastObject == loop.lastObject ? way.nodes.reverseObjectEnumerator
                                            : nil;
                if ( enumerator ) {
                    foundAdjacent = YES;
                    BOOL first = YES;
                    for ( OsmNode * n in enumerator ) {
                        if ( first ) {
                            first = NO;
                        } else {
                            [loop addObject:n];
                        }
                    }
                    [members removeObjectAtIndex:i];
                    break;
                }
            }
            if ( !foundAdjacent && repairing ) {
                // invalid, but we'll try to continue
                *isComplete = NO;
                [loop addObject:loop[0]];    // force-close the loop
            }
        }

        if ( loop.count && (loop.lastObject == loop[0] || !foundAdjacent) ) {
            // finished a loop. Outer goes clockwise, inner goes counterclockwise
            NSArray * lp = [OsmWay isClockwiseArrayOfNodes:loop] == isInner ? [[loop reverseObjectEnumerator] allObjects] : loop;
            [loopList addObject:lp];
            loop = nil;
        }
    }
    return loopList;
}


-(NSArray *)buildMultipolygonRepairing:(BOOL)repairing
{
    if ( !self.isMultipolygon )
        return nil;
    BOOL isComplete = YES;
    NSArray * a = [OsmRelation buildMultipolygonFromMembers:self.members repairing:repairing isComplete:&isComplete];
    return a;
}


-(CGPathRef)shapePathForObjectWithRefPoint:(OSMPoint *)pRefPoint CF_RETURNS_RETAINED
{
    NSArray * loopList = [self buildMultipolygonRepairing:YES];
    if ( loopList.count == 0 )
        return NULL;

    CGMutablePathRef     path = CGPathCreateMutable();
    BOOL                hasRefPoint = NO;
    OSMPoint            refPoint;

    for ( NSArray * loop in loopList ) {
        BOOL first = YES;
        for ( OsmNode * n in loop ) {
            OSMPoint pt = MapPointForLatitudeLongitude( n.lat, n.lon );
            if ( first ) {
                first = NO;
                if ( !hasRefPoint ) {
                    hasRefPoint = YES;
                    refPoint = pt;
                }
                CGPathMoveToPoint(path, NULL, (pt.x-refPoint.x)*PATH_SCALING, (pt.y-refPoint.y)*PATH_SCALING);
            } else {
                CGPathAddLineToPoint(path, NULL, (pt.x-refPoint.x)*PATH_SCALING, (pt.y-refPoint.y)*PATH_SCALING);
            }
        }
    }
    *pRefPoint = refPoint;
    return path;
}

-(OSMPoint)centerPoint
{
    NSMutableArray * outerSet = [NSMutableArray new];
    for ( OsmMember * member in _members ) {
        if ( [member.role isEqualToString:@"outer"] ) {
            OsmWay * way = member.ref;
            if ( [way isKindOfClass:[OsmWay class]] ) {
                [outerSet addObject:way];
            }
        }
    }
    if ( outerSet.count == 1 ) {
        return [outerSet[0] centerPoint];
    } else {
        OSMRect rc = self.boundingBox;
        return OSMPointMake( rc.origin.x + rc.size.width/2, rc.origin.y+rc.size.height/2);
    }
}
-(OSMPoint)selectionPoint
{
    OSMRect bbox = self.boundingBox;
    OSMPoint center = { bbox.origin.x + bbox.size.width/2, bbox.origin.y + bbox.size.height/2 };
    if ( [self isMultipolygon] ) {
        // pick a point on an outer polygon that is close to the center of the bbox
        for ( OsmMember * member in _members ) {
            if ( [member.role isEqualToString:@"outer"] ) {
                OsmWay * way = member.ref;
                if ( [way isKindOfClass:[OsmWay class]] && way.nodes.count > 0 ) {
                    return [way pointOnObjectForPoint:center];
                }
            }
        }
    }
    if ( [self isRestriction] ) {
        // pick via node or way
        for ( OsmMember * member in _members ) {
            if ( [member.role isEqualToString:@"via"] ) {
                OsmBaseObject * object = member.ref;
                if ( [object isKindOfClass:[OsmBaseObject class]] ) {
                    if ( object.isNode || object.isWay ) {
                        return [object selectionPoint];
                    }
                }
            }
        }
    }
    // choose any node/way member
    NSSet * all = [self allMemberObjects];    // might be a super relation, so need to recurse down
    OsmBaseObject * object = [all anyObject];
    return [object selectionPoint];
}

-(double)distanceToLineSegment:(OSMPoint)point1 point:(OSMPoint)point2
{
    double dist = 1000000.0;
    for ( OsmMember * member in _members ) {
        OsmBaseObject * object = member.ref;
        if ( [object isKindOfClass:[OsmBaseObject class]] ) {
            if ( !object.isRelation ) {
                double d = [object distanceToLineSegment:point1 point:point2];
                if ( d < dist ) {
                    dist = d;
                }
            }
        }
    }
    return dist;
}

-(OSMPoint)pointOnObjectForPoint:(OSMPoint)target
{
    OSMPoint bestPoint = target;
    double bestDistance = 10000000.0;
    for ( OsmBaseObject * object in self.allMemberObjects ) {
        OSMPoint pt = [object pointOnObjectForPoint:target];
        double dist = DistanceFromPointToPoint(target, pt);
        if ( dist < bestDistance ) {
            bestDistance = dist;
            bestPoint = pt;
        }
    }
    return bestPoint;
}

-(BOOL)containsObject:(OsmBaseObject *)object
{
    OsmNode * node = object.isNode;
    NSSet * set = [self allMemberObjects];
    for ( OsmBaseObject * obj in set ) {
        if ( obj == object ) {
            return YES;
        }
        if ( node && obj.isWay && [obj.isWay.nodes containsObject:object] ) {
            return YES;
        }
    }
    return NO;
}


-(void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder:coder];
    [coder encodeObject:_members forKey:@"members"];
}
-(id)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if ( self ) {
        _members    = [coder decodeObjectForKey:@"members"];
        _constructed = YES;
    }
    return self;
}

@end
