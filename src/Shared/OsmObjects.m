//
//  OsmObjects.m
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 10/27/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>

#import "iosapi.h"
#import "CommonTagList.h"
#import "CurvedTextLayer.h"
#import "DLog.h"
#import "OsmObjects.h"
#import "OsmMapData.h"
#import "UndoManager.h"


extern const double PATH_SCALING;


BOOL IsOsmBooleanTrue( NSString * value )
{
	if ( [value isEqualToString:@"true"] )
		return YES;
	if ( [value isEqualToString:@"yes"] )
		return YES;
	if ( [value isEqualToString:@"1"] )
		return YES;
	return NO;
}
BOOL IsOsmBooleanFalse( NSString * value )
{
	if ( [value respondsToSelector:@selector(boolValue)] ) {
		BOOL b = [value boolValue];
		return !b;
	}
	if ( [value isEqualToString:@"false"] )
		return YES;
	if ( [value isEqualToString:@"no"] )
		return YES;
	if ( [value isEqualToString:@"0"] )
		return YES;
	return NO;
}
NSString * OsmValueForBoolean( BOOL b )
{
	return b ? @"true" : @"false";
}

#pragma mark OsmWay

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
	return [CommonTagList isArea:self];
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
	OSMPoint	bestPoint = { 0, 0 };
	double		bestDist = 360 * 360;
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
			if ( loc.y < minY )		minY = loc.y;
			if ( loc.x < minX )		minX = loc.x;
			if ( loc.y > maxY )		maxY = loc.y;
			if ( loc.x > maxX )		maxX = loc.x;
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
		_nodes	= [coder decodeObjectForKey:@"nodes"];
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

#pragma mark OsmRelation

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
	[new minusSet:common];	// added items
	[old minusSet:common];	// removed items
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
			continue;	// unresolved reference

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
	NSMutableArray	*	loopList = [NSMutableArray new];
	NSMutableArray	*	loop = nil;
	NSMutableArray	*	members = [memberList mutableCopy];
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
				[loop addObject:loop[0]];	// force-close the loop
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

	CGMutablePathRef 	path = CGPathCreateMutable();
	BOOL				hasRefPoint = NO;
	OSMPoint			refPoint;

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
	NSSet * all = [self allMemberObjects];	// might be a super relation, so need to recurse down
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

#if 0
	__block contains = NO;
	[self forAllMemberObjects:^(OsmBaseObject * obj) {
		if ( obj == object ) {
			contains = YES;
			break;
		}
		if ( object.isNode && obj.isWay ) {
			if ( && obj.isWay.nodes containsObject:object]) )
		{
		}
	}];
#endif
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
		_members	= [coder decodeObjectForKey:@"members"];
		_constructed = YES;
	}
	return self;
}

@end

#pragma mark OsmMember

@implementation OsmMember

-(NSString *)description
{
	return [NSString stringWithFormat:@"%@ role=%@; type=%@;ref=%@;", [super description], _role, _type, _ref ];
}
-(id)initWithType:(NSString *)type ref:(NSNumber *)ref role:(NSString *)role
{
	self = [super init];
	if ( self ) {
		_type = type;
		_ref = ref;
		_role = role;
	}
	return self;
}
-(id)initWithRef:(OsmBaseObject *)ref role:(NSString *)role
{
	self = [super init];
	if ( self ) {
		_ref = ref;
		_role = role;
		if ( ref.isNode )
			_type = @"node";
		else if ( ref.isWay )
			_type = @"way";
		else if ( ref.isRelation )
			_type = @"relation";
		else {
			_type = nil;
		}
	}
	return self;
}

-(void)resolveRefToObject:(OsmBaseObject *)object
{
	assert( [_ref isKindOfClass:[NSNumber class]] || [_ref isKindOfClass:[OsmBaseObject class]] );
	assert( [object isKindOfClass:[NSNumber class]] || (object.isNode && self.isNode) || (object.isWay && self.isWay) || (object.isRelation && self.isRelation) );
	_ref = object;
}


-(BOOL)isNode
{
	return [_type isEqualToString:@"node"];
}
-(BOOL)isWay
{
	return [_type isEqualToString:@"way"];
}
-(BOOL)isRelation
{
	return [_type isEqualToString:@"relation"];
}

-(void)encodeWithCoder:(NSCoder *)coder
{
	OsmBaseObject * o = _ref;
	NSNumber * ref = [_ref isKindOfClass:[OsmBaseObject class]] ? o.ident : _ref;
	[coder encodeObject:_type	forKey:@"type"];
	[coder encodeObject:ref		forKey:@"ref"];
	[coder encodeObject:_role	forKey:@"role"];
}
-(id)initWithCoder:(NSCoder *)coder
{
	self = [super init];
	if ( self ) {
		_type	= [coder decodeObjectForKey:@"type"];
		_ref	= [coder decodeObjectForKey:@"ref"];
		_role	= [coder decodeObjectForKey:@"role"];
	}
	return self;
}

@end
