//
//  VectorMath.h
//  Rocket
//
//  Created by Bryce Cogswell on 5/31/12.
//
//

#ifndef Rocket_VectorMath_h
#define Rocket_VectorMath_h

typedef struct _OSMPoint {
	double	x, y;
} OSMPoint;

typedef struct _OSMSize {
	double	width, height;
} OSMSize;

typedef struct _OSMRect {
	OSMPoint	origin;
	OSMSize		size;
} OSMRect;

typedef struct _OSMTransform {
//	|  a   b   0  |
//	|  c   d   0  |
//	| tx  ty   1  |
	double a, b, c, d;
	double tx, ty;
} OSMTransform;

@interface OSMPointBoxed : NSObject
@property (readonly,nonatomic) OSMPoint	point;
+(OSMPointBoxed *)pointWithPoint:(OSMPoint)point;
@end


static inline OSMPoint OSMPointMake(double x, double y)
{
	OSMPoint pt = { x, y };
	return pt;
}
static inline OSMRect OSMRectMake(double x, double y, double w, double h)
{
	OSMRect rc = { x, y, w, h };
	return rc;
}
static inline CGPoint CGPointFromOSMPoint( OSMPoint pt )
{
	CGPoint p = { (CGFloat)pt.x, (CGFloat)pt.y };
	return p;
}

static inline OSMRect OSMRectZero()
{
	OSMRect rc = { 0 };
	return rc;
}

static inline OSMRect OSMRectOffset( OSMRect rect, double dx, double dy )
{
	rect.origin.x += dx;
	rect.origin.y += dy;
	return rect;
}

static inline OSMTransform OSMAffineTransformInvert( OSMTransform transform );
static inline OSMRect OSMRectApplyAffineTransform( OSMRect rect, OSMTransform transform );

static inline OSMRect OSMRectFromCGRect( CGRect cg )
{
	OSMRect rc = { cg.origin.x, cg.origin.y, cg.size.width, cg.size.height };
	return rc;
}
static inline BOOL OSMRectContainsPoint( OSMRect rc, OSMPoint pt )
{
	return	pt.x >= rc.origin.x &&
			pt.x <= rc.origin.x + rc.size.width &&
			pt.y >= rc.origin.y &&
			pt.y <= rc.origin.y + rc.size.height;
}
static inline BOOL OSMRectIntersectsRect( OSMRect a, OSMRect b )
{
	if ( a.origin.x >= b.origin.x + b.size.width )
		return NO;
	if ( a.origin.x + a.size.width < b.origin.x )
		return NO;
	if ( a.origin.y >= b.origin.y + b.size.height )
		return NO;
	if ( a.origin.y + a.size.height < b.origin.y )
		return NO;
	return YES;
}


static inline OSMRect OSMRectUnion( OSMRect a, OSMRect b )
{
	double minX = MIN(a.origin.x,b.origin.x);
	double minY = MIN(a.origin.y,b.origin.y);
	double maxX = MAX(a.origin.x+a.size.width,b.origin.x+b.size.width);
	double maxY = MAX(a.origin.y+a.size.height,b.origin.y+b.size.height);
	OSMRect r = { minX, minY, maxX - minX, maxY - minY };
	return r;
}

static inline BOOL OSMRectContainsRect( OSMRect a, OSMRect b )
{
	return	a.origin.x <= b.origin.x &&
			a.origin.y <= b.origin.y &&
			a.origin.x + a.size.width >= b.origin.x + b.size.width &&
			a.origin.y + a.size.height >= b.origin.y + b.size.height;
}


static inline CGFloat Dot( OSMPoint a, OSMPoint b )
{
	return a.x*b.x + a.y*b.y;
}

static inline CGFloat MagSquared( OSMPoint a )
{
	return a.x*a.x + a.y*a.y;
}

static inline CGFloat Mag( OSMPoint a )
{
	return sqrt( a.x*a.x + a.y*a.y );
}

static inline OSMPoint Add( OSMPoint a, OSMPoint b )
{
	return OSMPointMake( a.x + b.x, a.y + b.y );
}

static inline OSMPoint Sub( OSMPoint a, OSMPoint b )
{
	return OSMPointMake( a.x - b.x, a.y - b.y );
}

static inline OSMPoint Mult( OSMPoint a, double c )
{
	return OSMPointMake(a.x*c, a.y*c);
}

static inline OSMPoint UnitVector( OSMPoint a )
{
	CGFloat d = Mag(a);
	return OSMPointMake(a.x/d, a.y/d);
}

static inline double CrossMag( OSMPoint a, OSMPoint b )
{
	return a.x*b.y - a.y*b.x;
}

static inline double DistanceFromPointToPoint( OSMPoint a, OSMPoint b)
{
	return Mag( Sub(a,b) );
}

OSMPoint ClosestPointOnLineToPoint( OSMPoint a, OSMPoint b, OSMPoint p );
CGFloat DistanceFromPointToLineSegment( OSMPoint point, OSMPoint line1, OSMPoint line2 );
CGFloat DistanceFromLineToPoint( OSMPoint lineStart, OSMPoint lineDirection, OSMPoint point );
OSMPoint IntersectionOfTwoVectors( OSMPoint p1, OSMPoint v1, OSMPoint p2, OSMPoint v2 );
BOOL LineSegmentIntersectsRectangle( OSMPoint p1, OSMPoint p2, OSMRect rect );



static inline OSMTransform OSMTransformIdentity(void)
{
	OSMTransform transform = { 0 };
	transform.a = transform.d = 1.0;
	return transform;
}

static inline OSMTransform OSMTransformTranslate( OSMTransform transform, double dx, double dy )
{
	double z = transform.a;
	transform.tx += dx * z;
	transform.ty += dy * z;
	return transform;
}
static inline OSMTransform OSMTransformScale( OSMTransform transform, double scale )
{
	transform.a *= scale;
	transform.b *= scale;
	transform.c *= scale;
	transform.d *= scale;
	transform.tx *= scale;
	transform.ty *= scale;
	return transform;
}

static inline OSMTransform OSMTransformConcat( OSMTransform a, OSMTransform b )
{
	//	|  a   b   0  |
	//	|  c   d   0  |
	//	| tx  ty   1  |
	OSMTransform c;
	c.a = a.a*b.a + a.b*b.c;
	c.b = a.a*b.b + a.b*b.d;
	c.c = a.c*b.a + a.d*b.c;
	c.d = a.c*b.b + a.d*b.d;
	c.tx = a.tx*b.a + a.ty*b.c + b.tx;
	c.ty = a.tx*b.b + a.ty*b.d + b.ty;
	return c;
}


static inline OSMTransform OSMTransformRotate( OSMTransform transform, double angle )
{
	double s = sin(angle);
	double c = cos(angle);

	OSMTransform t = { c, s, -s, c, 0, 0 };
	return OSMTransformConcat( transform, t );
}

static inline OSMPoint OSMPointApplyAffineTransform( OSMPoint pt, OSMTransform transform )
{
	OSMPoint p;
	p.x = pt.x * transform.a + pt.y * transform.c + transform.tx;
	p.y = pt.x * transform.b + pt.y * transform.d + transform.ty;
	return p;
}
static inline OSMRect OSMRectApplyAffineTransform( OSMRect rc, OSMTransform transform )
{
	OSMPoint p1 = OSMPointApplyAffineTransform( rc.origin, transform);
	OSMPoint p2 = OSMPointApplyAffineTransform( OSMPointMake(rc.origin.x+rc.size.width, rc.origin.y+rc.size.height), transform);
	OSMRect r2 = { p1.x, p1.y, p2.x-p1.x, p2.y-p1.y };
	return r2;
}

OSMTransform OSMTransformInvert( OSMTransform t );

static inline CGAffineTransform CGAffineTransformFromOSMTransform( OSMTransform transform )
{
	CGAffineTransform t;
	t.a = transform.a;
	t.b = transform.b;
	t.c = transform.c;
	t.d = transform.d;
	t.tx = transform.tx;
	t.ty = transform.ty;
	return t;
}


static inline double latp2lat(double a)
{
	return 180/M_PI * (2 * atan(exp(a*M_PI/180)) - M_PI/2);
}
static inline double lat2latp(double a)
{
	return 180/M_PI * log(tan(M_PI/4+a*(M_PI/180)/2));
}



#endif
