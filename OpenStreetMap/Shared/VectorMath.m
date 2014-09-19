//
//  VectorMath.m
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 12/9/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import "VectorMath.h"


// https://developer.apple.com/library/mac/#samplecode/glut/Listings/gle_vvector_h.html


@implementation OSMPointBoxed
+(OSMPointBoxed *)pointWithPoint:(OSMPoint)point
{
	OSMPointBoxed * p = [OSMPointBoxed new];
	p->_point = point;
	return p;
}
-(id)copyWithZone:(NSZone *)zone
{
	return self;
}
-(NSString *)description
{
	return [NSString stringWithFormat:@"<%@ %p> x=%f,y=%f",[self class],self,_point.x,_point.y];
}
@end

@implementation OSMRectBoxed
+(OSMRectBoxed *)rectWithRect:(OSMRect)rect
{
	OSMRectBoxed * r = [OSMRectBoxed new];
	r->_rect = rect;
	return r;
}
@end



double Determinant( OSMTransform t )
{
	return t.a * t.d - t.b * t.c;
}

OSMTransform OSMTransformInvert( OSMTransform t )
{
	//	|  a   b   0  |
	//	|  c   d   0  |
	//	| tx  ty   1  |

	double det = Determinant( t );
	double s = 1.0 / det;
	OSMTransform a;

	a.a = s * t.d;
	a.c = s * -t.c;
	a.tx = s * (t.c * t.ty - t.d * t.tx);

	a.b = s * -t.b;
	a.d = s * t.a;
	a.ty = s * (t.b * t.tx - t.a * t.ty);

	return a;
}

OSMPoint ClosestPointOnLineToPoint( OSMPoint a, OSMPoint b, OSMPoint p )
{
	OSMPoint ap = Sub(p,a);
	OSMPoint ab = Sub(b,a);

	double ab2 = ab.x*ab.x + ab.y*ab.y;

	double ap_dot_ab = Dot( ap, ab );
	double t = ap_dot_ab / ab2;              // The normalized "distance" from a to point

	if ( t <= 0 ) {
		return a;
	}
	if ( t >= 1.0 ) {
		return b;
	}
	return Add( a, Mult( ab, t ) );
}


CGFloat DistanceFromLineToPoint( OSMPoint lineStart, OSMPoint lineDirection, OSMPoint point )
{
	// note: lineDirection must be unit vector
	OSMPoint dir = Sub( lineStart, point );
	CGFloat dist = Mag( Sub( dir, Mult( lineDirection, Dot(dir, lineDirection)) ));
	return dist;
}

CGFloat DistanceFromPointToLineSegment( OSMPoint point, OSMPoint line1, OSMPoint line2 )
{
	CGFloat length2 = MagSquared( Sub(line1, line2) );
	if ( length2 == 0.0 )
		return DistanceFromPointToPoint( point, line1 );
	CGFloat t = Dot( Sub(point, line1), Sub(line2, line1) ) / length2;
	if ( t < 0.0 )
		return DistanceFromPointToPoint(point, line1);
	if ( t > 1.0 )
		return DistanceFromPointToPoint(point, line2);

	OSMPoint projection = Add( line1, Mult( Sub(line2, line1), t));
	return DistanceFromPointToPoint(point, projection);
}

OSMPoint IntersectionOfTwoVectors( OSMPoint p1, OSMPoint v1, OSMPoint p2, OSMPoint v2 )
{
	CGFloat a = CrossMag( Sub(p2, p1), v2 ) / CrossMag(v1, v2);
	OSMPoint pt = Add( p1, Mult( v1, a ) );
	return pt;
}

BOOL LineSegmentIntersectsRectangle( OSMPoint p1, OSMPoint p2, OSMRect rect )
{
	double a_rectangleMinX = rect.origin.x;
	double a_rectangleMinY = rect.origin.y;
	double a_rectangleMaxX = rect.origin.x + rect.size.width;
	double a_rectangleMaxY = rect.origin.y + rect.size.height;
	double a_p1x = p1.x;
	double a_p1y = p1.y;
	double a_p2x = p2.x;
	double a_p2y = p2.y;

	// Find min and max X for the segment
	double minX = a_p1x;
	double maxX = a_p2x;

	if ( a_p1x > a_p2x ) {
		minX = a_p2x;
		maxX = a_p1x;
	}

	// Find the intersection of the segment's and rectangle's x-projections
	if ( maxX > a_rectangleMaxX ) {
		maxX = a_rectangleMaxX;
	}
	if ( minX < a_rectangleMinX ) {
		minX = a_rectangleMinX;
	}
	if ( minX > maxX ) {
		// If their projections do not intersect return false
		return NO;
	}

	// Find corresponding min and max Y for min and max X we found before
	double minY = a_p1y;
	double maxY = a_p2y;
	double dx = a_p2x - a_p1x;
	if ( fabs(dx) > 0.0000001 ) {
		double a = (a_p2y - a_p1y) / dx;
		double b = a_p1y - a * a_p1x;
		minY = a * minX + b;
		maxY = a * maxX + b;
	}

	if ( minY > maxY ) {
		double tmp = maxY;
		maxY = minY;
		minY = tmp;
	}

	// Find the intersection of the segment's and rectangle's y-projections
	if ( maxY > a_rectangleMaxY ) {
		maxY = a_rectangleMaxY;
	}
	if ( minY < a_rectangleMinY ) {
		minY = a_rectangleMinY;
	}
	if ( minY > maxY ) {
		// If Y-projections do not intersect return false
		return NO;
	}

	return YES;
}

// area in square meters
double SurfaceArea( OSMRect latLon )
{
	// http://mathforum.org/library/drmath/view/63767.html
	static const double EarthRadius = 6378137;
	double lon1 = latLon.origin.x;
	double lat1 = latLon.origin.y;
	double lon2 = latLon.origin.x + latLon.size.width;
	double lat2 = latLon.origin.y + latLon.size.height;
	double A = M_PI*EarthRadius*EarthRadius * fabs(sin(lat1*(M_PI/180))-sin(lat2*(M_PI/180))) * fabs(lon1-lon2)/180;
	return A;
}
