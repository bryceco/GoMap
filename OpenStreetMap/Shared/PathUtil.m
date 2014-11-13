//
//  PathUtil.m
//  OpenStreetMap
//
//  Created by Bryce on 1/24/13.
//  Copyright (c) 2013 Bryce. All rights reserved.
//

#import "PathUtil.h"


static void InvokeBlockAlongPathCallback2( void * info, const CGPathElement * element )
{
	ApplyPathCallback block = (__bridge ApplyPathCallback)info;
	block( element->type, element->points );
}

void CGPathApplyBlock( CGPathRef path, ApplyPathCallback block )
{
	CGPathApply(path, (__bridge void *)block, InvokeBlockAlongPathCallback2);
}

NSInteger CGPathPointCount( CGPathRef path )
{
	__block NSInteger count = 0;
	CGPathApplyBlock( path, ^(CGPathElementType type, CGPoint *points) {
		++count;
	});
	return count;
}

NSInteger CGPathGetPoints( CGPathRef path, CGPoint pointList[] )
{
	__block NSInteger index = 0;
	CGPathApplyBlock( path, ^(CGPathElementType type, CGPoint *points) {
		pointList[ index++ ] = points[0];
	});
	return index;
}

void CGPathDump( CGPathRef path )
{
	CGPathApplyBlock( path, ^(CGPathElementType type, CGPoint *points) {
		NSLog(@"%f,%f", points->x, points->y );
	});
}

void InvokeBlockAlongPath( CGPathRef path, double initialOffset, double interval, void(^callback)(OSMPoint pt, OSMPoint direction) )
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
					OSMPoint pos = { previous.x + offset * dx, previous.y + offset * dy };
					OSMPoint dir = { dx, dy };
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
	CGPathApplyBlock( path, block );
}

void PathPositionAndAngleForOffset( CGPathRef path, double startOffset, double baselineOffsetDistance, CGPoint * pPos, CGFloat * pAngle, CGFloat * pLength )
{
	__block BOOL	reachedOffset = NO;
	__block BOOL	quit = NO;
	__block CGPoint	previous = { 0 };
	__block CGFloat	offset = startOffset;

	CGPathApplyBlock( path, ^(CGPathElementType type, CGPoint * points) {
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
	CGPathApplyBlock( path, ^(CGPathElementType type, CGPoint * points){
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
