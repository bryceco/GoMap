//
//  OsmObjects.h
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 10/27/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import "OsmBaseObject.h"

NSDictionary * MergeTags(NSDictionary * myself, NSDictionary * tags, BOOL failOnConflict);


BOOL IsOsmBooleanTrue( NSString * value );
BOOL IsOsmBooleanFalse( NSString * value );


