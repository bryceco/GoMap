//
//  OsmMapData+Orthogonalize.m
//  Go Map!!
//
//  Created by Bryce on 7/6/14.
//  Copyright (c) 2014 Bryce. All rights reserved.
//

#import <math.h>

#import "OsmObjects.h"
#import "OsmMapData.h"
#import "UndoManager.h"
#import "VectorMath.h"


static const int NUM_STEPS = 1000;
static const double TOLERANCE = 1.0e-8;


@implementation OsmMapData (Orthogonalize)

/**
 * returns the score of a particular corner, which is constructed so that all corners
 * which are straight lines or 90-degree corners score close to zero and other angles
 * score higher. The goal of this action is to minimise the sum of all scores.
 */
static double scoreOf(OSMPoint a, OSMPoint b, OSMPoint c)
{
	OSMPoint p = Sub(a, b);
	OSMPoint q = Sub(c, b);

	p = UnitVector(p);
	q = UnitVector(q);
	double dotp = Dot(p,q);
	// score is constructed so that +1, -1 and 0 are all scored 0, any other angle
	// is scored higher.
	double score = 2.0 * MIN(fabs(dotp-1.0), MIN(fabs(dotp), fabs(dotp+1.0)));
	return score;
}

// get the goodness (sum of scores) of the whole way.
static double goodness( OSMPoint points[], NSInteger count )
{
	double g = 0.0;
	for (NSInteger i = 1; i < count - 1; ++i) {
		double score = scoreOf( points[i-1], points[i], points[i+1] );
		g += score;
	}
	double startScore = scoreOf( points[count-1], points[0], points[1] );
	double endScore = scoreOf( points[count-2], points[count-1], points[0] );
	g += startScore;
	g += endScore;
	return g;
}


/**
 * One step of the solver. Moves points towards their neighbours, or away from them, depending on
 * the angle of that corner.
 */

static void step( OSMPoint points[], NSInteger count )
{
	OSMPoint motions[ count ];

	for (NSInteger i = 0; i < count; ++i ) {
		OSMPoint b = points[i];
		OSMPoint a = points[(i-1+count) % count];
		OSMPoint c = points[(i+1) % count] ;
		OSMPoint p = Sub( a, b );
		OSMPoint q = Sub( c, b );
		double scale = Mag(p) + Mag(q);
		p = UnitVector(p);
		q = UnitVector(q);
		double dotp = Dot(p,q);
		// nasty hack to deal with almost-straight segments (angle is closer to 180 than to 90/270).
		if (dotp < -0.707106781186547) {
			dotp += 1.0;
		}
		OSMPoint v = Add(p,q);
		v = UnitVector(v);
		v = Mult(v, 0.1 * dotp * scale);
		motions[i] = v;
	}
	for (NSInteger i = 0; i < count; ++i) {
		points[i] = Add( points[i], motions[i]);
	}
}


/**
 * Attempts to make all corners of a way right angles. Returns true if it
 * thought it was successful and false if it failed. If it fails it does not
 * modify the way.
 */
- (BOOL)orthogonalize:(OsmWay *)way;
{
	// needs a closed way to work properly.
	if ( !way.isWay || !way.isArea ) {
		return false;
	}

	// get list of coordinates
	NSInteger count = way.nodes.count-1;
	OSMPoint points[ count ];
	for ( NSInteger i = 0; i < count; ++i ) {
		OsmNode * node = way.nodes[i];
		points[i].x = node.lon;
		points[i].y = lat2latp( node.lat );
	}

	// adjust to make square
	double score = goodness(points,count);
	for (int i = 0; i < NUM_STEPS; ++i) {
		step( points, count );
		double newScore = goodness(points,count);
		if (newScore > score) {
			return false;
		}
		score = newScore;
		if (score < TOLERANCE) {
			break;
		}
	}

	// apply new positions
	[_undoManager registerUndoComment:@"Make Rectangular"];

	for ( NSInteger i = 0; i < way.nodes.count; ++i ) {
		NSInteger modi = i < count ? i : 0;
		OsmNode * node = way.nodes[i];
		[self setLongitude:points[modi].x latitude:latp2lat(points[modi].y) forNode:node inWay:way];
	}
	return true;
}


@end
