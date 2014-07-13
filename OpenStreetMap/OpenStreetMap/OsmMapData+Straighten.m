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

#pragma mark straighten

static double positionAlongWay( OSMPoint node, OSMPoint start, OSMPoint end )
{
	return ((node.x - start.x) * (end.x - start.x) + (node.y - start.y) * (end.y - start.y)) / MagSquared(Sub(end,start));
}


- (BOOL)straighten:(OsmWay *)way
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

	[_undoManager registerUndoComment:@"Straighten"];

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


- (BOOL)reverse:(OsmWay *)way
{
	NSDictionary * roleReversals = @{
		@"forward" : @"backward",
		@"backward" : @"forward",
		@"north" : @"south",
		@"south" : @"north",
		@"east" : @"west",
		@"west" : @"east"
	};

	[_undoManager registerUndoComment:@"Reverse"];

	// reverse nodes
	NSArray * newNodes = [[way.nodes reverseObjectEnumerator] allObjects];
	while ( way.nodes.count ) {
		[self deleteNodeInWay:way index:0];
	}
	for ( NSInteger i = 0; i < newNodes.count; ++i ) {
		[self addNode:newNodes[i] toWay:way atIndex:i];
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
					OsmMember * newMember = [[OsmMember alloc] initWithType:member.type ref:(id)way role:newRole];
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

	[_undoManager registerUndoComment:@"Disconnect"];

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

#if 0
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
	double lengths[ nodes.count ];
	double best = 0;
	NSInteger idxB;

	// calculate lengths
	double length = 0;
	for (NSInteger i = (idxA+1)%nodes.count; i != idxA; i = (i+1)%nodes.count) {
		OsmNode * n1 = nodes[i];
		OsmNode * n2 = nodes[(i-1+nodes.count)%nodes.count];
		length += DistanceFromPointToPoint(n1.location,n2.location);
		lengths[i] = length;
	}
	length = 0;
	for (NSInteger i = (idxA-1+nodes.count)%nodes.count; i != idxA; i = (i-1+nodes.count)%nodes.count) {
		OsmNode * n1 = nodes[i];
		OsmNode * n2 = nodes[(i+1)%nodes.count];
		length += DistanceFromPointToPoint(n1.location,n2.location);
		if (length < lengths[i])
			lengths[i] = length;
	}

	// determine best opposite node to split
	for (NSInteger i = 0; i < nodes.count; i++) {
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
	[_undoManager registerUndoComment:@"Split"];

	OsmWay * wayA = selectedWay;
	OsmWay * wayB = [self createWay];

	[self setTags:wayA.tags forObject:wayB];

//	BOOL isOuter = NO; // iD.geo.isSimpleMultipolygonOuterMember(wayA, graph);

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

		// add shared endpoints
		[self addNode:wayB.nodes[0] toWay:wayA atIndex:wayA.nodes.count];
		[self addNode:wayA.nodes[0] toWay:wayB atIndex:wayB.nodes.count];

	} else {

		NSInteger idx = [wayA.nodes indexOfObject:node];
		while ( idx < wayA.nodes.count ) {
			[self addNode:wayA.nodes[idx] toWay:wayB atIndex:wayB.nodes.count];
			[self deleteNodeInWay:wayA index:idx];
		}

	}

	// fix parents
	for ( OsmRelation * relation in wayA.relations ) {
		for ( OsmMember * member in relation.members ) {
			if ( member.ref == wayA ) {

				if (relation.isRestriction) {
					NSInteger index = [relation.members indexOfObject:member];

					OsmBaseObject * via = [relation memberByRole:@"via"];
					if (via && [wayB.nodes indexOfObject:via] != NSNotFound) {
						// replace reference to wayA with wayB in relation
						OsmMember * memberB = [[OsmMember alloc] initWithType:member.type ref:(id)wayB role:member.role];
						[self addMember:memberB toRelation:relation atIndex:index+1];
						[self deleteMemberInRelation:relation index:index];
					}
				} else {
					if (relation == isOuter) {
						graph = graph.replace(relation.mergeTags(wayA.tags));
						graph = graph.replace(wayA.update({tags: {}}));
						graph = graph.replace(wayB.update({tags: {}}));
					}

					var member = {
						id: wayB.id,
					type: 'way',
					role: relation.memberById(wayA.id).role
					};

					graph = iD.actions.AddMember(relation.id, member)(graph);
				}

			}
		}
	}

		if (!isOuter && isArea) {
			var multipolygon = iD.Relation({
			tags: _.extend({}, wayA.tags, {type: 'multipolygon'}),
			members: [
					  {id: wayA.id, role: 'outer', type: 'way'},
					  {id: wayB.id, role: 'outer', type: 'way'}
					  ]});

			graph = graph.replace(multipolygon);
			graph = graph.replace(wayA.update({tags: {}}));
			graph = graph.replace(wayB.update({tags: {}}));
		}

	return YES;
}


	var action = function(graph) {
		var candidates = action.ways(graph);
		for (var i = 0; i < candidates.length; i++) {
			graph = split(graph, candidates[i], newWayIds && newWayIds[i]);
		}
		return graph;
	};

	action.ways = function(graph) {
		var node = graph.entity(nodeId),
		parents = graph.parentWays(node),
		hasLines = _.any(parents, function(parent) { return parent.geometry(graph) === 'line'; });

		return parents.filter(function(parent) {
			if (wayIds && wayIds.indexOf(parent.id) === -1)
				return false;

			if (!wayIds && hasLines && parent.geometry(graph) !== 'line')
				return false;

			if (parent.isClosed()) {
				return true;
			}

			for (var i = 1; i < parent.nodes.length - 1; i++) {
				if (parent.nodes[i] === nodeId) {
					return true;
				}
			}

			return false;
		});
	};

	action.disabled = function(graph) {
		var candidates = action.ways(graph);
		if (candidates.length === 0 || (wayIds && wayIds.length !== candidates.length))
			return 'not_eligible';
	};

	action.limitWays = function(_) {
		if (!arguments.length) return wayIds;
		wayIds = _;
		return action;
	};

	return action;
};
#endif

@end
