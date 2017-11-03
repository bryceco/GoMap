//
//  PathUtil.h
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 1/24/13.
//  Copyright (c) 2013 Bryce Cogswell. All rights reserved.
//

#ifndef OpenStreetMap_PathUtil_h
#define OpenStreetMap_PathUtil_h

#import "VectorMath.h"

typedef void (^ApplyPathCallback)(CGPathElementType type, CGPoint * points);

void CGPathApplyBlockEx( CGPathRef path, ApplyPathCallback block );
void InvokeBlockAlongPath( CGPathRef path, double initialOffset, double interval, void(^callback)(OSMPoint pt, OSMPoint direction) );
CGMutablePathRef PathReversed( CGPathRef path ) CF_RETURNS_RETAINED;
void PathPositionAndAngleForOffset( CGPathRef path, double startOffset, double baselineOffsetDistance, CGPoint * pPos, CGFloat * pAngle, CGFloat * pLength );
NSInteger CGPathPointCount( CGPathRef path );
NSInteger CGPathGetPoints( CGPathRef path, CGPoint pointList[] );
void CGPathDump( CGPathRef path );
CGMutablePathRef PathWithReducePoints( CGPathRef path, double epsilon ) CF_RETURNS_RETAINED;

#endif
