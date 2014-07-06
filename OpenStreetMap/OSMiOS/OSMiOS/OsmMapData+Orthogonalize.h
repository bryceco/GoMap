//
//  OsmMapData+Orthogonalize.h
//  Go Map!!
//
//  Created by Bryce on 7/6/14.
//  Copyright (c) 2014 Bryce. All rights reserved.
//

#import "OsmMapData.h"

@class OsmWay;

@interface OsmMapData (Orthogonalize)

- (BOOL)orthogonalize:(OsmWay *)way;

@end
