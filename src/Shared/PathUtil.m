//
//  PathUtil.m
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 1/24/13.
//  Copyright (c) 2013 Bryce Cogswell. All rights reserved.
//

#import "PathUtil.h"


static void InvokeBlockAlongPathCallback2( void * info, const CGPathElement * element )
{
	ApplyPathCallback block = (__bridge ApplyPathCallback)info;
	block( element->type, element->points );
}

void CGPathApplyBlockEx( CGPathRef path, ApplyPathCallback block )
{
	CGPathApply(path, (__bridge void *)block, InvokeBlockAlongPathCallback2);
}

NSInteger CGPathPointCount( CGPathRef path )
{
	__block NSInteger count = 0;
	CGPathApplyBlockEx( path, ^(CGPathElementType type, CGPoint *points) {
		++count;
	});
	return count;
}

NSInteger CGPathGetPoints( CGPathRef path, CGPoint pointList[] )
{
	__block NSInteger index = 0;
	CGPathApplyBlockEx( path, ^(CGPathElementType type, CGPoint *points) {
		switch ( type ) {
			case kCGPathElementMoveToPoint:
			case kCGPathElementAddLineToPoint:
				pointList[ index++ ] = points[0];
				break;
			case kCGPathElementCloseSubpath:
				pointList[ index++ ] = pointList[0];
				break;
			default:
				break;
		}
	});
	return index;
}

void CGPathDump( CGPathRef path )
{
	CGPathApplyBlockEx( path, ^(CGPathElementType type, CGPoint *points) {
		NSLog(@"%f,%f", points->x, points->y );
	});
}

void InvokeBlockAlongPath( CGPathRef path, double initialOffset, double interval, void(^callback)(CGPoint pt, CGPoint direction) )
{
	__block CGFloat offset = initialOffset;
	__block CGPoint previous;

	void(^block)(CGPathElementType type, CGPoint * points) = ^(CGPathElementType type, CGPoint * points){

		switch ( type ) {

			case kCGPathElementMoveToPoint:
				previous = points[0];
				break;

			case kCGPathElementAddLineToPoint:
			{
				CGPoint nextPt = points[0];
				double dx = nextPt.x - previous.x;
				double dy = nextPt.y - previous.y;
				double len = sqrt( dx*dx + dy*dy );
				dx /= len;
				dy /= len;

				while ( offset < len ) {
					// found it
					CGPoint pos = { previous.x + offset * dx, previous.y + offset * dy };
					CGPoint dir = { dx, dy };
					callback( pos, dir );
					offset += interval;
				}
				offset -= len;
				previous = nextPt;
			}
				break;

			case kCGPathElementAddQuadCurveToPoint:
			case kCGPathElementAddCurveToPoint:
			case kCGPathElementCloseSubpath:
				assert(NO);
				break;
		}
	};
	CGPathApplyBlockEx( path, block );
}

void PathPositionAndAngleForOffset( CGPathRef path, double startOffset, double baselineOffsetDistance, CGPoint * pPos, CGFloat * pAngle, CGFloat * pLength )
{
	__block BOOL	reachedOffset = NO;
	__block BOOL	quit = NO;
	__block CGPoint	previous = { 0 };
	__block CGFloat	offset = startOffset;

	CGPathApplyBlockEx( path, ^(CGPathElementType type, CGPoint * points) {
		if ( quit )
			return;
		switch ( type ) {
			case kCGPathElementMoveToPoint:
				previous = points[0];
				break;
			case kCGPathElementAddLineToPoint:
			{
				CGPoint pt = points[0];
				CGFloat dx = pt.x - previous.x;
				CGFloat dy = pt.y - previous.y;
				CGFloat len = hypot(dx,dy);
				dx /= len;
				dy /= len;
				CGFloat a = atan2f(dy,dx);

				// shift text off baseline
				CGPoint baselineOffset = { dy * baselineOffsetDistance, -dx * baselineOffsetDistance };

				if ( !reachedOffset ) {
					// always set position/angle because if we fall off the end we need it set
					pPos->x = previous.x + offset * dx + baselineOffset.x;
					pPos->y = previous.y + offset * dy + baselineOffset.y;
					*pAngle = a;
					*pLength = len - offset;
				} else {
					if ( fabs(a - *pAngle) < M_PI/40 ) {
						// continuation of previous
						*pLength = len - offset;
					} else {
						quit = YES;
					}
				}

				if ( offset < len ) {
					// found it
					reachedOffset = YES;
				}
				offset -= len;
				previous = pt;
			}
				break;
			case kCGPathElementAddQuadCurveToPoint:
			case kCGPathElementAddCurveToPoint:
			case kCGPathElementCloseSubpath:
				assert(NO);
				break;
		}
	});
}

// reverse path
CGMutablePathRef PathReversed( CGPathRef path )
{
	NSMutableArray * a = [NSMutableArray new];
	CGPathApplyBlockEx( path, ^(CGPathElementType type, CGPoint * points){
		if ( type == kCGPathElementMoveToPoint || type == kCGPathElementAddLineToPoint ) {
			CGPoint cgPoint = points[0];
			OSMPoint pt = { cgPoint.x, cgPoint.y };
			OSMPointBoxed * boxed = [OSMPointBoxed pointWithPoint:pt];
			[a addObject:boxed];
		}
	});
	CGMutablePathRef newPath = CGPathCreateMutable();
	__block BOOL first = YES;
	[a enumerateObjectsWithOptions:NSEnumerationReverse usingBlock:^(OSMPointBoxed * pt, NSUInteger idx, BOOL *stop) {
		if ( first ) {
			first = NO;
			CGPathMoveToPoint( newPath, NULL, pt.point.x, pt.point.y );
		} else {
			CGPathAddLineToPoint( newPath, NULL, pt.point.x, pt.point.y );
		}
	}];
	return newPath;
}



static CGPoint * DouglasPeuckerCore( CGPoint points[], NSInteger first, NSInteger last, double epsilon, CGPoint * result )
{
	// Find the point with the maximum distance
	double dmax = 0.0;
	NSInteger index = 0;
	OSMPoint end1 = OSMPointFromCGPoint( points[first] );
	OSMPoint end2 = OSMPointFromCGPoint( points[last] );
	for ( NSInteger i = first+1; i < last; ++i ) {
		OSMPoint p = OSMPointFromCGPoint( points[i] );
		CGFloat d = DistanceFromPointToLineSegment( p, end1, end2 );
		if ( d > dmax ) {
			index = i;
			dmax = d;
		}
	}
	// If max distance is greater than epsilon, recursively simplify
	if ( dmax > epsilon ) {
		// Recursive call
		result = DouglasPeuckerCore( points, first, index, epsilon, result );
		result = DouglasPeuckerCore( points, index, last, epsilon, result-1 );
	} else {
		*result++ = CGPointFromOSMPoint( end1 );
		*result++ = CGPointFromOSMPoint( end2 );
	}
	return result;
}

CGMutablePathRef PathWithReducePoints( CGPathRef path, double epsilon ) CF_RETURNS_RETAINED
{
	NSInteger count = CGPathPointCount( path );
	if ( count < 3 )
		return CGPathCreateMutableCopy( path );
	CGPoint * points = (CGPoint *)malloc( count * sizeof(points[0]));
	CGPoint * result = (CGPoint *)malloc( count * sizeof(result[0]));
	CGPathGetPoints( path, points );
	CGPoint * resultLast = DouglasPeuckerCore( points, 0, count-1, epsilon, result );
	NSInteger resultCount = resultLast - result;
	CGMutablePathRef newPath = CGPathCreateMutable();
	CGPathAddLines( newPath, NULL, result, resultCount );
	free( points );
	free( result );
	return newPath;
}
