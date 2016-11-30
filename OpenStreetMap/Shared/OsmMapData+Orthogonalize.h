//
//  OsmMapData+Orthogonalize.h
//  Go Map!!
//
//  Created by Bryce Cogswell on 7/6/14.
//  Copyright (c) 2014 Bryce Cogswell. All rights reserved.
//

#import "OsmMapData.h"

@class OsmWay;

@interface OsmMapData (Orthogonalize)

- (BOOL)orthogonalizeWay:(OsmWay *)way;

@end
