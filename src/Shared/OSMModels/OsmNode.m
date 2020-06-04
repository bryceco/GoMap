//
//  OsmNode.m
//  Go Map!!
//
//  Created by Wolfgang Timme on 1/18/20.
//  Copyright © 2020 Bryce. All rights reserved.
//

#import "OsmNode.h"

#import "BingMapsGeometry.h"

@implementation OsmNode
@synthesize lon = _lon;
@synthesize lat = _lat;
@synthesize wayCount = _wayCount;

-(NSString *)description
{
    return [NSString stringWithFormat:@"OsmNode (%f,%f) %@", self.lon, self.lat, [super description]];
}

-(OsmNode *)isNode
{
    return self;
}

-(OSMPoint)location
{
    return OSMPointMake(_lon, _lat);
}

-(OSMPoint)selectionPoint
{
    return OSMPointMake(_lon, _lat);
}

-(OSMPoint)pointOnObjectForPoint:(OSMPoint)target
{
    return OSMPointMake(_lon, _lat);
}

-(BOOL)isBetterToKeepThan:(OsmNode *)node
{
    if ( (self.ident.longLongValue > 0) == (node.ident.longLongValue > 0) ) {
        // both are new or both are old, so take whichever has more tags
        return _tags.count > node.tags.count;
    }
    // take the previously existing one
    return self.ident.longLongValue > 0;
}

-(NSSet *)nodeSet
{
    return [NSSet setWithObject:self];
}
-(void)computeBoundingBox
{
    OSMRect rc = { _lon, _lat, 0, 0 };
    _boundingBox = rc;
}

-(double)distanceToLineSegment:(OSMPoint)point1 point:(OSMPoint)point2
{
    OSMPoint metersPerDegree = { MetersPerDegreeLongitude(_lat), MetersPerDegreeLatitude(_lat) };
    point1.x = (point1.x - _lon) * metersPerDegree.x;
    point1.y = (point1.y - _lat) * metersPerDegree.y;
    point2.x = (point2.x - _lon) * metersPerDegree.x;
    point2.y = (point2.y - _lat) * metersPerDegree.y;
    double dist = DistanceFromPointToLineSegment(OSMPointMake(0,0), point1, point2 );
    return dist;
}

-(void)setLongitude:(double)longitude latitude:(double)latitude undo:(UndoManager *)undo
{
    if ( _constructed ) {
        assert(undo);
        [self incrementModifyCount:undo];
        [undo registerUndoWithTarget:self selector:@selector(setLongitude:latitude:undo:) objects:@[@(_lon),@(_lat),undo]];
    }
    _lon = longitude;
    _lat = latitude;
}
-(void)serverUpdateInPlace:(OsmNode *)newerVersion
{
    [super serverUpdateInPlace:newerVersion];
    _lon = newerVersion.lon;
    _lat = newerVersion.lat;
}


-(id)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if ( self ) {
        if ( [coder allowsKeyedCoding] ) {
            _lat        = [coder decodeDoubleForKey:@"lat"];
            _lon        = [coder decodeDoubleForKey:@"lon"];
            _wayCount    = [coder decodeIntegerForKey:@"wayCount"];
        } else {
            NSUInteger len;
            _lat        = *(double        *)[coder decodeBytesWithReturnedLength:&len];
            _lon        = *(double        *)[coder decodeBytesWithReturnedLength:&len];
            _wayCount    = *(NSInteger    *)[coder decodeBytesWithReturnedLength:&len];
        }
        _constructed = YES;
    }
    return self;
}

-(void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder:coder];
    if ( [coder allowsKeyedCoding] ) {
        [coder encodeDouble:_lat forKey:@"lat"];
        [coder encodeDouble:_lon forKey:@"lon"];
        [coder encodeInteger:_wayCount    forKey:@"wayCount"];
    } else {
        [coder encodeBytes:&_lat length:sizeof _lat];
        [coder encodeBytes:&_lon length:sizeof _lon];
        [coder encodeBytes:&_wayCount length:sizeof _wayCount];
    }
}

-(NSInteger)wayCount
{
    return _wayCount;
}
-(void)setWayCount:(NSInteger)wayCount undo:(UndoManager *)undo
{
    if ( _constructed && undo ) {
        [undo registerUndoWithTarget:self selector:@selector(setWayCount:undo:) objects:@[@(_wayCount),undo]];
    }
    _wayCount = wayCount;
}

@end
