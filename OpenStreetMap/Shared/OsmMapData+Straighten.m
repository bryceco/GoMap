//
//  OsmMapData+Straighten.m
//  Go Map!!
//
//  Created by Bryce Cogswell on 7/9/14.
//  Copyright (c) 2014 Bryce Cogswell. All rights reserved.
//


#import "OsmMapData+Straighten.h"
#import "OsmObjects.h"
#import "UndoManager.h"
#import "VectorMath.h"



@implementation OsmMapData (Straighten)

#pragma mark unjoinNodeFromWway

- (BOOL)disconnectNode:(OsmNode *)node fromWay:(OsmWay *)way
{
	return NO;
}

#pragma mark straighten

static double positionAlongWay( OSMPoint node, OSMPoint start, OSMPoint end )
{
	return ((node.x - start.x) * (end.x - start.x) + (node.y - start.y) * (end.y - start.y)) / MagSquared(Sub(end,start));
}

- (BOOL)straightenWay:(OsmWay *)way
{
	NSInteger count = way.nodes.count;
	OSMPoint points[ count ];
	for ( NSInteger i = 0; i < count; ++i ) {
		OsmNode * n = way.nodes[i];
		OSMPoint p = n.location;
		points[ i ].x = p.x;
		points[ i ].y = lat2latp(p.y);
	}
	OSMPoint startPoint = points[0];
	OSMPoint endPoint = points[count-1];

	double threshold = 0.2 * DistanceFromPointToPoint( startPoint, endPoint );

	for ( NSInteger i = 1; i < count-1; i++) {
		OsmNode * node = way.nodes[i];
		OSMPoint point = points[i];

		double u = positionAlongWay( point, startPoint, endPoint );
		OSMPoint newPoint = Add( startPoint, Mult( Sub(endPoint, startPoint), u ) );

		double dist = DistanceFromPointToPoint( newPoint, point );
		if ( dist > threshold )
			return NO;

		// if node is interesting then move it, otherwise delete it.
		if ( node.wayCount > 1 || node.relations.count > 0 || node.hasInterestingTags ) {
			points[i] = newPoint;
		} else {
			// safe to delete
			points[i].x = points[i].y = nan("");
		}
	}

	[_undoManager registerUndoComment:NSLocalizedString(@"Straighten",nil)];

	for ( NSInteger i = count-1; i >= 0; --i ) {
		if ( isnan( points[i].x ) ) {
			[self deleteNodeInWay:way index:i];
		} else {
			OsmNode * node = way.nodes[i];
			[self setLongitude:points[i].x latitude:latp2lat(points[i].y) forNode:node inWay:way];
		}
	}

	return YES;
}

#pragma mark reverse

NSString * reverseKey( NSString * key )
{
	NSDictionary * replacements = @{ @":right"		: @":left",
									 @":left"		: @":right",
									 @":forward"	: @":backward",
									 @":backward"	: @":forward"
									 };
	__block NSString * newKey = key;
	[replacements enumerateKeysAndObjectsUsingBlock:^(NSString * k, NSString * v, BOOL *stop) {
		if ( [key hasSuffix:k] ) {
			newKey = [newKey stringByReplacingOccurrencesOfString:k withString:v options:NSBackwardsSearch range:NSMakeRange(0, newKey.length)];
			*stop = YES;
		}
	}];
	return newKey;
}

static BOOL isNumeric( NSString * s )
{
	static NSRegularExpression * regex = nil;
	if ( regex == nil ) {
		NSString * numeric = @"^[+\\-]?[\\d.]";
		regex = [NSRegularExpression regularExpressionWithPattern:numeric options:NSRegularExpressionCaseInsensitive error:NULL];
	}
	NSRange r = [regex rangeOfFirstMatchInString:s options:0 range:NSMakeRange(0,s.length)];
	return r.length > 0;
}

NSString * reverseValue( NSString * key, NSString * value)
{
	if ( [key isEqualToString:@"incline"] && isNumeric(value)) {
		unichar ch = [value characterAtIndex:0];
		if ( ch == '-' )
			return [value substringFromIndex:1];
		else
			return [NSString stringWithFormat:@"-%@", ch == '+' ? [value substringFromIndex:1] : value];
	} else if ([key isEqualToString:@"incline"] || [key isEqualToString:@"direction"] ) {
		if ( [value isEqualToString:@"up"] )
			return @"down";
		if ( [value isEqualToString:@"down"] )
			return @"up";
		return value;
	} else {
		if ( [value isEqualToString:@"left"] )
			return @"right";
		if ( [value isEqualToString:@"right"] )
			return @"left";
		return value;
	}
}


- (BOOL)reverseWay:(OsmWay *)way
{
	NSDictionary * roleReversals = @{
		@"forward" : @"backward",
		@"backward" : @"forward",
		@"north" : @"south",
		@"south" : @"north",
		@"east" : @"west",
		@"west" : @"east"
	};

	[_undoManager registerUndoComment:NSLocalizedString(@"Reverse",nil)];

	// reverse nodes
	NSArray * newNodes = [[way.nodes reverseObjectEnumerator] allObjects];
	for ( NSInteger i = 0; i < newNodes.count; ++i ) {
		[self addNode:newNodes[i] toWay:way atIndex:i];
	}
	while ( way.nodes.count > newNodes.count ) {
		[self deleteNodeInWay:way index:way.nodes.count-1];
	}

	// reverse tags
	__block NSMutableDictionary * newTags = [NSMutableDictionary new];
	[way.tags enumerateKeysAndObjectsUsingBlock:^(NSString * k, NSString * v, BOOL *stop) {
		k = reverseKey(k);
		v = reverseValue(k, v);
		[newTags setObject:v forKey:k];
	}];
	[self setTags:newTags forObject:way];

	// reverse roles in relations the way belongs to
	for ( OsmRelation * relation in way.relations ) {
		for ( OsmMember * member in [relation.members copy] ) {
			if ( member.ref == way ) {
				NSString * newRole = roleReversals[ member.role ];
				if ( newRole ) {
					NSInteger index = [relation.members indexOfObject:member];
					OsmMember * newMember = [[OsmMember alloc] initWithRef:way role:newRole];
					[self deleteMemberInRelation:relation index:index];
					[self addMember:newMember toRelation:relation atIndex:index];
				}
			}
		}
	}
	return YES;
}

#pragma mark disconnect

// disconnect all other ways from the selected way joined to it at node
- (BOOL)disconnectWay:(OsmWay *)selectedWay atNode:(OsmNode *)node
{
	if ( node.wayCount < 2 )
		return NO;

	[_undoManager registerUndoComment:NSLocalizedString(@"Disconnect",nil)];

	CLLocationCoordinate2D loc = { node.lat, node.lon };
	OsmNode * newNode = [self createNodeAtLocation:loc];
	[self setTags:node.tags forObject:newNode];

	[_ways enumerateKeysAndObjectsUsingBlock:^(NSNumber * ident, OsmWay * way, BOOL *stop) {
		if ( way == selectedWay )
			return;
		BOOL disconnectWay = NO;
		for ( OsmNode * n in way.nodes ) {
			if ( n == node ) {
				disconnectWay = YES;
				break;
			}
		}
		if ( disconnectWay ) {
			for (NSInteger i = way.nodes.count-1; i >= 0; --i ) {
				if ( way.nodes[i] == node) {
					[self deleteNodeInWay:way index:i];
					[self addNode:newNode toWay:way atIndex:i];
				}
			}
		}
	}];
	return YES;
}

#pragma mark split

// if the way is closed, we need to search for a partner node
// to split the way at.
//
// The following looks for a node that is both far away from
// the initial node in terms of way segment length and nearby
// in terms of beeline-distance. This assures that areas get
// split on the most "natural" points (independent of the number
// of nodes).
// For example: bone-shaped areas get split across their waist
// line, circles across the diameter.
static NSInteger splitArea(NSArray * nodes, NSInteger idxA)
{
	NSInteger count = nodes.count;
	double lengths[ count ];
	double best = 0;
	NSInteger idxB = 0;

	assert(idxA >= 0 && idxA < count);

	// calculate lengths
	double length = 0;
	for (NSInteger i = (idxA+1)%count; i != idxA; i = (i+1)%count) {
		OsmNode * n1 = nodes[i];
		OsmNode * n2 = nodes[(i-1+count)%count];
		length += DistanceFromPointToPoint(n1.location,n2.location);
		lengths[i] = length;
	}
	lengths[idxA] = 0.0;	// never used, but need it to convince static analyzer that it isn't an unitialized variable
	length = 0;
	for (NSInteger i = (idxA-1+count)%count; i != idxA; i = (i-1+count)%count) {
		OsmNode * n1 = nodes[i];
		OsmNode * n2 = nodes[(i+1)%count];
		length += DistanceFromPointToPoint(n1.location,n2.location);
		if (length < lengths[i])
			lengths[i] = length;
	}

	// determine best opposite node to split
	for (NSInteger i = 0; i < count; i++) {
		if ( i == idxA )
			continue;
		OsmNode * n1 = nodes[idxA];
		OsmNode * n2 = nodes[i];
		double cost = lengths[i] / DistanceFromPointToPoint(n1.location,n2.location);
		if (cost > best) {
			idxB = i;
			best = cost;
		}
	}

	return idxB;
}



-(BOOL)splitWay:(OsmWay *)selectedWay atNode:(OsmNode *)node
{
	BOOL createRelations = NO;

	[_undoManager registerUndoComment:NSLocalizedString(@"Split",nil)];

	OsmWay * wayA = selectedWay;
	OsmWay * wayB = [self createWay];

	[self setTags:wayA.tags forObject:wayB];

	OsmRelation * isOuter = wayA.isSimpleMultipolygonOuterMember ? wayA.relations.lastObject : nil;
	BOOL isClosed = wayA.isClosed;
	if (wayA.isClosed) {

		// remove duplicated node
		[self deleteNodeInWay:wayA index:wayA.nodes.count-1];

		// get segment indices
		NSInteger idxA = [wayA.nodes indexOfObject:node];
		NSInteger idxB = splitArea(wayA.nodes, idxA);

		// build new way
		for ( NSInteger i = idxB; i != idxA; i = (i+1)%wayA.nodes.count) {
			[self addNode:wayA.nodes[i] toWay:wayB atIndex:wayB.nodes.count];
		}

		// delete moved nodes from original way
		for ( OsmNode * n in wayB.nodes ) {
			NSInteger i = [wayA.nodes indexOfObject:n];
			[self deleteNodeInWay:wayA index:i];
		}

		// rebase A so it starts with selected node
		while ( wayA.nodes[0] != node ) {
			[self addNode:wayA.nodes[0] toWay:wayA atIndex:wayA.nodes.count];
			[self deleteNodeInWay:wayA index:0];
		}

		// add shared endpoints
		[self addNode:wayB.nodes[0] toWay:wayA atIndex:wayA.nodes.count];
		[self addNode:wayA.nodes[0] toWay:wayB atIndex:wayB.nodes.count];

	} else {

		// place common node in new way
		[self addNode:node toWay:wayB atIndex:0];

		// move remaining nodes to 2nd way
		NSInteger idx = [wayA.nodes indexOfObject:node] + 1;
		while ( idx < wayA.nodes.count ) {
			[self addNode:wayA.nodes[idx] toWay:wayB atIndex:wayB.nodes.count];
			[self deleteNodeInWay:wayA index:idx];
		}

	}

	// fix parent relations
	for ( OsmRelation * relation in wayA.relations ) {
		for ( NSInteger index = 0; index < relation.members.count; ++index ) {
			OsmMember * member = relation.members[index];
			if ( member.ref == wayA ) {

				if (relation.isRestriction) {
					OsmMember * via = [relation memberByRole:@"via"];
					if (via && [wayB.nodes containsObject:via.ref] ) {
						// replace reference to wayA with wayB in relation
						OsmMember * memberB = [[OsmMember alloc] initWithRef:wayB role:member.role];
						[self addMember:memberB toRelation:relation atIndex:index+1];
						[self deleteMemberInRelation:relation index:index];
					}
				} else {
					if (relation == isOuter) {
						NSDictionary * merged = MergeTags(relation.tags, wayA.tags);
						[self setTags:merged forObject:relation];
						[self setTags:nil forObject:wayA];
						[self setTags:nil forObject:wayB];
					}
					
					// if this is a route relation we want to add the new member in such a way that the route maintains a consecutive sequence of ways
					BOOL insertAfter = YES;
					OsmMember * prevMem = index > 1 ? relation.members[index-1] : nil;
					OsmWay * prevWay = prevMem && [prevMem.ref isKindOfClass:[OsmWay class]] ? prevMem.ref : nil;
					if ( prevWay.nodes.count > 0 ) {
						if ( prevWay.nodes[0] == wayB.nodes[0] ||
							prevWay.nodes[0] == wayB.nodes.lastObject ||
							prevWay.nodes.lastObject == wayB.nodes[0] ||
							prevWay.nodes.lastObject == wayB.nodes.lastObject )
						{
							insertAfter = NO;
						}
					}
					OsmMember * newMember = [[OsmMember alloc] initWithRef:wayB role:member.role];
					[self addMember:newMember toRelation:relation atIndex:insertAfter?index+1:index];
					++index;
				}
			}
		}
	}

	if ( createRelations ) {
		// convert split buildings into relations
		if (!isOuter && isClosed) {
			OsmRelation * multipolygon = [self createRelation];
			NSMutableDictionary * tags = [wayA.tags mutableCopy];
			[tags setValue:@"multipolygon" forKey:@"type"];
			[self setTags:tags forObject:multipolygon];
			OsmMember * memberA = [[OsmMember alloc] initWithRef:wayA role:@"outer"];
			OsmMember * memberB = [[OsmMember alloc] initWithRef:wayB role:@"outer"];
			[self addMember:memberA toRelation:multipolygon atIndex:0];
			[self addMember:memberB toRelation:multipolygon atIndex:1];
			[self setTags:nil forObject:wayA];
			[self setTags:nil forObject:wayB];
		}
	}

	return YES;
}

#pragma mark Join

-(BOOL)joinWay:(OsmWay *)selectedWay atNode:(OsmNode *)selectedNode
{
	NSArray * ways = [self waysContainingNode:selectedNode];
	if ( ways.count != 2 )
		return NO;
	OsmWay * otherWay = nil;
	if ( ways[0] == selectedWay ) {
		otherWay = ways[1];
	} else if ( ways[1] == selectedWay ) {
		otherWay = ways[0];
	} else {
		return NO;
	}

#if 1
	// don't allow joining to a way that is part of a relation
	if ( otherWay.relations.count > 0 )
		return NO;
	if ( selectedWay.relations.count > 0 )
		return NO;
#else
	// make sure no nodes are part of a turn restriction
	NSArray * relations = [selectedWay.relations arrayByAddingObjectsFromArray:otherWay.relations];
	for ( OsmRelation * parent in relations ) {
		if ( parent.isRestriction ) {
			for ( OsmMember * m in parent.members ) {
				if ( [selectedWay.nodes containsObject:m.ref] || [otherWay.nodes containsObject:m.ref] )
					return NO;
			}
		}
	}
#endif

	// join nodes, preserving selected way
	NSInteger index = 0;
	if ( selectedWay.nodes.lastObject == otherWay.nodes[0] ) {
		[_undoManager registerUndoComment:NSLocalizedString(@"Join",nil)];
		for ( OsmNode * n in otherWay.nodes ) {
			if ( index++ == 0 )
				continue;
			[self addNode:n toWay:selectedWay atIndex:selectedWay.nodes.count];
		}
	} else if ( selectedWay.nodes.lastObject == otherWay.nodes.lastObject ) {
		[_undoManager registerUndoComment:NSLocalizedString(@"Join",nil)];
		[self reverseWay:otherWay];	// reverse the tags on other way
		for ( OsmNode * n in otherWay.nodes ) {
			if ( index++ == 0 )
				continue;
			[self addNode:n toWay:selectedWay atIndex:selectedWay.nodes.count];
		}
	} else if ( selectedWay.nodes[0] == otherWay.nodes[0] ) {
		[_undoManager registerUndoComment:NSLocalizedString(@"Join",nil)];
		[self reverseWay:otherWay];	// reverse the tags on other way
		for ( OsmNode * n in [[otherWay.nodes reverseObjectEnumerator] allObjects] ) {
			if ( index++ == 0 )
				continue;
			[self addNode:n toWay:selectedWay atIndex:0];
		}
	} else if ( selectedWay.nodes[0] == otherWay.nodes.lastObject ) {
		[_undoManager registerUndoComment:NSLocalizedString(@"Join",nil)];
		for ( OsmNode * n in [[otherWay.nodes reverseObjectEnumerator] allObjects] ) {
			if ( index++ == 0 )
				continue;
			[self addNode:n toWay:selectedWay atIndex:0];
		}
	} else {
		return NO;
	}

	// join tags
	NSDictionary * newTags = MergeTags(selectedWay.tags, otherWay.tags);
	[self setTags:newTags forObject:selectedWay];

	[self deleteWay:otherWay];

	return YES;
}

#pragma mark Circularize

static double AverageDistanceToCenter( OsmWay * way, OSMPoint center )
{
	double d = 0;
	for ( NSInteger i = 0; i < way.nodes.count - 1; i++ ) {
		OsmNode * n = way.nodes[i];
		d += hypot( n.lon - center.x, lat2latp(n.lat) - center.y );
	}
	d /= way.nodes.count - 1;
	return d;
}

static void InsertNode( OsmMapData * mapData, OsmWay * way, OSMPoint center, double ang, double radius, int index)
{
	CLLocationCoordinate2D point;
	point.longitude = center.x + sin(ang*M_PI/180)*radius;
	point.latitude  = latp2lat( center.y + cos(ang*M_PI/180)*radius );
	OsmNode * newNode = [mapData createNodeAtLocation:point];
	[mapData addNode:newNode toWay:way atIndex:index];
}

-(BOOL)circularizeWay:(OsmWay *)way
{
	if ( !way.isWay )
		return NO;
	if ( !way.isClosed )
		return NO;
	if ( way.nodes.count < 4 )
		return NO;

	OSMPoint center = [way centerPointWithArea:NULL];
	center.y = lat2latp(center.y);
	double radius = AverageDistanceToCenter(way, center);

	for ( int i = 0; i < way.nodes.count-1; i++ ) {
		OsmNode * n = way.nodes[i];
		double c = hypot( n.lon - center.x, lat2latp(n.lat) - center.y );
		double lat = latp2lat( center.y + (lat2latp(n.lat) - center.y) / c * radius );
		double lon = center.x + (n.lon - center.x) / c * radius;
		[self setLongitude:lon latitude:lat forNode:n inWay:way];
	}

	// Insert extra nodes to make circle
	// clockwise: angles decrease, wrapping round from -170 to 170
	BOOL clockwise = way.isClockwise;
	for ( int i = 0; i < way.nodes.count; ++i ) {
		int j = (i+1) % way.nodes.count;

		OsmNode * n1 = way.nodes[i];
		OsmNode * n2 = way.nodes[j];

		double a1 = atan2( n1.lon - center.x, lat2latp(n1.lat) - center.y) * (180/M_PI);
		double a2 = atan2( n2.lon - center.x, lat2latp(n2.lat) - center.y) * (180/M_PI);
		if ( clockwise ) {
			if (a2 > a1) {
				a2 -= 360;
			}
			double diff = a1 - a2;
			if  ( diff > 20 ) {
				for ( double ang = a1-20; ang > a2+10; ang -= 20 ) {
					InsertNode( self, way, center, ang, radius, i+1 );
					j++;
					i++;
				}
			}
		} else {
			if ( a1 > a2 ) {
				a1 -= 360;
			}
			double diff = a2 - a1;
			if ( diff > 20 ) {
				for ( double ang = a1 + 20; ang < a2 - 10; ang += 20 ) {
					InsertNode( self, way, center, ang, radius, i+1 );
					j++;
					i++;
				}
			}
		}
	}
	return YES;
}

#pragma mark Duplicate

-(OsmNode *)duplicateNode:(OsmNode *)node
{
	double offsetLat = -0.00005;
	double offsetLon = 0.00005;
	CLLocationCoordinate2D loc = { node.lat + offsetLat, node.lon + offsetLon };
	OsmNode * newNode = [self createNodeAtLocation:loc];
	[self setTags:node.tags forObject:newNode];
	return newNode;
}

-(OsmWay *)duplicateWay:(OsmWay *)way
{
	OsmWay * newWay = [self createWay];
	NSUInteger index = 0;
	for ( OsmNode * node in way.nodes ) {
		// check if node is a duplicate of previous node
		NSInteger prev = [way.nodes indexOfObject:node];
		OsmNode * newNode = prev < index ? newWay.nodes[prev] : [self duplicateNode:node];
		[self addNode:newNode toWay:newWay atIndex:index++];
	}
	[self setTags:way.tags forObject:newWay];
	return newWay;
}

- (OsmBaseObject *)duplicateObject:(OsmBaseObject *)object
{
	if ( object.isNode ) {
		[_undoManager registerUndoComment:NSLocalizedString(@"duplicate",nil)];
		return [self duplicateNode:object.isNode];
	}
	if ( object.isWay ) {
		[_undoManager registerUndoComment:NSLocalizedString(@"duplicate",nil)];
		return [self duplicateWay:object.isWay];
	}
	return nil;
}
@end
