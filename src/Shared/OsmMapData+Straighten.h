//
//  OsmMapData+Straighten.h
//  Go Map!!
//
//  Created by Bryce on 7/9/14.
//  Copyright (c) 2014 Bryce. All rights reserved.
//



#import "OsmMapData.h"

@class OsmWay;

@interface OsmMapData (Straighten)

- (BOOL)straightenWay:(OsmWay *)way;
- (BOOL)reverseWay:(OsmWay *)way;
- (BOOL)disconnectWay:(OsmWay *)selectedWay atNode:(OsmNode *)node;
- (BOOL)splitWay:(OsmWay *)selectedWay atNode:(OsmNode *)node;
- (BOOL)joinWay:(OsmWay *)selectedWay atNode:(OsmNode *)selectedNode;

@end
