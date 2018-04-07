//
//  OsmMapData+Straighten.h
//  Go Map!!
//
//  Created by Bryce Cogswell on 7/9/14.
//  Copyright (c) 2014 Bryce Cogswell. All rights reserved.
//



#import "OsmMapData.h"

@class OsmWay;

@interface OsmMapData (Straighten)

- (BOOL)straightenWay:(OsmWay *)way;
- (BOOL)reverseWay:(OsmWay *)way;
- (BOOL)disconnectWay:(OsmWay *)selectedWay atNode:(OsmNode *)node;
- (OsmWay *)splitWay:(OsmWay *)selectedWay atNode:(OsmNode *)node;	// returns the new other half
- (BOOL)joinWay:(OsmWay *)selectedWay atNode:(OsmNode *)selectedNode;
- (BOOL)circularizeWay:(OsmWay *)way;
- (OsmBaseObject *)duplicateObject:(OsmBaseObject *)object;


-(OsmRelation *)createTurnRestrictionRelation:(OsmNode *)vieNode fromWay:(OsmWay *)fromWay toWay:(OsmWay *)toWay turn:(NSString *)strTurn;
-(OsmRelation *)updateTurnRestrictionRelation:(OsmRelation *)restriction viaNode:(OsmNode *)vieNode fromWay:(OsmWay *)fromWay toWay:(OsmWay *)toWay turn:(NSString *)strTurn;
@end
