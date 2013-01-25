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

void PathPositionAndAngleForOffset( CGPathRef path, double startOffset, CGPoint * pPos, CGFloat * pAngle )
{
	__block BOOL	done = NO;
	__block CGPoint	previous = { 0 };
	__block CGFloat	offset = startOffset;

	CGPathApplyBlock( path, ^(CGPathElementType type, CGPoint * points) {
		if ( done )
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
				CGFloat len = hypotf(dx,dy);
				dx /= len;
				dy /= len;

				// shift text off baseline
				CGPoint baselineOffset = { dy * 3, -dx * 3 };

				// always set position/angle because if we fall off the end we need it set
				pPos->x = previous.x + offset * dx + baselineOffset.x;
				pPos->y = previous.y + offset * dy + baselineOffset.y;
				*pAngle = atan2f(dy,dx);

				if ( offset < len ) {
					// found it
					done = YES;
				} else {
					offset -= len;
					previous = pt;
				}
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
CGPathRef ReversePath( CGPathRef path )
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
