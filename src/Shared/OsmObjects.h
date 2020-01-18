//
//  OsmObjects.h
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 10/27/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import "OsmBaseObject.h"

@class CAShapeLayer;
@class CurvedTextLayer;
@class OsmBaseObject;
@class OsmMapData;
@class OsmMember;
@class OsmNode;
@class OsmWay;
@class UndoManager;

NSDictionary * MergeTags(NSDictionary * myself, NSDictionary * tags, BOOL failOnConflict);


BOOL IsOsmBooleanTrue( NSString * value );
BOOL IsOsmBooleanFalse( NSString * value );


