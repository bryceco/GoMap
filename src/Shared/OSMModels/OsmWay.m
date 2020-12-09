//
//  OsmWay.m
//  Go Map!!
//
//  Created by Wolfgang Timme on 1/18/20.
//  Copyright © 2020 Bryce. All rights reserved.
//

#import "OsmWay.h"

#import "OsmMember.h"
#import "PresetsDatabase.h"

@implementation OsmWay

-(NSString *)description
{
    return [NSString stringWithFormat:@"OsmWay %@", [super description]];
}


-(void)constructNode:(NSNumber *)node
{
    assert( !_constructed );
    if ( _nodes == nil ) {
        _nodes = [NSMutableArray arrayWithObject:node];
    } else {
        [_nodes addObject:node];
    }
}
-(void)constructNodeList:(NSMutableArray *)nodes
{
    assert( !_constructed );
    _nodes = nodes;
}


-(OsmWay *)isWay
{
    return self;
}

-(void)resolveToMapData:(OsmMapData *)mapData
{
    for ( NSInteger i = 0, e = _nodes.count; i < e; ++i ) {
        NSNumber * ref = _nodes[i];
        if ( ![ref isKindOfClass:[NSNumber class]] )
            continue;
        OsmNode * node = [mapData nodeForRef:ref];
        NSAssert(node,nil);
        _nodes[i] = node;
        [node setWayCount:node.wayCount+1 undo:nil];
    }
}

-(void)removeNodeAtIndex:(NSInteger)index undo:(UndoManager *)undo
{
    assert(undo);
    OsmNode * node = _nodes[index];
    [self incrementModifyCount:undo];
    [undo registerUndoWithTarget:self selector:@selector(addNode:atIndex:undo:) objects:@[node,@(index),undo]];
    [_nodes removeObjectAtIndex:index];
    [node setWayCount:node.wayCount-1 undo:nil];
    [self computeBoundingBox];
}
-(void)addNode:(OsmNode *)node atIndex:(NSInteger)index undo:(UndoManager *)undo
{
    if ( _constructed ) {
        assert(undo);
        [self incrementModifyCount:undo];
        [undo registerUndoWithTarget:self selector:@selector(removeNodeAtIndex:undo:) objects:@[@(index),undo]];
    }
    if ( _nodes == nil ) {
        _nodes = [NSMutableArray new];
    }
    [_nodes insertObject:node atIndex:index];
    [node setWayCount:node.wayCount+1 undo:nil];
    [self computeBoundingBox];
}

-(void)serverUpdateInPlace:(OsmWay *)newerVersion
{
    [super serverUpdateInPlace:newerVersion];
    _nodes = [newerVersion.nodes mutableCopy];
}


-(BOOL)isArea
{
    return [PresetsDatabase isArea:self];
}

-(BOOL)isClosed
{
    return _nodes.count > 2 && _nodes[0] == _nodes.lastObject;
}

-(ONEWAY)computeIsOneWay
{
    static NSDictionary * oneWayTags = nil;
    if ( oneWayTags == nil ) {
        oneWayTags = @{
                       @"aerialway" : @{
                               @"chair_lift" : @YES,
                               @"mixed_lift" : @YES,
                               @"t-bar" : @YES,
                               @"j-bar" : @YES,
                               @"platter" : @YES,
                               @"rope_tow" : @YES,
                               @"magic_carpet" : @YES,
                               @"yes" : @YES
                               },
                       @"highway" : @{
                               @"motorway" : @YES,
                               @"motorway_link" : @YES,
                               @"steps" : @YES
                               },
                       @"junction": @{
                               @"roundabout" : @YES
                               },
                       @"man_made": @{
                               @"piste:halfpipe" : @YES,
                               @"embankment" : @YES
                               },
                       @"natural" : @{
                               @"cliff" : @YES,
                               @"coastline" : @YES
                               },
                       @"piste:type": @{
                               @"downhill" : @YES,
                               @"sled" : @YES,
                               @"yes" : @YES
                               },
                       @"waterway": @{
                               @"brook" : @YES,
                               @"canal" : @YES,
                               @"ditch" : @YES,
                               @"drain" : @YES,
                               @"fairway" : @YES,
                               @"river" : @YES,
                               @"stream" : @YES,
                               @"weir" : @YES
                               }
                       };
    }

    NSString * oneWayVal = [_tags objectForKey:@"oneway"];
    if ( oneWayVal ) {
        if ( [oneWayVal isEqualToString:@"yes"] || [oneWayVal isEqualToString:@"1"] )
            return ONEWAY_FORWARD;
        if ( [oneWayVal isEqualToString:@"no"] || [oneWayVal isEqualToString:@"0"] )
            return ONEWAY_NONE;
        if ( [oneWayVal isEqualToString:@"-1"] )
            return ONEWAY_BACKWARD;
    }

    __block ONEWAY oneWay = ONEWAY_NONE;
    [_tags enumerateKeysAndObjectsUsingBlock:^(NSString * tag, NSString * value, BOOL *stop) {
        NSDictionary * valueDict = [oneWayTags objectForKey:tag];
        if ( valueDict ) {
            if ( valueDict[ value ] ) {
                oneWay = ONEWAY_FORWARD;
                *stop = YES;
            }
        }
    }];
    return oneWay;
}

-(BOOL)sharesNodesWithWay:(OsmWay *)way
{
    if ( _nodes.count * way.nodes.count < 100 ) {
        for ( OsmNode * n in way.nodes ) {
            if ( [_nodes containsObject:n] )
                return YES;
        }
        return NO;
    } else {
        NSSet * set1 = [NSSet setWithArray:way.nodes];
        NSSet * set2 = [NSSet setWithArray:_nodes];
        return [set1 intersectsSet:set2];
    }
}


-(BOOL)isMultipolygonMember
{
    for ( OsmRelation * parent in self.parentRelations ) {
        if ( parent.isMultipolygon && parent.tags.count > 0 )
            return YES;
    }
    return NO;
}

-(BOOL)isSimpleMultipolygonOuterMember
{
    NSArray * parents = self.parentRelations;
    if (parents.count != 1)
        return NO;

    OsmRelation * parent = parents[0];
    if (!parent.isMultipolygon || parent.tags.count > 1)
        return NO;

    for ( OsmMember * member in parent.members ) {
        if (member.ref == self ) {
            if ( ![member.role isEqualToString:@"outer"] )
                return NO; // Not outer member
        } else {
            if ( (member.role == nil || [member.role isEqualToString:@"outer"]))
                return NO; // Not a simple multipolygon
        }
    }
    return YES;
}

-(double)wayArea
{
    assert(NO);
    return 0;
}

// return the point on the way closest to the supplied point
-(OSMPoint)pointOnObjectForPoint:(OSMPoint)target
{
    switch ( _nodes.count ) {
        case 0:
            return target;
        case 1:
            return ((OsmNode *)_nodes.lastObject).location;
    }
    OSMPoint    bestPoint = { 0, 0 };
    double        bestDist = 360 * 360;
    for ( NSInteger i = 1; i < _nodes.count; ++i ) {
        OSMPoint p1 = [((OsmNode *)_nodes[i-1]) location];
        OSMPoint p2 = [((OsmNode *)_nodes[ i ]) location];
        OSMPoint linePoint = ClosestPointOnLineToPoint( p1, p2, target );
        double dist = MagSquared( Sub( linePoint, target ) );
        if ( dist < bestDist ) {
            bestDist = dist;
            bestPoint = linePoint;
        }
    }
    return bestPoint;
}

-(double)distanceToLineSegment:(OSMPoint)point1 point:(OSMPoint)point2
{
    if ( _nodes.count == 1 ) {
        return [_nodes.lastObject distanceToLineSegment:point1 point:point2];
    }
    double dist = 1000000.0;
    OsmNode * prevNode = nil;
    for ( OsmNode * node in _nodes ) {
        if ( prevNode && LineSegmentsIntersect( prevNode.location, node.location, point1, point2 )) {
            return 0.0;
        }
        double d = [node distanceToLineSegment:point1 point:point2];
        if ( d < dist ) {
            dist = d;
        }
        prevNode = node;
    }
    return dist;
}


-(NSSet *)nodeSet
{
    return [NSSet setWithArray:_nodes];
}

-(void)computeBoundingBox
{
    double minX, maxX, minY, maxY;
    BOOL first = YES;
    for ( OsmNode * node in _nodes ) {
        OSMPoint loc = node.location;
        if ( first ) {
            first = NO;
            minX = maxX = loc.x;
            minY = maxY = loc.y;
        } else {
            if ( loc.y < minY )        minY = loc.y;
            if ( loc.x < minX )        minX = loc.x;
            if ( loc.y > maxY )        maxY = loc.y;
            if ( loc.x > maxX )        maxX = loc.x;
        }
    }
    if ( first ) {
        _boundingBox = OSMRectMake(0, 0, 0, 0);
    } else {
        _boundingBox = OSMRectMake(minX, minY, maxX-minX, maxY-minY);
    }
}
-(OSMPoint)centerPointWithArea:(double *)pArea
{
    double dummy;
    if ( pArea == NULL )
        pArea = &dummy;

    BOOL isClosed = self.isClosed;

    NSInteger nodeCount = isClosed ? _nodes.count-1 : _nodes.count;

    if ( nodeCount > 2)  {
        if ( isClosed ) {
            // compute centroid
            double sum = 0;
            double sumX = 0;
            double sumY = 0;
            BOOL first = YES;
            OSMPoint offset = { 0, 0 };
            OSMPoint previous;
            for ( OsmNode * node in _nodes )  {
                if ( first ) {
                    offset.x = node.lon;
                    offset.y = node.lat;
                    previous.x = 0;
                    previous.y = 0;
                    first = NO;
                } else {
                    OSMPoint current = { node.lon - offset.x, node.lat - offset.y };
                    CGFloat partialSum = previous.x*current.y - previous.y*current.x;
                    sum += partialSum;
                    sumX += (previous.x + current.x) * partialSum;
                    sumY += (previous.y + current.y) * partialSum;
                    previous = current;
                }
            }
            *pArea = sum/2;
            OSMPoint point = { sumX/6/ *pArea, sumY/6/ *pArea };
            point.x += offset.x;
            point.y += offset.y;
            return point;
        } else {
            // compute average
            double sumX = 0, sumY = 0;
            for ( OsmNode * node in _nodes ) {
                sumX += node.lon;
                sumY += node.lat;
            }
            OSMPoint point = { sumX/nodeCount, sumY/nodeCount };
            return point;
        }
    } else if ( nodeCount == 2 ) {
        *pArea = 0;
        OsmNode * n1 = _nodes[0];
        OsmNode * n2 = _nodes[1];
        return OSMPointMake( (n1.lon+n2.lon)/2, (n1.lat+n2.lat)/2);
    } else if ( nodeCount == 1 ) {
        *pArea = 0;
        OsmNode * node = _nodes.lastObject;
        return OSMPointMake(node.lon, node.lat);
    } else {
        *pArea = 0;
        OSMPoint pt = { 0, 0 };
        return pt;
    }
}

-(OSMPoint)centerPoint
{
    return [self centerPointWithArea:NULL];
}

-(double)lengthInMeters
{
    BOOL first = YES;
    double len = 0;
    OSMPoint prev = { 0, 0 };
    for ( OsmNode * node in _nodes ) {
        OSMPoint pt = node.location;
        if ( !first ) {
            len += GreatCircleDistance( pt, prev );
        }
        first = NO;
        prev = pt;
    }
    return len;
}

// pick a point close to the center of the way
-(OSMPoint)selectionPoint
{
    double dist = [self lengthInMeters] / 2;
    BOOL first = YES;
    OSMPoint prev = { 0, 0 };
    for ( OsmNode * node in _nodes ) {
        OSMPoint pt = node.location;
        if ( !first ) {
            double segment = GreatCircleDistance( pt, prev );
            if ( segment >= dist ) {
                OSMPoint pos = Add( prev, Mult( Sub(pt,prev), dist/segment) );
                return pos;
            }
            dist -= segment;
        }
        first = NO;
        prev = pt;
    }
    return prev; // dummy value, shouldn't ever happen
}


+(BOOL)isClockwiseArrayOfNodes:(NSArray *)nodes
{
    if ( nodes.count < 4 || nodes[0] != nodes.lastObject )
        return NO;
    CGFloat sum = 0;
    BOOL first = YES;
    OSMPoint offset;
    OSMPoint previous;
    for ( OsmNode * node in nodes )  {
        OSMPoint point = node.location;
        if ( first ) {
            offset = point;
            previous.x = previous.y = 0;
            first = NO;
        } else {
            OSMPoint current = { point.x - offset.x, point.y - offset.y };
            sum += previous.x*current.y - previous.y*current.x;
            previous = current;
        }
    }
    return sum >= 0;
}

-(BOOL)isClockwise
{
    return [OsmWay isClockwiseArrayOfNodes:self.nodes];
}

+(CGPathRef)shapePathForNodes:(NSArray *)nodes forward:(BOOL)forward withRefPoint:(OSMPoint *)pRefPoint CF_RETURNS_RETAINED;
{
    if ( nodes.count == 0 || nodes[0] != nodes.lastObject )
        return nil;
    CGMutablePathRef path = CGPathCreateMutable();
    BOOL first = YES;
    // want loops to run clockwise
    NSEnumerator * enumerator = forward ? nodes.objectEnumerator : nodes.reverseObjectEnumerator;
    for ( OsmNode * n in enumerator ) {
        OSMPoint pt = MapPointForLatitudeLongitude( n.lat, n.lon );
        if ( first ) {
            first = NO;
            *pRefPoint = pt;
            CGPathMoveToPoint(path, NULL, 0, 0);
        } else {
            CGPathAddLineToPoint(path, NULL, (pt.x-pRefPoint->x)*PATH_SCALING, (pt.y-pRefPoint->y)*PATH_SCALING );
        }
    }
    return path;
}

-(CGPathRef)shapePathForObjectWithRefPoint:(OSMPoint *)pRefPoint CF_RETURNS_RETAINED;
{
    return [OsmWay shapePathForNodes:self.nodes forward:self.isClockwise withRefPoint:pRefPoint];
}

-(BOOL)hasDuplicatedNode
{
    OsmNode * prev = nil;
    for ( OsmNode * node in _nodes ) {
        if ( node == prev )
            return YES;
        prev = node;
    }
    return NO;
}

-(OsmNode *)connectsToWay:(OsmWay *)way
{
    if ( _nodes.count > 0 && way.nodes.count > 0 ) {
        if ( _nodes[0] == way.nodes[0] || _nodes[0] == way.nodes.lastObject )
            return _nodes[0];
        if ( _nodes.lastObject == way.nodes[0] || _nodes.lastObject == way.nodes.lastObject )
            return _nodes.lastObject;
    }
    return nil;
}

-(NSInteger)segmentClosestToPoint:(OSMPoint)point
{
    NSInteger best = -1;
    double bestDist = 100000000.0;
    for ( NSInteger index = 0; index+1 < _nodes.count; ++index ) {
        OsmNode * this = _nodes[index];
        OsmNode * next = _nodes[index+1];
        double dist = DistanceFromPointToLineSegment(point, this.location, next.location);
        if ( dist < bestDist ) {
            bestDist = dist;
            best = index;
        }
    }
    return best;
}

-(id)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if ( self ) {
        _nodes    = [coder decodeObjectForKey:@"nodes"];
        _constructed = YES;
#if DEBUG
        for ( OsmNode * node in _nodes ) {
            assert( node.wayCount > 0 );
        }
#endif
    }
    return self;
}

-(void)encodeWithCoder:(NSCoder *)coder
{
#if DEBUG
    for ( OsmNode * node in _nodes ) {
        assert( node.wayCount > 0 );
    }
#endif

    [super encodeWithCoder:coder];
    [coder encodeObject:_nodes forKey:@"nodes"];
}

@end
