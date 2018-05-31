//
//  OsmMapData+Edit.m
//  Go Map!!
//
//  Created by Bryce Cogswell on 7/9/14.
//  Copyright (c) 2014 Bryce Cogswell. All rights reserved.
//

#import "DLog.h"
#import "OsmMapData+Edit.h"
#import "OsmObjects.h"
#import "UndoManager.h"
#import "VectorMath.h"



@interface OsmMapData ()
// private methods in main file
-(void)addNodeUnsafe:(OsmNode *)node toWay:(OsmWay *)way atIndex:(NSInteger)index;
-(void)deleteNodeInWayUnsafe:(OsmWay *)way index:(NSInteger)index;
-(void)deleteWayUnsafe:(OsmWay *)way;
-(void)addMemberUnsafe:(OsmMember *)member toRelation:(OsmRelation *)relation atIndex:(NSInteger)index;
-(void)deleteMemberInRelationUnsafe:(OsmRelation *)relation index:(NSInteger)index;
@end


@implementation OsmMapData (Edit)


#pragma mark straightenWay

static double positionAlongWay( OSMPoint node, OSMPoint start, OSMPoint end )
{
	return ((node.x - start.x) * (end.x - start.x) + (node.y - start.y) * (end.y - start.y)) / MagSquared(Sub(end,start));
}

- (EditAction)canStraightenWay:(OsmWay *)way
{
	NSInteger count = way.nodes.count;

	NSMutableArray * points = [NSMutableArray arrayWithCapacity:count];
	for ( NSInteger i = 0; i < count; ++i ) {
		OsmNode * n = way.nodes[i];
		OSMPoint p = { n.lon, lat2latp(n.lat) };
		points[i] = [OSMPointBoxed pointWithPoint:p];
	}
	OSMPoint startPoint = ((OSMPointBoxed *)points[0]).point;
	OSMPoint endPoint = ((OSMPointBoxed *)points[count-1]).point;

	double threshold = 0.2 * DistanceFromPointToPoint( startPoint, endPoint );

	for ( NSInteger i = 1; i < count-1; i++) {
		OsmNode * node = way.nodes[i];
		OSMPoint point = ((OSMPointBoxed *)points[i]).point;

		double u = positionAlongWay( point, startPoint, endPoint );
		OSMPoint newPoint = Add( startPoint, Mult( Sub(endPoint, startPoint), u ) );

		double dist = DistanceFromPointToPoint( newPoint, point );
		if ( dist > threshold )
			return nil;

		// if node is interesting then move it, otherwise delete it.
		if ( node.wayCount > 1 || node.parentRelations.count > 0 || node.hasInterestingTags ) {
			points[i] = [OSMPointBoxed pointWithPoint:newPoint];
		} else {
			// safe to delete
			points[i] = [NSNull null];
		}
	}

	return ^{
		[self registerUndoCommentString:NSLocalizedString(@"Straighten",nil)];

		for ( NSInteger i = count-1; i >= 0; --i ) {
			OSMPointBoxed * point = points[i];
			if ( [point isKindOfClass:[NSNull class]] ) {
				OsmNode * node = way.nodes[i];
				EditAction canDelete = [self canDeleteNode:node fromWay:way];
				if ( canDelete ) {
					canDelete();
				}
			} else {
				OsmNode * node = way.nodes[i];
				OSMPoint pt = point.point;
				[self setLongitude:pt.x latitude:latp2lat(pt.y) forNode:node inWay:way];
			}
		}
	};
}

#pragma mark reverseWay

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


- (EditAction)canReverseWay:(OsmWay *)way
{
	NSDictionary * roleReversals = @{
		@"forward" : @"backward",
		@"backward" : @"forward",
		@"north" : @"south",
		@"south" : @"north",
		@"east" : @"west",
		@"west" : @"east"
	};

	return ^{
		[self registerUndoCommentString:NSLocalizedString(@"Reverse",nil)];

		// reverse nodes
		NSArray * newNodes = [[way.nodes reverseObjectEnumerator] allObjects];
		for ( NSInteger i = 0; i < newNodes.count; ++i ) {
			[self addNodeUnsafe:newNodes[i] toWay:way atIndex:i];
		}
		while ( way.nodes.count > newNodes.count ) {
			[self deleteNodeInWayUnsafe:way index:way.nodes.count-1];
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
		for ( OsmRelation * relation in way.parentRelations ) {
			for ( OsmMember * member in [relation.members copy] ) {
				if ( member.ref == way ) {
					NSString * newRole = roleReversals[ member.role ];
					if ( newRole ) {
						NSInteger index = [relation.members indexOfObject:member];
						OsmMember * newMember = [[OsmMember alloc] initWithRef:way role:newRole];
						[self deleteMemberInRelationUnsafe:relation index:index];
						[self addMemberUnsafe:newMember toRelation:relation atIndex:index];
					}
				}
			}
		}
	};
}

#pragma mark deleteNodeFromWay

-(BOOL)canDisconnectOrRemoveNode:(OsmNode *)node inWay:(OsmWay *)way
{
	// only care if node is an endpoiont
	if ( node == way.nodes[0] || node == way.nodes.lastObject ) {

		// we don't want to truncate a way that is a portion of a route relation, polygon, etc.
		for ( OsmRelation * relation in way.parentRelations ) {
			if ( relation.isRestriction ) {
				// only permissible if deleting interior node of via, or non-via node in from/to
				NSArray * viaList = [relation membersByRole:@"via"];
				OsmMember * from = [relation memberByRole:@"from"];
				OsmMember * to   = [relation memberByRole:@"to"];
				if ( from.ref == way || to.ref == way ) {
					if ( way.nodes.count <= 2 ) {
						return NO;	// deleting node will cause degenerate way
					}
					for ( OsmMember * viaMember in viaList ) {
						if ( viaMember.ref == node ) {
							return NO;
						} else {
							OsmBaseObject * viaObject = viaMember.ref;
							if ( [viaObject isKindOfClass:[OsmBaseObject class]] ) {
								OsmNode * common = [viaObject.isWay connectsToWay:way];
								if ( common.isNode == node ) {
									// deleting the node that connects from/to and via
									return NO;
								}
							} else {
								return NO;	// if we don't know then assume not
							}
						}
					}
				}

				// disallow deleting an endpoint of any via way, or a via node itself
				for ( OsmMember * viaMember in viaList ) {
					if ( viaMember.ref == way ) {
						// can't delete an endpoint of a via way
						return NO;
					}
				}
			} else if ( relation.isMultipolygon ) {
				// okay
			} else {
				// don't allow deleting an endpoint node of routes, etc.
				return NO;
			}
		}
	}
	return YES;
}


-(EditAction)canDeleteNode:(OsmNode *)node fromWay:(OsmWay *)way
{
	if ( ![self canDisconnectOrRemoveNode:node inWay:way] )
		return nil;

	return ^{
		BOOL needAreaFixup = way.nodes.lastObject == node  &&  way.nodes[0] == node;
		for ( NSInteger index = 0; index < way.nodes.count; ++index ) {
			if ( way.nodes[index] == node ) {
				[self deleteNodeInWayUnsafe:way index:index];
				--index;
			}
		}
		if ( way.nodes.count < 2 ) {
			EditAction delete = [self canDeleteWay:way];
			if ( delete )
				delete();	// this will also delete any relations the way belongs to
			else
				[self deleteWayUnsafe:way];
		} else if ( needAreaFixup ) {
			// special case where deleted node is first & last node of an area
			[self addNodeUnsafe:way.nodes[0] toWay:way atIndex:way.nodes.count];
		}
	};
}

#pragma mark disconnectWayAtNode

// disconnect all other ways from the selected way joined to it at node
- (EditActionReturnNode)canDisconnectWay:(OsmWay *)way atNode:(OsmNode *)node
{
	if ( ![way.nodes containsObject:node] )
		return nil;
	if ( node.wayCount < 2 )
		return nil;

	if ( ![self canDisconnectOrRemoveNode:node inWay:way] )
		return nil;

	return ^{
		[self registerUndoCommentString:NSLocalizedString(@"Disconnect",nil)];

		CLLocationCoordinate2D loc = { node.lat, node.lon };
		OsmNode * newNode = [self createNodeAtLocation:loc];
		[self setTags:node.tags forObject:newNode];

		NSInteger index;
		while ( (index = [way.nodes indexOfObject:node]) != NSNotFound ) {
			[self addNodeUnsafe:newNode toWay:way atIndex:index+1];
			[self deleteNodeInWayUnsafe:way index:index];
		}
		return newNode;
	};
}

#pragma mark splitWayAtNode

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


-(EditActionReturnWay)canSplitWay:(OsmWay *)selectedWay atNode:(OsmNode *)node
{
	return ^{
		[self registerUndoCommentString:NSLocalizedString(@"Split",nil)];

		OsmWay * wayA = selectedWay;
		OsmWay * wayB = [self createWay];

		[self setTags:wayA.tags forObject:wayB];

		OsmRelation * wayIsOuter = wayA.isSimpleMultipolygonOuterMember ? wayA.parentRelations.lastObject : nil;	// only 1 parent relation if it is simple

		if (wayA.isClosed) {

			// remove duplicated node
			[self deleteNodeInWayUnsafe:wayA index:wayA.nodes.count-1];

			// get segment indices
			NSInteger idxA = [wayA.nodes indexOfObject:node];
			NSInteger idxB = splitArea(wayA.nodes, idxA);

			// build new way
			for ( NSInteger i = idxB; i != idxA; i = (i+1)%wayA.nodes.count) {
				[self addNodeUnsafe:wayA.nodes[i] toWay:wayB atIndex:wayB.nodes.count];
			}

			// delete moved nodes from original way
			for ( OsmNode * n in wayB.nodes ) {
				NSInteger i = [wayA.nodes indexOfObject:n];
				[self deleteNodeInWayUnsafe:wayA index:i];
			}

			// rebase A so it starts with selected node
			while ( wayA.nodes[0] != node ) {
				[self addNodeUnsafe:wayA.nodes[0] toWay:wayA atIndex:wayA.nodes.count];
				[self deleteNodeInWayUnsafe:wayA index:0];
			}

			// add shared endpoints
			[self addNodeUnsafe:wayB.nodes[0] toWay:wayA atIndex:wayA.nodes.count];
			[self addNodeUnsafe:wayA.nodes[0] toWay:wayB atIndex:wayB.nodes.count];

		} else {

			// place common node in new way
			[self addNodeUnsafe:node toWay:wayB atIndex:0];

			// move remaining nodes to 2nd way
			const NSInteger idx = [wayA.nodes indexOfObject:node] + 1;
			while ( idx < wayA.nodes.count ) {
				[self addNodeUnsafe:wayA.nodes[idx] toWay:wayB atIndex:wayB.nodes.count];
				[self deleteNodeInWayUnsafe:wayA index:idx];
			}

		}

		// get a unique set of parent relations (de-duplicate)
		NSSet * relations = [NSSet setWithArray:wayA.parentRelations];

		// fix parent relations
		for ( OsmRelation * relation in relations ) {

			if (relation.isRestriction) {

				OsmMember 	* f = [relation memberByRole:@"from"];
				NSArray 	* v = [relation membersByRole:@"via"];
				OsmMember 	* t = [relation memberByRole:@"to"];

				if ( f.ref == wayA || t.ref == wayA ) {

					// 1. split a FROM/TO
					BOOL keepB = NO;
					for ( OsmMember * member in v ) {
						OsmBaseObject * via = member.ref;
						if ( ![via isKindOfClass:[OsmBaseObject class]] )
							continue;
						if ( via.isNode && [wayB.nodes containsObject:via] ) {
							keepB = YES;
							break;
						} else if ( via.isWay && [via.isWay connectsToWay:wayB] ) {
							keepB = YES;
							break;
						}
					}

					if ( keepB ) {
						// replace member(s) referencing A with B
						for ( NSInteger index = 0; index < relation.members.count; ++index ) {
							OsmMember * memberA = relation.members[index];
							if ( memberA.ref == wayA ) {
								OsmMember * memberB = [[OsmMember alloc] initWithRef:wayB role:memberA.role];
								[self addMemberUnsafe:memberB toRelation:relation atIndex:index+1];
								[self deleteMemberInRelationUnsafe:relation index:index];
							}
						}
					}

				} else {

					// 2. split a VIA
					OsmWay * prevWay = f.ref;
					for ( NSInteger index = 0; index < relation.members.count; index++ ) {
						OsmMember * memberA = relation.members[index];
						if ( [memberA.role isEqualToString:@"via"] ) {
							if ( memberA.ref == wayA ) {
								OsmMember * memberB = [[OsmMember alloc] initWithRef:wayB role:memberA.role];
								BOOL insertBefore = [prevWay isKindOfClass:[OsmWay class]] && [wayB connectsToWay:prevWay];
								[self addMemberUnsafe:memberB toRelation:relation atIndex:insertBefore?index:index+1];
								break;
							}
							prevWay = memberA.ref;
						}
					}
				}

			} else {

				// All other relations (Routes, Multipolygons, etc):
				// 1. Both `wayA` and `wayB` remain in the relation
				// 2. But must be inserted as a pair

				if ( relation == wayIsOuter ) {
					NSDictionary * merged = MergeTags(relation.tags, wayA.tags, YES);
					[self setTags:merged forObject:relation];
					[self setTags:nil forObject:wayA];
					[self setTags:nil forObject:wayB];
				}

				// if this is a route relation we want to add the new member in such a way that the route maintains a consecutive sequence of ways
				OsmWay * prevWay = nil;
				NSInteger index = 0;
				for ( OsmMember * member in relation.members ) {
					if ( member.ref == wayA ) {
						BOOL insertBefore = [prevWay isKindOfClass:[OsmWay class]] && [prevWay.isWay connectsToWay:wayB];
						OsmMember * newMember = [[OsmMember alloc] initWithRef:wayB role:member.role];
						[self addMemberUnsafe:newMember toRelation:relation atIndex:insertBefore?index:index+1];
						break;
					}
					prevWay = member.ref;
					++index;
				}
			}
		}

		return wayB;
	};
}


#pragma mark Turn-restriction relations

-(OsmRelation *)updateTurnRestrictionRelation:(OsmRelation *)restriction viaNode:(OsmNode *)viaNode
									  fromWay:(OsmWay *)fromWay
								  fromWayNode:(OsmNode *)fromWayNode
										toWay:(OsmWay *)toWay
									toWayNode:(OsmNode *)toWayNode
										 turn:(NSString *)strTurn
									  newWays:(NSArray **)resultWays
									willSplit:(BOOL(^)(NSArray * splitWays))requiresSplitting
{
	if ( ![fromWay.nodes containsObject:viaNode] ||
		 ![fromWay.nodes containsObject:fromWayNode] ||
		 ![toWay.nodes containsObject:viaNode] ||
		 ![toWay.nodes containsObject:toWayNode] ||
		 viaNode == fromWayNode ||
		 viaNode == toWayNode )
	{
		// error
		return nil;
	}

	// find ways that need to be split
	NSMutableArray * splits = [NSMutableArray new];
	NSArray * list = (fromWay == toWay) ? @[ fromWay ] : @[ fromWay, toWay ];
	for ( OsmWay * way in list ) {
		BOOL split = NO;
		if (way.isClosed) {
			split = YES;
		} else if ( way.nodes[0] != viaNode && way.nodes.lastObject != viaNode ) {
			split = YES;
		}
		if ( split ) {
			[splits addObject:way];
		}
	}
	if ( requiresSplitting && splits.count > 0 && !requiresSplitting(splits) )
		return nil;

	// get all necessary splits
	NSMutableArray * newWays = [NSMutableArray new];
	for ( OsmWay * way in splits ) {
		EditActionReturnWay split = [self canSplitWay:way atNode:viaNode];
		if ( split == nil )
			return nil;
		[newWays addObject:split];
	}

	[self registerUndoCommentString:NSLocalizedString(@"create turn restriction",nil)];

	for ( NSInteger i = 0; i < newWays.count; ++i ) {
		OsmWay 				* way = splits[i];
		EditActionReturnWay split = newWays[i];
		OsmWay * newWay = split();
		if ( way == fromWay && [newWay.nodes containsObject:fromWayNode] )
			fromWay = newWay;
		if ( way == toWay && [newWay.nodes containsObject:toWayNode] )
			toWay = newWay;
		newWays[i] = newWay;
	}

	if ( restriction == nil ) {
		restriction = [self createRelation];
	} else {
		while ( restriction.members.count > 0 ) {
			[self deleteMemberInRelationUnsafe:restriction index:0];
		}
	}
	
	NSMutableDictionary * tags = [NSMutableDictionary new];
	[tags setValue:@"restriction" forKey:@"type"];
	[tags setValue:strTurn forKey:@"restriction"];
	[self setTags:tags forObject:restriction];

	OsmMember * fromM = [[OsmMember alloc] initWithRef:fromWay role:@"from"];
	OsmMember * viaM = [[OsmMember alloc] initWithRef:viaNode role:@"via"];
	OsmMember * toM = [[OsmMember alloc] initWithRef:toWay role:@"to"];

	[self addMemberUnsafe:fromM toRelation:restriction atIndex:0];
	[self addMemberUnsafe:viaM toRelation:restriction atIndex:1];
	[self addMemberUnsafe:toM toRelation:restriction atIndex:2];

	if ( resultWays )
		*resultWays = newWays;
	
	return restriction;
}

#pragma mark joinWay

-(EditAction)canJoinWay:(OsmWay *)selectedWay atNode:(OsmNode *)selectedNode
{
	if ( selectedWay.nodes[0] != selectedNode && selectedWay.nodes.lastObject != selectedNode )
		return nil;	// must be endpoint node

	NSArray * ways = [self waysContainingNode:selectedNode];
	OsmWay * otherWay = nil;
	for ( OsmWay * way in ways ) {
		if ( way == selectedWay )
			continue;
		if ( way.nodes[0] == selectedNode || way.nodes.lastObject == selectedNode ) {
			if ( otherWay ) {
				// ambigious connection
				return nil;
			}
			otherWay = way;
		}
	}
	if ( otherWay == nil )
		return nil;

	NSMutableSet * relations = [NSMutableSet setWithArray:selectedWay.parentRelations];
	[relations intersectSet:[NSSet setWithArray:otherWay.parentRelations]];
	for ( OsmRelation * relation in relations ) {
		// both belong to relation
		if ( relation.isRestriction ) {
			// joining is only okay if both belong to via
			NSArray * viaList = [relation membersByRole:@"via"];
			int foundSet = 0;
			for ( OsmMember * member in viaList ) {
				if ( member.ref == selectedWay )
					foundSet |= 1;
				if ( member.ref == otherWay )
					foundSet |= 2;
			}
			if ( foundSet != 3 )
				return nil;
		}
		// route or polygon, so should be okay
	}

	//
	NSDictionary * newTags = MergeTags(selectedWay.tags, otherWay.tags, NO);
	if ( newTags == nil ) {
		// tag conflict
		return nil;
	}

	return ^{

		// join nodes, preserving selected way
		NSInteger index = 0;
		if ( selectedWay.nodes.lastObject == otherWay.nodes[0] ) {
			[self registerUndoCommentString:NSLocalizedString(@"Join",nil)];
			for ( OsmNode * n in otherWay.nodes ) {
				if ( index++ == 0 )
					continue;
				[self addNodeUnsafe:n toWay:selectedWay atIndex:selectedWay.nodes.count];
			}
		} else if ( selectedWay.nodes.lastObject == otherWay.nodes.lastObject ) {
			[self registerUndoCommentString:NSLocalizedString(@"Join",nil)];
			EditAction reverse = [self canReverseWay:otherWay];	// reverse the tags on other way
			reverse();
			for ( OsmNode * n in otherWay.nodes ) {
				if ( index++ == 0 )
					continue;
				[self addNodeUnsafe:n toWay:selectedWay atIndex:selectedWay.nodes.count];
			}
		} else if ( selectedWay.nodes[0] == otherWay.nodes[0] ) {
			[self registerUndoCommentString:NSLocalizedString(@"Join",nil)];
			EditAction reverse = [self canReverseWay:otherWay];	// reverse the tags on other way
			reverse();
			for ( OsmNode * n in [[otherWay.nodes reverseObjectEnumerator] allObjects] ) {
				if ( index++ == 0 )
					continue;
				[self addNodeUnsafe:n toWay:selectedWay atIndex:0];
			}
		} else if ( selectedWay.nodes[0] == otherWay.nodes.lastObject ) {
			[self registerUndoCommentString:NSLocalizedString(@"Join",nil)];
			for ( OsmNode * n in [[otherWay.nodes reverseObjectEnumerator] allObjects] ) {
				if ( index++ == 0 )
					continue;
				[self addNodeUnsafe:n toWay:selectedWay atIndex:0];
			}
		} else {
			DbgAssert(NO);
			return;	// never happens
		}

		// join tags
		[self setTags:newTags forObject:selectedWay];

		[self deleteWayUnsafe:otherWay];
	};
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
	[mapData addNodeUnsafe:newNode toWay:way atIndex:index];
}

-(EditAction)canCircularizeWay:(OsmWay *)way
{
	if ( !way.isWay )
		return nil;
	if ( !way.isClosed )
		return nil;
	if ( way.nodes.count < 4 )
		return nil;

	return ^{
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
	};
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
		[self addNodeUnsafe:newNode toWay:newWay atIndex:index++];
	}
	[self setTags:way.tags forObject:newWay];
	return newWay;
}

- (OsmBaseObject *)duplicateObject:(OsmBaseObject *)object
{
	if ( object.isNode ) {
		[self registerUndoCommentString:NSLocalizedString(@"duplicate",nil)];
		return [self duplicateNode:object.isNode];
	} else if ( object.isWay ) {
		[self registerUndoCommentString:NSLocalizedString(@"duplicate",nil)];
		return [self duplicateWay:object.isWay];
	} else if ( object.isRelation.isMultipolygon ) {
		[self registerUndoCommentString:NSLocalizedString(@"duplicate",nil)];
		OsmRelation * newRelation = [self createRelation];
		for ( OsmMember * member in object.isRelation.members ) {
			OsmWay * way = member.ref;
			if ( [way isKindOfClass:[OsmWay class]] ) {
				OsmWay * newWay = nil;
				for ( NSInteger prev = 0; prev < newRelation.members.count; ++prev ) {
					OsmMember * m = object.isRelation.members[prev];
					if ( m.ref == way ) {
						// way is duplicated
						newWay = ((OsmMember *)newRelation.members[prev]).ref;
						break;
					}
				}
				if ( newWay == nil )
					newWay = [self duplicateWay:way];
				OsmMember * newMember = [[OsmMember alloc] initWithType:member.type ref:(NSNumber *)newWay role:member.role];
				[newRelation addMember:newMember atIndex:newRelation.members.count undo:_undoManager];
			}
		}
		[self setTags:object.tags forObject:newRelation];
		return newRelation;
	}
	return nil;
}

#pragma mark Rectangularize

static double rectoThreshold;
static double rectoLowerThreshold;
static double rectoUpperThreshold;

static double filterDotProduct(double dotp)
{
	if (rectoLowerThreshold > fabs(dotp) || fabs(dotp) > rectoUpperThreshold) {
		return dotp;
	}
	return 0;
}

static double normalizedDotProduct(NSInteger i, const OSMPoint points[], NSInteger count)
{
	OSMPoint a = points[(i - 1 + count) % count];
	OSMPoint b = points[i];
	OSMPoint c = points[(i + 1) % count];
	OSMPoint p = Sub(a, b);
	OSMPoint q = Sub(c, b);

	p = UnitVector(p);
	q = UnitVector(q);

	return Dot(p,q);
}

static double squareness(const OSMPoint points[], NSInteger count)
{
	double sum = 0.0;
	for ( NSInteger i = 0; i < count; ++i ) {
		double dotp = normalizedDotProduct(i, points,count);
		dotp = filterDotProduct(dotp);
		sum += 2.0 * MIN(fabs(dotp - 1.0), MIN(fabs(dotp), fabs(dotp + 1)));
	}
	return sum;
}


static OSMPoint calcMotion(OSMPoint b, NSInteger i, OSMPoint array[], NSInteger count, NSInteger * pCorner, double * pDotp )
{
	OSMPoint a = array[(i - 1 + count) % count];
	OSMPoint c = array[(i + 1) % count];
	OSMPoint p = Sub(a, b);
	OSMPoint q = Sub(c, b);

	OSMPoint origin = {0,0};
	double scale = 2 * MIN(DistanceFromPointToPoint(p, origin), DistanceFromPointToPoint(q, origin));
	p = UnitVector(p);
	q = UnitVector(q);

	if ( isnan(p.x) || isnan(q.x) ) {
		if ( pDotp )
			*pDotp = 1.0;
		return OSMPointMake(0, 0);
	}

	double dotp = filterDotProduct( Dot(p,q) );

	// nasty hack to deal with almost-straight segments (angle is closer to 180 than to 90/270).
	if (count > 3) {
		if (dotp < -0.707106781186547) {
			dotp += 1.0;
		}
	} else {
		// for triangles save the best corner
		if (dotp && pDotp && fabs(dotp) < *pDotp) {
			*pCorner = i;
			*pDotp = fabs( dotp );
		}
	}

	OSMPoint r = UnitVector( Add(p,q) );
	r = Mult( r, 0.1 * dotp * scale );
	return r;
}

-(EditAction)canOrthogonalizeWay:(OsmWay *)way
{
	// needs a closed way to work properly.
	if ( !way.isWay || !way.isClosed || way.nodes.count < 3 ) {
		return nil;
	}


#if 0
	if ( squareness(points,count) == 0.0 ) {
		// already square
		return NO;
	}
#endif

	return ^{
		[self registerUndoCommentString:NSLocalizedString(@"Make Rectangular",nil)];

		rectoThreshold = 12; // degrees within right or straight to alter
		rectoLowerThreshold = cos((90 - rectoThreshold) * M_PI / 180);
		rectoUpperThreshold = cos(rectoThreshold * M_PI / 180);

		NSInteger count = way.nodes.count-1;
		OSMPoint points[ count ];
		for ( NSInteger i = 0; i < count; ++i ) {
			OsmNode * node = way.nodes[i];
			points[i].x = node.lon;
			points[i].y = lat2latp(node.lat);
		}

		double epsilon = 1e-4;

		if (count == 3) {

			double score = 0.0;
			NSInteger corner = 0;
			double dotp = 1.0;

			for ( NSInteger step = 0; step < 1000; step++) {
				OSMPoint motions[ count ];
				for ( NSInteger i = 0; i < count; ++i ) {
					motions[i] = calcMotion(points[i],i,points,count,&corner,&dotp);
				}
				points[corner] = Add( points[corner],motions[corner] );
				score = dotp;
				if (score < epsilon) {
					break;
				}
			}

			// apply new position
			OsmNode * node = way.nodes[corner];
			[self setLongitude:points[corner].x latitude:latp2lat(points[corner].y) forNode:node inWay:way];

		} else {

			OSMPoint best[count];
			OSMPoint originalPoints[count];
			memcpy( originalPoints, points, sizeof points);
			double score = 1e9;

			for ( NSInteger step = 0; step < 1000; step++) {
				OSMPoint motions[ count ];
				for ( NSInteger i = 0; i < count; ++i ) {
					motions[i] = calcMotion(points[i],i,points,count,NULL,NULL);
					//				NSLog(@"motion[%ld] = %f,%f", i, motions[i].x, motions[i].y );
				}
				for ( NSInteger i = 0; i < count; i++) {
					points[i] = Add( points[i], motions[i] );
					//				NSLog(@"points[%ld] = %f,%f", i, points[i].x, points[i].y );
				}
				double newScore = squareness(points,count);
				if (newScore < score) {
					memcpy( best, points, sizeof points);
					score = newScore;
				}
				if (score < epsilon) {
					break;
				}
			}

			memcpy(points,best,sizeof points);

			for ( NSInteger i = 0; i < way.nodes.count; ++i ) {
				NSInteger modi = i < count ? i : 0;
				OsmNode * node = way.nodes[i];
				if ( points[i].x != originalPoints[i].x || points[i].y != originalPoints[i].y ) {
					[self setLongitude:points[modi].x latitude:latp2lat(points[modi].y) forNode:node inWay:way];
				}
			}

			// remove empty nodes on straight sections
			// * deleting nodes that are referenced by non-downloaded ways could case data loss
			for (NSInteger i = count-1; i >= 0; i--) {
				OsmNode * node = way.nodes[i];

				if ( node.wayCount > 1 ||
					node.parentRelations.count > 0 ||
					node.hasInterestingTags)
				{
					continue;
				}

				double dotp = normalizedDotProduct(i, points, count);
				if (dotp < -1 + epsilon) {
					EditAction canDeleteNode = [self canDeleteNode:node fromWay:way];
					if ( canDeleteNode ) {
						canDeleteNode();
					}
				}
			}
		}
	};
}

@end
