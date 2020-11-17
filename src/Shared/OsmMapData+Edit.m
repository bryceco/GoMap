//
//  OsmMapData+Edit.m
//  Go Map!!
//
//  Created by Bryce Cogswell on 7/9/14.
//  Copyright (c) 2014 Bryce Cogswell. All rights reserved.
//

#import "DLog.h"
#import "OsmMapData.h"
#import "OsmMapData+Edit.h"
#import "OsmMember.h"
#import "UndoManager.h"
#import "VectorMath.h"



@interface OsmMapData ()
// private methods in main file
-(void)addNodeUnsafe:(OsmNode *)node toWay:(OsmWay *)way atIndex:(NSInteger)index;
-(void)deleteNodeInWayUnsafe:(OsmWay *)way index:(NSInteger)index preserveNode:(BOOL)preserveNode;
-(void)deleteNodeUnsafe:(OsmNode *)node;
-(void)deleteWayUnsafe:(OsmWay *)way;
-(void)deleteRelationUnsafe:(OsmRelation *)relation;
-(void)addMemberUnsafe:(OsmMember *)member toRelation:(OsmRelation *)relation atIndex:(NSInteger)index;
-(void)deleteMemberInRelationUnsafe:(OsmRelation *)relation index:(NSInteger)index;
-(void)updateMembersUnsafe:(NSArray *)memberList inRelation:(OsmRelation *)relation;
@end


@implementation OsmMapData (Edit)

#pragma mark canDeleteNode

// Only for solitary nodes. Otherwise use delete node in way.
-(EditAction)canDeleteNode:(OsmNode *)node error:(NSString **)error
{
	if ( node.wayCount > 0 || node.parentRelations.count > 0 ) {
		*error = NSLocalizedString(@"Can't delete node that is part of a relation", nil);
		return nil;
	}
	return ^{
		[self deleteNodeUnsafe:node];
	};
}

#pragma mark canDeleteWay

-(EditAction)canDeleteWay:(OsmWay *)way error:(NSString **)error
{
	if ( way.parentRelations.count > 0 ) {
		BOOL ok = NO;
		if ( way.parentRelations.count == 1 ) {
			OsmRelation * relation = way.parentRelations.lastObject;
			if ( relation.isMultipolygon ) {
				ok = YES;
			} else if ( relation.isRestriction ) {
				// allow deleting if we're both from and to (u-turn)
				OsmMember * from = [relation memberByRole:@"from"];
				OsmMember * to   = [relation memberByRole:@"to"];
				if ( from.ref == way && to.ref == way ) {
					return ^{
						[self deleteRelationUnsafe:relation];
						[self deleteWayUnsafe:way];
					};
				}
			}
		}
		if ( !ok ) {
			*error = NSLocalizedString(@"Can't delete way that is part of a Route or similar relation", nil);
			return nil;
		}
	}

	return ^{
		[self deleteWayUnsafe:way];
	};
}

#pragma mark canDeleteRelation

-(EditAction)canDeleteRelation:(OsmRelation *)relation error:(NSString **)error
{
	if ( relation.isMultipolygon ) {
		// okay
	} else if ( relation.isRestriction ) {
		// okay
	} else {
		*error = NSLocalizedString(@"Can't delete relation that is not a multipolygon", nil);
		return nil;
	}

	return ^{
		[self deleteRelationUnsafe:relation];
	};
}

#pragma mark canAddNodeToWay

-(EditActionWithNode)canAddNodeToWay:(OsmWay *)way atIndex:(NSInteger)index error:(NSString **)error
{
	if ( way.nodes.count >= 2 && (index == 0 || index == way.nodes.count) ) {
		// we don't want to extend a way that is a portion of a route relation, polygon, etc.
		for ( OsmRelation * relation in way.parentRelations ) {
			if ( relation.isRestriction ) {
				// only permissible if extending from/to on the end away from the via node/ways
				NSArray * viaList = [relation membersByRole:@"via"];
				OsmNode * prevNode = index ? way.nodes.lastObject : way.nodes[0];
				// disallow extending any via way, or any way touching via node
				for ( OsmMember * viaMember in viaList ) {
					OsmBaseObject * via = viaMember.ref;
					if ( [via isKindOfClass:[OsmBaseObject class]] ) {
						if ( via.isWay && (via == way || [via.isWay.nodes containsObject:prevNode]) ) {
							*error = NSLocalizedString(@"Extending a 'via' in a Turn Restriction will break the relation", nil);
							return nil;
						}
					} else {
						*error = NSLocalizedString(@"The way belongs to a relation that is not fully downloaded", nil);
						return nil;
					}
				}
			} else {
				*error = NSLocalizedString(@"Extending a way which belongs to a Route or similar relation may damage the relation", nil);
				return nil;
			}
		}
	}
	if ( way.nodes.count == 2000 ) {
		*error = NSLocalizedString(@"Maximum way length is 2000 nodes", nil);
		return nil;
	}

	return ^(OsmNode * node) {
		[self addNodeUnsafe:node toWay:way atIndex:index];
	};
}

#pragma mark updateMultipolygonRelationRoles

-(void)updateMultipolygonRelationRoles:(OsmRelation *)relation
{
	if ( !relation.isMultipolygon )
		return;

	BOOL				isComplete = NO;
	NSMutableArray	* members	= [relation.members mutableCopy];
	NSArray		 	* loopList 	= [OsmRelation buildMultipolygonFromMembers:members repairing:NO isComplete:&isComplete];

	if ( !isComplete )
		return;

	NSMutableSet   	* innerSet 	= [NSMutableSet new];
	for ( NSArray * loop in loopList ) {
		OSMPoint refPoint;
		CGPathRef path = [OsmWay shapePathForNodes:loop forward:YES withRefPoint:&refPoint];
		if ( path == NULL )
			continue;
		for ( NSInteger m = 0; m < members.count; ++m ) {
			OsmMember * member = members[m];
			OsmWay * way = member.ref;
			if ( ![way isKindOfClass:[OsmWay class]] || way.nodes.count == 0 )
				continue;
			OsmNode * node = way.nodes.lastObject;
			if ( [loop containsObject:node] ) {
				// This way is part of the loop being checked against
				continue;
			}
			extern const double PATH_SCALING;
			OSMPoint pt = MapPointForLatitudeLongitude( node.lat, node.lon );
			pt = Sub( pt, refPoint );
			pt = Mult( pt, PATH_SCALING );
			BOOL isInner = CGPathContainsPoint(path, NULL, CGPointFromOSMPoint(pt), NO);
			if ( isInner ) {
				[innerSet addObject:member];
			}
		}
		CGPathRelease(path);
	}
	// update roles if necessary
	BOOL changed = NO;
	for ( NSInteger m = 0; m < members.count; ++m ) {
		OsmMember * member = members[m];
		if ( ![member.ref isKindOfClass:[OsmWay class]] ) {
			continue;
		}
		if ( [innerSet containsObject:member] ) {
			if ( ![member.role isEqualToString:@"inner"] ) {
				members[m] = [[OsmMember alloc] initWithRef:member.ref role:@"inner"];
				changed = YES;
			}
		} else {
			if ( ![member.role isEqualToString:@"outer"] ) {
				members[m] = [[OsmMember alloc] initWithRef:member.ref role:@"outer"];
				changed = YES;
			}
		}
	}
	if ( changed ) {
		[self updateMembersUnsafe:members inRelation:relation];
	}
}

-(void)updateParentMultipolygonRelationRolesForWay:(OsmWay *)way
{
	for ( OsmRelation * relation in way.parentRelations ) {
		// might have moved an inner outside a multipolygon
		[self updateMultipolygonRelationRoles:relation];
	}
}

#pragma mark canAddWayToRelation

-(EditAction)canAddObject:(OsmBaseObject *)obj toRelation:(OsmRelation *)relation withRole:(NSString *)role error:(NSString **)error
{
	if ( !relation.isMultipolygon ) {
		*error = NSLocalizedString(@"Only multipolygon relations are supported", nil);
		return nil;
	}
	OsmWay * newWay = obj.isWay;
	if ( !newWay ) {
		*error = NSLocalizedString(@"Can only add ways to multipolygons", nil);
		return nil;
	}

	// place the member adjacent to a way its connected to, if any
	NSInteger index = 0;
	for ( OsmMember * m in relation.members ) {
		OsmWay * w = m.ref;
		++index;
		if ( ![w isKindOfClass:[OsmWay class]] )
			continue;
		if ( ![m.role isEqualToString:@"inner"] && ![m.role isEqualToString:@"outer"] )
			continue;
		if ( [newWay connectsToWay:w] ) {
			if ( role && ![role isEqualToString:m.role] ) {
				*error = NSLocalizedString(@"Cannot connect an inner way to an outer way", nil);
				return nil;
			}
			role = m.role;	// copy the role of the way it's connected to
			break;
		}
	}
	if ( role == nil ) {
		*error = NSLocalizedString(@"Unknown role", nil);
		return nil;
	}

	return ^{
		OsmMember * newMember = [[OsmMember alloc] initWithRef:newWay role:role];
		[self addMemberUnsafe:newMember toRelation:relation atIndex:index];
	};
}

#pragma mark canRemoveObject:fromRelation

-(EditAction)canRemoveObject:(OsmBaseObject *)obj fromRelation:(OsmRelation *)relation error:(NSString **)error
{
	if ( !relation.isMultipolygon ) {
		*error = NSLocalizedString(@"Only multipolygon relations are supported", nil);
		return nil;
	}
	return ^{
		for ( NSInteger index = 0; index < relation.members.count; ++index ) {
			OsmMember * member = relation.members[index];
			if ( member.ref == obj ) {
				[self deleteMemberInRelationUnsafe:relation index:index];
				--index;
			}
		}
	};
}

#pragma mark canMergeNode:intoNode

// used when dragging a node into another node
-(EditActionReturnNode)canMergeNode:(OsmNode *)node1 intoNode:(OsmNode *)node2 error:(NSString **)error
{
	NSDictionary * mergedTags = MergeTags(node1.tags, node2.tags, NO );
	if ( mergedTags == nil ) {
		*error = NSLocalizedString(@"The merged nodes contain conflicting tags", nil);
		return nil;
	}

	OsmNode * survivor;
	if ( node1.ident.longLongValue < 0 ) {
		survivor = node2;
	} else if ( node2.ident.longLongValue < 0 ) {
		survivor = node1;
	} else if ( node1.wayCount > node2.wayCount ) {
		survivor = node1;
	} else {
		survivor = node2;
	}
	OsmNode * deadNode = (survivor == node1) ? node2 : node1;

	// if the nodes have different relation roles they can't merge

	// 1. disable if the nodes being connected have conflicting relation roles
	NSArray * nodes = @[ survivor, deadNode ];
	NSMutableSet * restrictions = [NSMutableSet new];
	NSMutableDictionary * seen = [NSMutableDictionary new];
	for ( OsmNode * node in nodes ) {
		NSArray * relations = node.parentRelations;
		for ( OsmRelation * relation in relations ) {
			OsmMember * member = [relation memberByRef:node];
			NSString * role = member.role;

			// if this node is a via node in a restriction, remember for later
			if ( relation.isRestriction ) {
				[restrictions addObject:relation];
			}

			NSString * prevRole = seen[relation.ident];
			if (prevRole && ![prevRole isEqualToString:role] ) {
				*error = NSLocalizedString(@"The nodes have conflicting roles in parent relations", nil);
				return nil;
			} else {
				seen[relation.ident] = role;
			}
		}
	}

	// gather restrictions for parent ways
	for ( OsmNode * node in nodes ) {
		NSArray<OsmWay *> * parents = [self waysContainingNode:node];
		for ( OsmWay * parent in parents ) {
			for ( OsmRelation * relation in parent.parentRelations ) {
				if ( relation.isRestriction ) {
					[restrictions addObject:relation];
				}
			}
		}
	}

	// test restrictions
	for ( OsmRelation * relation in restrictions ) {

		NSMutableSet * memberWays = [NSMutableSet new];
		for ( OsmMember * member in relation.members ) {
			if ( member.isWay ) {
				if ( ![member.ref isKindOfClass:[OsmWay class]] ) {
					*error = NSLocalizedString(@"A relation the node belongs to is not fully downloaded",nil);
					return nil;
				}
				[memberWays addObject:member.ref];
			}
		}

		OsmMember * f = [relation memberByRole:@"from"];
		OsmMember * t = [relation memberByRole:@"to"];
		BOOL isUturn = (f.ref == t.ref);

		// 2a. disable if connection would damage a restriction (a key node is a node at the junction of ways)
		NSDictionary * collection = @{
									  @"from" : [NSMutableSet new],
									  @"via" : [NSMutableSet new],
									  @"to" : [NSMutableSet new]
									  };
		NSMutableSet * keyfrom 	= [NSMutableSet new];
		NSMutableSet * keyto 	= [NSMutableSet new];
		for ( OsmMember * member in relation.members ) {

			NSString * role = member.role;

			if (member.isNode ) {

				[collection[role] addObject:member];

				if ( [role isEqualToString:@"via"] ) {
					[keyfrom addObject:member];
					[keyto   addObject:member];
				}

			} else if ( member.isWay ) {

				OsmWay * way = member.ref;
				if ( ![way isKindOfClass:[OsmBaseObject class]] ) {
					*error = NSLocalizedString(@"A relation the node belongs to is not fully downloaded",nil);
					return nil;
				}
				[collection[role] addObjectsFromArray:way.nodes];

				if ( [role isEqualToString:@"from"] || [role isEqualToString:@"via"] ) {
					[keyfrom addObject:way.nodes[0]];
					[keyfrom addObject:way.nodes.lastObject];
				}
				if ( [role isEqualToString:@"to"] || [role isEqualToString:@"via"] ) {
					[keyto addObject:way.nodes[0]];
					[keyto addObject:way.nodes.lastObject];
				}
			}
		}

		NSPredicate * filter = [NSPredicate predicateWithBlock:^BOOL(OsmNode * node, id bindings) {
			return ![keyfrom containsObject:node] && ![keyto containsObject:node];
		}];
		NSArray * from = [[collection[@"from"] allObjects] filteredArrayUsingPredicate:filter];
		NSArray * to   = [[collection[@"to"]   allObjects] filteredArrayUsingPredicate:filter];
		NSArray * via  = [[collection[@"via"]  allObjects] filteredArrayUsingPredicate:filter];

		BOOL connectFrom = false;
		BOOL connectVia = false;
		BOOL connectTo = false;
		BOOL connectKeyFrom = false;
		BOOL connectKeyTo = false;

		for ( OsmNode * n in nodes ) {
			if ( [from containsObject:n] ) 		 { connectFrom = true; }
			if ( [via containsObject:n]	)	     { connectVia = true; }
			if ( [to containsObject:n] )		 { connectTo = true; }
			if ( [keyfrom containsObject:n] )	 { connectKeyFrom = true; }
			if ( [keyto containsObject:n] )		 { connectKeyTo = true; }
		}
		if ( (connectFrom && connectTo && !isUturn) ||
			 (connectFrom && connectVia) ||
			 (connectTo   && connectVia) )
		{
			*error = NSLocalizedString(@"Connecting the nodes would damage a relation",nil);
			return nil;
		}

		// connecting to a key node -
		// if both nodes are on a member way (i.e. part of the turn restriction),
		// the connecting node must be adjacent to the key node.
		if ( connectKeyFrom || connectKeyTo ) {

			OsmNode * n0 = nil;
			OsmNode * n1 = nil;
			for ( OsmWay * way in memberWays ) {
				if ( [way.nodes containsObject:nodes[0]] ) { n0 = nodes[0]; }
				if ( [way.nodes containsObject:nodes[1]] ) { n1 = nodes[1]; }
			}

			if ( n0 && n1 ) {    // both nodes are part of the restriction
				*error = NSLocalizedString(@"Connecting the nodes would damage a relation",nil);
				return nil;
			}
		}
	}

	return ^{
		if ( survivor == node1 ) {
			// update survivor to have location of other node
			[self setLongitude:node2.lon latitude:node2.lat forNode:survivor];
		}

		[self setTags:mergedTags forObject:survivor];

		// need to replace the node in all objects everywhere
		[_ways enumerateKeysAndObjectsUsingBlock:^(NSNumber * ident, OsmWay * way, BOOL * _Nonnull stop) {
			if ( [way.nodes containsObject:deadNode] ) {
				for ( NSInteger index = 0; index < way.nodes.count; ++index ) {
					if ( way.nodes[index] == deadNode ) {
						[self addNodeUnsafe:survivor toWay:way atIndex:index];
						[self deleteNodeInWayUnsafe:way index:index+1 preserveNode:NO];
					}
				}
			}
		}];
		[_relations enumerateKeysAndObjectsUsingBlock:^(NSNumber * ident, OsmRelation * relation, BOOL * _Nonnull stop) {
			for ( NSInteger index = 0; index < relation.members.count; ++index ) {
				OsmMember * member = relation.members[index];
				if ( member.ref == deadNode ) {
					OsmMember * newMember = [[OsmMember alloc] initWithRef:survivor role:member.role];
					[self addMemberUnsafe:newMember toRelation:relation atIndex:index+1];
					[self deleteMemberInRelationUnsafe:relation index:index];
				}
			}
		}];

		[self deleteNodeUnsafe:deadNode];
		return survivor;
	};
}

#pragma mark straightenWay

static double positionAlongWay( OSMPoint node, OSMPoint start, OSMPoint end )
{
	return ((node.x - start.x) * (end.x - start.x) + (node.y - start.y) * (end.y - start.y)) / MagSquared(Sub(end,start));
}

- (EditAction)canStraightenWay:(OsmWay *)way error:(NSString **)error
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
		if ( dist > threshold ) {
			*error = NSLocalizedString(@"The way is not sufficiently straight", nil);
			return nil;
		}

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
				NSString * dummy = nil;
				EditAction canDelete = [self canDeleteNode:node fromWay:way error:&dummy];
				if ( canDelete ) {
					canDelete();
				} else {
					// no big deal
				}
			} else {
				OsmNode * node = way.nodes[i];
				OSMPoint pt = point.point;
				[self setLongitude:pt.x latitude:latp2lat(pt.y) forNode:node];
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


- (EditAction)canReverseWay:(OsmWay *)way error:(NSString **)error
{
	NSDictionary * roleReversals = @{
		@"forward" : @"backward",
		@"backward" : @"forward",
		@"north" : @"south",
		@"south" : @"north",
		@"east" : @"west",
		@"west" : @"east"
	};
	NSDictionary * nodeReversals = @{
		@"forward" : @"backward",
		@"backward" : @"forward",
	};

	return ^{
		[self registerUndoCommentString:NSLocalizedString(@"Reverse",nil)];

		// reverse nodes
		NSArray * newNodes = [[way.nodes reverseObjectEnumerator] allObjects];
		for ( NSInteger i = 0; i < newNodes.count; ++i ) {
			[self addNodeUnsafe:newNodes[i] toWay:way atIndex:i];
		}
		while ( way.nodes.count > newNodes.count ) {
			[self deleteNodeInWayUnsafe:way index:way.nodes.count-1 preserveNode:NO];
		}

		// reverse tags on way
		__block NSMutableDictionary * newWayTags = [NSMutableDictionary new];
		[way.tags enumerateKeysAndObjectsUsingBlock:^(NSString * k, NSString * v, BOOL *stop) {
			k = reverseKey(k);
			v = reverseValue(k, v);
			[newWayTags setObject:v forKey:k];
		}];
		[self setTags:newWayTags forObject:way];

		// reverse direction tags on nodes in way
		for ( OsmNode * node in way.nodes ) {
			NSString * value = node.tags[@"direction"];
			NSString * replacement = nodeReversals[ value ];
			if ( replacement ) {
				NSMutableDictionary * nodeTags = [node.tags mutableCopy];
				nodeTags[ @"direction" ] = replacement;
				[self setTags:nodeTags forObject:node];
			}
		}

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

-(BOOL)canDisconnectOrDeleteNode:(OsmNode *)node inWay:(OsmWay *)way isDelete:(BOOL)isDelete error:(NSString **)error
{
	// only care if node is an endpoiont
	if ( node == way.nodes[0] || node == way.nodes.lastObject ) {

		// we don't want to truncate a way that is a portion of a route relation, polygon, etc.
		for ( OsmRelation * relation in way.parentRelations ) {
			if ( relation.isRestriction ) {
				for ( OsmMember * member in relation.members ) {
					if ( ! [member.ref isKindOfClass:[OsmBaseObject class]] ) {
						*error = NSLocalizedString(@"The way belongs to a relation this not fully downloaded", nil);
						return NO;
					}
				}

				// only permissible if deleting interior node of via, or non-via node in from/to
				NSArray * viaList = [relation membersByRole:@"via"];
				OsmMember * from = [relation memberByRole:@"from"];
				OsmMember * to   = [relation memberByRole:@"to"];
				if ( from.ref == way || to.ref == way ) {
					if ( isDelete && way.nodes.count <= 2 ) {
						*error = NSLocalizedString(@"Can't remove Turn Restriction to/from way", nil);
						return NO;	// deleting node will cause degenerate way
					}
					for ( OsmMember * viaMember in viaList ) {
						if ( viaMember.ref == node ) {
							*error = NSLocalizedString(@"Can't remove Turn Restriction 'via' node", nil);
							return NO;
						} else {
							OsmBaseObject * viaObject = viaMember.ref;
							if ( [viaObject isKindOfClass:[OsmBaseObject class]] ) {
								OsmNode * common = [viaObject.isWay connectsToWay:way];
								if ( common.isNode == node ) {
									// deleting the node that connects from/to and via
									*error = NSLocalizedString(@"Can't remove Turn Restriction node connecting 'to'/'from' to 'via'", nil);
									return NO;
								}
							}
						}
					}
				}

				// disallow deleting an endpoint of any via way, or a via node itself
				for ( OsmMember * viaMember in viaList ) {
					if ( viaMember.ref == way ) {
						// can't delete an endpoint of a via way
						*error = NSLocalizedString(@"Can't remove node in Turn Restriction 'via' way", nil);
						return NO;
					}
				}
			} else if ( relation.isMultipolygon ) {
				// okay
			} else {
				// don't allow deleting an endpoint node of routes, etc.
				*error = NSLocalizedString(@"Can't remove component of a Route or similar relation", nil);
				return NO;
			}
		}
	}
	return YES;
}


-(EditAction)canDeleteNode:(OsmNode *)node fromWay:(OsmWay *)way error:(NSString **)error
{
	if ( ![self canDisconnectOrDeleteNode:node inWay:way isDelete:YES error:error] )
		return nil;

	return ^{
		BOOL needAreaFixup = way.nodes.lastObject == node  &&  way.nodes[0] == node;
		for ( NSInteger index = 0; index < way.nodes.count; ++index ) {
			if ( way.nodes[index] == node ) {
				[self deleteNodeInWayUnsafe:way index:index preserveNode:NO];
				--index;
			}
		}
		if ( way.nodes.count < 2 ) {
			NSString * dummy = nil;
			EditAction delete = [self canDeleteWay:way error:&dummy];
			if ( delete ) {
				delete();	// this will also delete any relations the way belongs to
			} else {
				[self deleteWayUnsafe:way];
			}
		} else if ( needAreaFixup ) {
			// special case where deleted node is first & last node of an area
			[self addNodeUnsafe:way.nodes[0] toWay:way atIndex:way.nodes.count];
		}
		[self updateParentMultipolygonRelationRolesForWay:way];
	};
}

#pragma mark disconnectWayAtNode

// disconnect all other ways from the selected way joined to it at node
- (EditActionReturnNode)canDisconnectWay:(OsmWay *)way atNode:(OsmNode *)node error:(NSString **)error
{
	if ( ![way.nodes containsObject:node] ) {
		*error = NSLocalizedString(@"Node is not an element of way", nil);
		return nil;
	}
	if ( node.wayCount < 2 ) {
		*error = NSLocalizedString(@"The way must have at least 2 nodes", nil);
		return nil;
	}

	if ( ![self canDisconnectOrDeleteNode:node inWay:way isDelete:NO error:error] )
		return nil;

	return ^{
		[self registerUndoCommentString:NSLocalizedString(@"Disconnect",nil)];

		CLLocationCoordinate2D loc = { node.lat, node.lon };
		OsmNode * newNode = [self createNodeAtLocation:loc];
		[self setTags:node.tags forObject:newNode];

		NSInteger index;
		while ( (index = [way.nodes indexOfObject:node]) != NSNotFound ) {
			[self addNodeUnsafe:newNode toWay:way atIndex:index+1];
			[self deleteNodeInWayUnsafe:way index:index preserveNode:NO];
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


-(EditActionReturnWay)canSplitWay:(OsmWay *)selectedWay atNode:(OsmNode *)node error:(NSString **)error
{
	return ^{
		[self registerUndoCommentString:NSLocalizedString(@"Split",nil)];

		OsmWay * wayA = selectedWay;
		OsmWay * wayB = [self createWay];

		[self setTags:wayA.tags forObject:wayB];

		OsmRelation * wayIsOuter = wayA.isSimpleMultipolygonOuterMember ? wayA.parentRelations.lastObject : nil;	// only 1 parent relation if it is simple

		if (wayA.isClosed) {

			// remove duplicated node
			[self deleteNodeInWayUnsafe:wayA index:wayA.nodes.count-1 preserveNode:NO];

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
				[self deleteNodeInWayUnsafe:wayA index:i preserveNode:NO];
			}

			// rebase A so it starts with selected node
			while ( wayA.nodes[0] != node ) {
				[self addNodeUnsafe:wayA.nodes[0] toWay:wayA atIndex:wayA.nodes.count];
				[self deleteNodeInWayUnsafe:wayA index:0 preserveNode:NO];
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
				[self deleteNodeInWayUnsafe:wayA index:idx preserveNode:NO];
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
						if ( via.isNode && [wayB.nodes containsObject:via.isNode] ) {
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
		NSString * error;
		EditActionReturnWay split = [self canSplitWay:way atNode:viaNode error:&error];
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

-(EditAction)canJoinWay:(OsmWay *)selectedWay atNode:(OsmNode *)selectedNode error:(NSString **)error
{
	if ( selectedWay.nodes[0] != selectedNode && selectedWay.nodes.lastObject != selectedNode ) {
		*error = NSLocalizedString(@"Node must first or last node of the way",nil);
		return nil;	// must be endpoint node
	}

	NSArray<OsmWay *> * ways = [self waysContainingNode:selectedNode];
	NSMutableArray * otherWays = [NSMutableArray new];
	NSMutableArray * otherMatchingTags = [NSMutableArray new];
	for ( OsmWay * way in ways ) {
		if ( way == selectedWay )
			continue;
		if ( way.nodes[0] == selectedNode || way.nodes.lastObject == selectedNode ) {
			if ( [way.tags isEqualToDictionary:selectedWay.tags] ) {
				[otherMatchingTags addObject:way];
			} else {
				[otherWays addObject:way];
			}
		}
	}
	if ( otherMatchingTags.count ) {
		otherWays = otherMatchingTags;
	}
	if ( otherWays.count > 1 ) {
		// ambigious connection
		*error = NSLocalizedString(@"The target way is ambiguous",nil);
		return nil;
	} else if ( otherWays.count == 0 ) {
		*error = NSLocalizedString(@"Missing way to connect to",nil);
		return nil;
	}

	OsmWay * otherWay = otherWays.firstObject;
	if ( otherWay.nodes.count + selectedWay.nodes.count > 2000 ) {
		*error = NSLocalizedString(@"Max nodes after joining is 2000",nil);
		return nil;
	}

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
			if ( foundSet != 3 ) {
				*error = NSLocalizedString(@"Joining would invalidate a Turn Restriction the way belongs to",nil);
				return nil;
			}
		}
		// route or polygon, so should be okay
	}

	// check if extending the way would break something
	NSInteger loc = [selectedWay.nodes indexOfObject:selectedNode];
	if ( ![self canAddNodeToWay:selectedWay atIndex:(loc?:loc+1) error:error] )
		return nil;
	loc = [otherWay.nodes indexOfObject:selectedNode];
	if ( ![self canAddNodeToWay:otherWay atIndex:(loc?:loc+1) error:error] )
		return nil;

	NSDictionary * newTags = MergeTags(selectedWay.tags, otherWay.tags, NO);
	if ( newTags == nil ) {
		// tag conflict
		*error = NSLocalizedString(@"The ways contain incompatible tags",nil);
		return nil;
	}

	return ^{

		// join nodes, preserving selected way
		NSInteger index = 0;
		NSString * dummy = nil;
		if ( selectedWay.nodes.lastObject == otherWay.nodes[0] ) {
			[self registerUndoCommentString:NSLocalizedString(@"Join",nil)];
			for ( OsmNode * n in otherWay.nodes ) {
				if ( index++ == 0 )
					continue;
				[self addNodeUnsafe:n toWay:selectedWay atIndex:selectedWay.nodes.count];
			}
		} else if ( selectedWay.nodes.lastObject == otherWay.nodes.lastObject ) {
			[self registerUndoCommentString:NSLocalizedString(@"Join",nil)];
			EditAction reverse = [self canReverseWay:otherWay error:&dummy];	// reverse the tags on other way
			reverse();
			for ( OsmNode * n in otherWay.nodes ) {
				if ( index++ == 0 )
					continue;
				[self addNodeUnsafe:n toWay:selectedWay atIndex:selectedWay.nodes.count];
			}
		} else if ( selectedWay.nodes[0] == otherWay.nodes[0] ) {
			[self registerUndoCommentString:NSLocalizedString(@"Join",nil)];
			EditAction reverse = [self canReverseWay:otherWay error:&dummy];	// reverse the tags on other way
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
		[self updateParentMultipolygonRelationRolesForWay:selectedWay];
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

-(EditAction)canCircularizeWay:(OsmWay *)way error:(NSString **)error
{
	if ( !way.isWay || !way.isClosed || way.nodes.count < 4 ) {
		*error = NSLocalizedString(@"Requires a closed way with at least 3 nodes",nil);
		return nil;
	}

	return ^{
		OSMPoint center = [way centerPointWithArea:NULL];
		center.y = lat2latp(center.y);
		double radius = AverageDistanceToCenter(way, center);

		for ( int i = 0; i < way.nodes.count-1; i++ ) {
			OsmNode * n = way.nodes[i];
			double c = hypot( n.lon - center.x, lat2latp(n.lat) - center.y );
			double lat = latp2lat( center.y + (lat2latp(n.lat) - center.y) / c * radius );
			double lon = center.x + (n.lon - center.x) / c * radius;
			[self setLongitude:lon latitude:lat forNode:n];
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

-(OsmNode *)duplicateNode:(OsmNode *)node withOffset:(OSMPoint)offset
{
	CLLocationCoordinate2D loc = { node.lat + offset.y, node.lon + offset.x };
	OsmNode * newNode = [self createNodeAtLocation:loc];
	[self setTags:node.tags forObject:newNode];
	return newNode;
}

-(OsmWay *)duplicateWay:(OsmWay *)way withOffset:(OSMPoint)offset
{
	OsmWay * newWay = [self createWay];
	NSUInteger index = 0;
	for ( OsmNode * node in way.nodes ) {
		// check if node is a duplicate of previous node
		NSInteger prev = [way.nodes indexOfObject:node];
		OsmNode * newNode = prev < index ? newWay.nodes[prev] : [self duplicateNode:node withOffset:offset];
		[self addNodeUnsafe:newNode toWay:newWay atIndex:index++];
	}
	[self setTags:way.tags forObject:newWay];
	return newWay;
}

- (OsmBaseObject *)duplicateObject:(OsmBaseObject *)object withOffset:(OSMPoint)offset
{
	if ( object.isNode ) {
		[self registerUndoCommentString:NSLocalizedString(@"duplicate",nil)];
		return [self duplicateNode:object.isNode withOffset:offset];
	} else if ( object.isWay ) {
		[self registerUndoCommentString:NSLocalizedString(@"duplicate",nil)];
		return [self duplicateWay:object.isWay withOffset:offset];
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
					newWay = [self duplicateWay:way withOffset:offset];
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
		if (dotp < -0.707106781186547) { // -sin(PI/4)
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

-(EditAction)canOrthogonalizeWay:(OsmWay *)way error:(NSString **)error
{
	// needs a closed way to work properly.
	if ( !way.isWay || !way.isClosed || way.nodes.count < 5 ) {
		*error = NSLocalizedString(@"Requires a closed way with at least 4 nodes",nil);
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
			[self setLongitude:points[corner].x latitude:latp2lat(points[corner].y) forNode:node];

		} else {

			OSMPoint originalPoints[count];
			memcpy( originalPoints, points, sizeof points);
			double bestScore = 1e9;
			OSMPoint bestPoints[count];

			for ( NSInteger step = 0; step < 1000; step++) {
				OSMPoint motions[ count ];
				for ( NSInteger i = 0; i < count; ++i ) {
					motions[i] = calcMotion(points[i],i,points,count,NULL,NULL);
				}
				for ( NSInteger i = 0; i < count; i++) {
					if ( !isnan(motions[i].x) ) {
						points[i] = Add( points[i], motions[i] );
					}
				}
				double newScore = squareness(points,count);
				if (newScore < bestScore) {
					memcpy( bestPoints, points, sizeof points);
					bestScore = newScore;
				}
				if (bestScore < epsilon) {
					NSLog(@"Straighten steps = %d",(int)step);
					break;
				}
			}

			memcpy(points,bestPoints,sizeof points);

			for ( NSInteger i = 0; i < way.nodes.count; ++i ) {
				NSInteger modi = i < count ? i : 0;
				OsmNode * node = way.nodes[i];
				if ( points[i].x != originalPoints[i].x || points[i].y != originalPoints[i].y ) {
					[self setLongitude:points[modi].x latitude:latp2lat(points[modi].y) forNode:node];
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
					NSString * dummy = nil;
					EditAction canDeleteNode = [self canDeleteNode:node fromWay:way error:&dummy];
					if ( canDeleteNode ) {
						canDeleteNode();
					} else {
						// oh well...
					}
				}
			}
		}
	};
}

@end
