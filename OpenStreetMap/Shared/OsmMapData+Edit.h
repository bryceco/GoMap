//
//  OsmMapData+Straighten.h
//  Go Map!!
//
//  Created by Bryce Cogswell on 7/9/14.
//  Copyright (c) 2014 Bryce Cogswell. All rights reserved.
//



#import "OsmMapData.h"

@class OsmWay;

@interface OsmMapData (Edit)

// basic stuff:
- (EditAction)canDeleteNode:(OsmNode *)node error:(NSString **)error;
- (EditAction)canDeleteWay:(OsmWay *)way error:(NSString **)error;
- (EditAction)canDeleteRelation:(OsmRelation *)relation error:(NSString **)error;

- (EditActionWithNode)canAddNodeToWay:(OsmWay *)way atIndex:(NSInteger)index error:(NSString **)error;
- (EditActionReturnNode)canMergeNode:(OsmNode *)node1 intoNode:(OsmNode *)node2 error:(NSString **)error;

- (EditAction)canDeleteNode:(OsmNode *)node fromWay:(OsmWay *)way error:(NSString **)error;

// more complicated stuff:
- (EditAction)canOrthogonalizeWay:(OsmWay *)way error:(NSString **)error;
- (EditAction)canStraightenWay:(OsmWay *)way error:(NSString **)error;
- (EditAction)canReverseWay:(OsmWay *)way error:(NSString **)error;
- (EditActionReturnNode)canDisconnectWay:(OsmWay *)way atNode:(OsmNode *)node error:(NSString **)error;
- (EditActionReturnWay)canSplitWay:(OsmWay *)way atNode:(OsmNode *)node error:(NSString **)error;	// returns the new other half
- (EditAction)canJoinWay:(OsmWay *)selectedWay atNode:(OsmNode *)selectedNode error:(NSString **)error;
- (EditAction)canCircularizeWay:(OsmWay *)way error:(NSString **)error;
- (OsmBaseObject *)duplicateObject:(OsmBaseObject *)object;

-(OsmRelation *)updateTurnRestrictionRelation:(OsmRelation *)restriction viaNode:(OsmNode *)viaNode
									  fromWay:(OsmWay *)fromWay
								  fromWayNode:(OsmNode *)fromWayNode
										toWay:(OsmWay *)toWay
									toWayNode:(OsmNode *)toWayNode
										 turn:(NSString *)strTurn
									  newWays:(NSArray **)resultWays
									willSplit:(BOOL(^)(NSArray * splitWays))requiresSplitting;
@end
