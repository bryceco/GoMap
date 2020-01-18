//
//  OsmObjects.m
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 10/27/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>

#import "iosapi.h"
#import "CommonTagList.h"
#import "CurvedTextLayer.h"
#import "DLog.h"
#import "OsmObjects.h"
#import "OsmMapData.h"
#import "UndoManager.h"


extern const double PATH_SCALING;


BOOL IsOsmBooleanTrue( NSString * value )
{
	if ( [value isEqualToString:@"true"] )
		return YES;
	if ( [value isEqualToString:@"yes"] )
		return YES;
	if ( [value isEqualToString:@"1"] )
		return YES;
	return NO;
}
BOOL IsOsmBooleanFalse( NSString * value )
{
	if ( [value respondsToSelector:@selector(boolValue)] ) {
		BOOL b = [value boolValue];
		return !b;
	}
	if ( [value isEqualToString:@"false"] )
		return YES;
	if ( [value isEqualToString:@"no"] )
		return YES;
	if ( [value isEqualToString:@"0"] )
		return YES;
	return NO;
}
NSString * OsmValueForBoolean( BOOL b )
{
	return b ? @"true" : @"false";
}

