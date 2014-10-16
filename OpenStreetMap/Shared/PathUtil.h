//
//  PathUtil.h
//  OpenStreetMap
//
//  Created by Bryce on 1/24/13.
//  Copyright (c) 2013 Bryce. All rights reserved.
//

#ifndef OpenStreetMap_PathUtil_h
#define OpenStreetMap_PathUtil_h

#import "VectorMath.h"

typedef void (^ApplyPathCallback)(CGPathElementType type, CGPoint * points);

void CGPathApplyBlock( CGPathRef path, ApplyPathCallback block );
void InvokeBlockAlongPath( CGPathRef path, double initialOffset, double interval, void(^callback)(OSMPoint pt, OSMPoint direction) );
CGMutablePathRef PathReversed( CGPathRef path ) CF_RETURNS_RETAINED;
void PathPositionAndAngleForOffset( CGPathRef path, double startOffset, double baselineOffsetDistance, CGPoint * pPos, CGFloat * pAngle, CGFloat * pLength );
NSInteger CGPathPointCount( CGPathRef path );

#endif
