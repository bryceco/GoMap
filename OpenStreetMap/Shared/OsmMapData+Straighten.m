//
//  OsmMapData+Straighten.m
//  Go Map!!
//
//  Created by Bryce on 7/9/14.
//  Copyright (c) 2014 Bryce. All rights reserved.
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
		for ( OsmMember * member in [relation.members copy] ) {
			if ( member.ref == wayA ) {

				if (relation.isRestriction) {
					NSInteger index = [relation.members indexOfObject:member];

					OsmMember * via = [relation memberByRole:@"via"];
					if (via && [wayB.nodes indexOfObject:via.ref] != NSNotFound) {
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
					OsmMember * newMember = [[OsmMember alloc] initWithRef:wayB role:member.role];
					[self addMember:newMember toRelation:relation atIndex:relation.members.count];
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
	if ( selectedWay.nodes.lastObject == otherWay.nodes[0] ) {
		[_undoManager registerUndoComment:NSLocalizedString(@"Join",nil)];
		for ( OsmNode * n in otherWay.nodes ) {
			[self addNode:n toWay:selectedWay atIndex:selectedWay.nodes.count];
		}
	} else if ( selectedWay.nodes.lastObject == otherWay.nodes.lastObject ) {
		[_undoManager registerUndoComment:NSLocalizedString(@"Join",nil)];
		for ( OsmNode * n in [[otherWay.nodes reverseObjectEnumerator] allObjects] ) {
			[self addNode:n toWay:selectedWay atIndex:selectedWay.nodes.count];
		}
	} else if ( selectedWay.nodes[0] == otherWay.nodes[0] ) {
		[_undoManager registerUndoComment:NSLocalizedString(@"Join",nil)];
		for ( OsmNode * n in otherWay.nodes ) {
			[self addNode:n toWay:selectedWay atIndex:0];
		}
	} else if ( selectedWay.nodes[0] == otherWay.nodes.lastObject ) {
		[_undoManager registerUndoComment:NSLocalizedString(@"Join",nil)];
		for ( OsmNode * n in [[otherWay.nodes reverseObjectEnumerator] allObjects] ) {
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

#if 0
-(void)makeConvex:(OsmWay *)way
{
	NSMutableArray * nodes = [way.nodes mutableCopy];
	[nodes removeLastObject];

	points = nodes.map(function(n) { return projection(n.loc); }),

	sign = d3.geom.polygon(points).area() > 0 ? 1 : -1,
	hull = d3.geom.hull(points);
	// D3 convex hulls go counterclockwise..
	if (sign === -1) {
		nodes.reverse();
		points.reverse();
	}

	for (NSInteger i = 0; i < hull.length - 1; i++) {
		var startIndex = points.indexOf(hull[i]),
		endIndex = points.indexOf(hull[i+1]),
		indexRange = (endIndex - startIndex);
		if (indexRange < 0) {
			indexRange += nodes.length;
		}
		// move interior nodes to the surface of the convex hull..
		for (var j = 1; j < indexRange; j++) {
			var point = iD.geo.interp(hull[i], hull[i+1], j / indexRange),
			node = nodes[(j + startIndex) % nodes.length].move(projection.invert(point));
			graph = graph.replace(node);
		}
	}
	return graph;
};

-(BOOL)circularizeWay:(OsmWay *)way
{
	if ( !way.isClosed )
		return NO;
	maxAngle = (maxAngle || 20) * Math.PI / 180;
	var action = function(graph) {
		var way = graph.entity(wayId);
		if (!way.isConvex(graph)) {
			graph = action.makeConvex(graph);
		}
		var nodes = _.uniq(graph.childNodes(way)),
		keyNodes = nodes.filter(function(n) { return graph.parentWays(n).length !== 1; }),
		points = nodes.map(function(n) { return projection(n.loc); }),
		keyPoints = keyNodes.map(function(n) { return projection(n.loc); }),
		centroid = (points.length === 2) ? iD.geo.interp(points[0], points[1], 0.5) : d3.geom.polygon(points).centroid(),
		radius = d3.median(points, function(p) { return iD.geo.euclideanDistance(centroid, p); }),
		sign = d3.geom.polygon(points).area() > 0 ? 1 : -1,
		ids;
		// we need atleast two key nodes for the algorithm to work
		if (!keyNodes.length) {
			keyNodes = [nodes[0]];
			keyPoints = [points[0]];
		}
		if (keyNodes.length === 1) {
			var index = nodes.indexOf(keyNodes[0]),
			oppositeIndex = Math.floor((index + nodes.length / 2) % nodes.length);
			keyNodes.push(nodes[oppositeIndex]);
			keyPoints.push(points[oppositeIndex]);
		}
		// key points and nodes are those connected to the ways,
		// they are projected onto the circle, inbetween nodes are moved
		// to constant intervals between key nodes, extra inbetween nodes are
		// added if necessary.
		for (var i = 0; i < keyPoints.length; i++) {
			var nextKeyNodeIndex = (i + 1) % keyNodes.length,
			startNode = keyNodes[i],
			endNode = keyNodes[nextKeyNodeIndex],
			startNodeIndex = nodes.indexOf(startNode),
			endNodeIndex = nodes.indexOf(endNode),
			numberNewPoints = -1,
			indexRange = endNodeIndex - startNodeIndex,
			distance, totalAngle, eachAngle, startAngle, endAngle,
			angle, loc, node, j,
			inBetweenNodes = [];
			if (indexRange < 0) {
				indexRange += nodes.length;
			}
			// position this key node
			distance = iD.geo.euclideanDistance(centroid, keyPoints[i]);
			if (distance === 0) { distance = 1e-4; }
			keyPoints[i] = [
							centroid[0] + (keyPoints[i][0] - centroid[0]) / distance * radius,
							centroid[1] + (keyPoints[i][1] - centroid[1]) / distance * radius];
			graph = graph.replace(keyNodes[i].move(projection.invert(keyPoints[i])));
			// figure out the between delta angle we want to match to
			startAngle = Math.atan2(keyPoints[i][1] - centroid[1], keyPoints[i][0] - centroid[0]);
			endAngle = Math.atan2(keyPoints[nextKeyNodeIndex][1] - centroid[1], keyPoints[nextKeyNodeIndex][0] - centroid[0]);
			totalAngle = endAngle - startAngle;
			// detects looping around -pi/pi
			if (totalAngle * sign > 0) {
				totalAngle = -sign * (2 * Math.PI - Math.abs(totalAngle));
			}
			do {
				numberNewPoints++;
				eachAngle = totalAngle / (indexRange + numberNewPoints);
			} while (Math.abs(eachAngle) > maxAngle);
			// move existing points
			for (j = 1; j < indexRange; j++) {
				angle = startAngle + j * eachAngle;
				loc = projection.invert([
										 centroid[0] + Math.cos(angle)*radius,
										 centroid[1] + Math.sin(angle)*radius]);
				node = nodes[(j + startNodeIndex) % nodes.length].move(loc);
				graph = graph.replace(node);
			}
			// add new inbetween nodes if necessary
			for (j = 0; j < numberNewPoints; j++) {
				angle = startAngle + (indexRange + j) * eachAngle;
				loc = projection.invert([
										 centroid[0] + Math.cos(angle) * radius,
										 centroid[1] + Math.sin(angle) * radius]);
				node = iD.Node({loc: loc});
				graph = graph.replace(node);
				nodes.splice(endNodeIndex + j, 0, node);
				inBetweenNodes.push(node.id);
			}
			// Check for other ways that share these keyNodes..
			// If keyNodes are adjacent in both ways,
			// we can add inBetween nodes to that shared way too..
			if (indexRange === 1 && inBetweenNodes.length) {
				var startIndex1 = way.nodes.lastIndexOf(startNode.id),
				endIndex1 = way.nodes.lastIndexOf(endNode.id),
				wayDirection1 = (endIndex1 - startIndex1);
				if (wayDirection1 < -1) { wayDirection1 = 1;}
				/*jshint -W083 */
				_.each(_.without(graph.parentWays(keyNodes[i]), way), function(sharedWay) {
					if (sharedWay.areAdjacent(startNode.id, endNode.id)) {
						var startIndex2 = sharedWay.nodes.lastIndexOf(startNode.id),
						endIndex2 = sharedWay.nodes.lastIndexOf(endNode.id),
						wayDirection2 = (endIndex2 - startIndex2),
						insertAt = endIndex2;
						if (wayDirection2 < -1) { wayDirection2 = 1;}
						if (wayDirection1 !== wayDirection2) {
							inBetweenNodes.reverse();
							insertAt = startIndex2;
						}
						for (j = 0; j < inBetweenNodes.length; j++) {
							sharedWay = sharedWay.addNode(inBetweenNodes[j], insertAt + j);
						}
						graph = graph.replace(sharedWay);
					}
				});
				/*jshint +W083 */
			}
		}
		// update the way to have all the new nodes
		ids = nodes.map(function(n) { return n.id; });
		ids.push(ids[0]);
		way = way.update({nodes: ids});
		graph = graph.replace(way);
		return graph;
	};
	action.disabled = function(graph) {
		if (!graph.entity(wayId).isClosed())
			return 'not_closed';
	};
	return action;
}
#endif

@end
