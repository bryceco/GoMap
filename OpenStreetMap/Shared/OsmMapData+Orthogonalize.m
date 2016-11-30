//
//  OsmMapData+Orthogonalize.m
//  Go Map!!
//
//  Created by Bryce Cogswell on 7/6/14.
//  Copyright (c) 2014 Bryce Cogswell. All rights reserved.
//

#import <math.h>

#import "DLog.h"
#import "OsmObjects.h"
#import "OsmMapData.h"
#import "UndoManager.h"
#import "VectorMath.h"



@implementation OsmMapData (Orthogonalize)

static double threshold;
static double lowerThreshold;
static double upperThreshold;

static double filterDotProduct(double dotp)
{
	if (lowerThreshold > fabs(dotp) || fabs(dotp) > upperThreshold) {
		return dotp;
	}
	return 0;
}

static double normalizedDotProduct(NSInteger i, const OSMPoint points[], NSInteger count)
{
	OSMPoint a = points[(i - 1 + count) % count];
	OSMPoint b = points[i];
	OSMPoint c = points[(i + 1) % count];
	OSMPoint p = Sub(a, b);
	OSMPoint q = Sub(c, b);

	p = UnitVector(p);
	q = UnitVector(q);

	return Dot(p,q);
}

static double squareness(const OSMPoint points[], NSInteger count)
{
	double sum = 0.0;
	for ( NSInteger i = 0; i < count; ++i ) {
		double dotp = normalizedDotProduct(i, points,count);
		dotp = filterDotProduct(dotp);
		sum += 2.0 * MIN(fabs(dotp - 1.0), MIN(fabs(dotp), fabs(dotp + 1)));
	}
	return sum;
}


static OSMPoint calcMotion(OSMPoint b, NSInteger i, OSMPoint array[], NSInteger count, NSInteger * pCorner, double * pDotp )
{
	OSMPoint a = array[(i - 1 + count) % count];
	OSMPoint c = array[(i + 1) % count];
	OSMPoint p = Sub(a, b);
	OSMPoint q = Sub(c, b);

	OSMPoint origin = {0,0};
	double scale = 2 * MIN(DistanceFromPointToPoint(p, origin), DistanceFromPointToPoint(q, origin));
	p = UnitVector(p);
	q = UnitVector(q);

	if ( isnan(p.x) || isnan(q.x) ) {
		if ( pDotp )
			*pDotp = 1.0;
		return OSMPointMake(0, 0);
	}

	double dotp = filterDotProduct( Dot(p,q) );

	// nasty hack to deal with almost-straight segments (angle is closer to 180 than to 90/270).
	if (count > 3) {
		if (dotp < -0.707106781186547) {
			dotp += 1.0;
		}
	} else {
		// for triangles save the best corner
		if (dotp && pDotp && fabs(dotp) < *pDotp) {
			*pCorner = i;
			*pDotp = fabs( dotp );
		}
	}

	OSMPoint r = UnitVector( Add(p,q) );
	r = Mult( r, 0.1 * dotp * scale );
	return r;
}

-(BOOL)orthogonalizeWay:(OsmWay *)way
{
	// needs a closed way to work properly.
	if ( !way.isWay || !way.isClosed || way.nodes.count < 3 ) {
		return NO;
	}

	threshold = 12; // degrees within right or straight to alter
	lowerThreshold = cos((90 - threshold) * M_PI / 180);
	upperThreshold = cos(threshold * M_PI / 180);

	NSInteger count = way.nodes.count-1;
	OSMPoint points[ count ];
	for ( NSInteger i = 0; i < count; ++i ) {
		OsmNode * node = way.nodes[i];
		points[i].x = node.lon;
		points[i].y = lat2latp(node.lat);
	}

#if 0
	if ( squareness(points,count) == 0.0 ) {
		// already square
		return NO;
	}
#endif

	[_undoManager registerUndoComment:NSLocalizedString(@"Make Rectangular",nil)];

	double epsilon = 1e-4;

	if (count == 3) {

		double score = 0.0;
		NSInteger corner = 0;
		double dotp = 1.0;

		for ( NSInteger step = 0; step < 1000; step++) {
			OSMPoint motions[ count ];
			for ( NSInteger i = 0; i < count; ++i ) {
				motions[i] = calcMotion(points[i],i,points,count,&corner,&dotp);
			}
			points[corner] = Add( points[corner],motions[corner] );
			score = dotp;
			if (score < epsilon) {
				break;
			}
		}

		// apply new position
		OsmNode * node = way.nodes[corner];
		[self setLongitude:points[corner].x latitude:latp2lat(points[corner].y) forNode:node inWay:way];

	} else {

		OSMPoint best[count];
		OSMPoint originalPoints[count];
		memcpy( originalPoints, points, sizeof points);
		double score = 1e9;

		for ( NSInteger step = 0; step < 1000; step++) {
			OSMPoint motions[ count ];
			for ( NSInteger i = 0; i < count; ++i ) {
				motions[i] = calcMotion(points[i],i,points,count,NULL,NULL);
//				NSLog(@"motion[%ld] = %f,%f", i, motions[i].x, motions[i].y );
			}
			for ( NSInteger i = 0; i < count; i++) {
				points[i] = Add( points[i], motions[i] );
//				NSLog(@"points[%ld] = %f,%f", i, points[i].x, points[i].y );
			}
			double newScore = squareness(points,count);
			if (newScore < score) {
				memcpy( best, points, sizeof points);
				score = newScore;
			}
			if (score < epsilon) {
				break;
			}
		}

		memcpy(points,best,sizeof points);

		for ( NSInteger i = 0; i < way.nodes.count; ++i ) {
			NSInteger modi = i < count ? i : 0;
			OsmNode * node = way.nodes[i];
			if ( points[i].x != originalPoints[i].x || points[i].y != originalPoints[i].y ) {
				[self setLongitude:points[modi].x latitude:latp2lat(points[modi].y) forNode:node inWay:way];
			}
		}

		// remove empty nodes on straight sections
		// * deleting nodes that are referenced by non-downloaded ways could case data loss
		for (NSInteger i = count-1; i >= 0; i--) {
			OsmNode * node = way.nodes[i];

			if ( node.wayCount > 1 ||
				node.relations.count > 0 ||
				node.hasInterestingTags)
			{
				continue;
			}

			double dotp = normalizedDotProduct(i, points, count);
			if (dotp < -1 + epsilon) {
				[self deleteNodeInWay:way index:i];
			}
		}
	}

	return YES;
}

@end
