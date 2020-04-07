//
//  VectorMath.h
//  Rocket
//
//  Created by Bryce Cogswell on 5/31/12.
//
//

#import <UIKit/UIKit.h>

#ifndef Rocket_VectorMath_h
#define Rocket_VectorMath_h


#define TRANSFORM_3D 0


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

#if TRANSFORM_3D
typedef CATransform3D OSMTransform;
#else
typedef struct _OSMTransform {
//	|  a   b   0  |
//	|  c   d   0  |
//	| tx  ty   1  |
	double a, b, c, d;
	double tx, ty;
} OSMTransform;
#endif

@interface OSMPointBoxed : NSObject
@property (readonly,nonatomic) OSMPoint	point;
+(OSMPointBoxed *)pointWithPoint:(OSMPoint)point;
@end

@interface OSMRectBoxed : NSObject
@property (readonly,nonatomic) OSMRect rect;
+(OSMRectBoxed *)rectWithRect:(OSMRect)rect;
@end

#pragma mark Point

static inline CGPoint CGPointWithOffset( CGPoint pt, CGFloat dx, CGFloat dy )
{
	return CGPointMake( pt.x+dx, pt.y+dy );
}

static inline CGPoint CGPointSubtract( CGPoint a, CGPoint b )
{
	CGPoint pt = { a.x - b.x, a.y - b.y };
	return pt;
}

static inline OSMPoint OSMPointMake(double x, double y)
{
	OSMPoint pt = { x, y };
	return pt;
}
static inline OSMPoint OSMPointFromCGPoint( CGPoint pt )
{
	OSMPoint point = { pt.x, pt.y };
	return point;
}
static inline CGPoint CGPointFromOSMPoint( OSMPoint pt )
{
	CGPoint p = { (CGFloat)pt.x, (CGFloat)pt.y };
	return p;
}


static inline double Dot( OSMPoint a, OSMPoint b )
{
	return a.x*b.x + a.y*b.y;
}

static inline double MagSquared( OSMPoint a )
{
	return a.x*a.x + a.y*a.y;
}

static inline double Mag( OSMPoint a )
{
	return hypot(a.x, a.y);
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
static inline OSMPoint OffsetPoint( OSMPoint p, double dx, double dy )
{
	OSMPoint p2 = { p.x+dx, p.y+dy };
	return p2;
}

OSMPoint ClosestPointOnLineToPoint( OSMPoint a, OSMPoint b, OSMPoint p );
CGFloat DistanceFromPointToLineSegment( OSMPoint point, OSMPoint line1, OSMPoint line2 );
CGFloat DistanceFromLineToPoint( OSMPoint lineStart, OSMPoint lineDirection, OSMPoint point );
BOOL LineSegmentsIntersect( OSMPoint p0, OSMPoint p1, OSMPoint p2, OSMPoint p3 );
double DistanceToVector( OSMPoint pos1, OSMPoint dir1, OSMPoint pos2, OSMPoint dir2 );
OSMPoint IntersectionOfTwoVectors( OSMPoint pos1, OSMPoint dir1, OSMPoint pos2, OSMPoint dir2 );
BOOL LineSegmentIntersectsRectangle( OSMPoint p1, OSMPoint p2, OSMRect rect );
double SurfaceArea( OSMRect latLon );
double GreatCircleDistance( OSMPoint p1, OSMPoint p2 );

#pragma mark Rect

static inline CGPoint CGRectCenter( CGRect rc )
{
	CGPoint c = { rc.origin.x+rc.size.width/2, rc.origin.y+rc.size.height/2 };
	return c;
}

static inline OSMRect OSMRectMake(double x, double y, double w, double h)
{
	OSMRect rc = { x, y, w, h };
	return rc;
}

static inline CGRect CGRectFromOSMRect( OSMRect rc )
{
	CGRect r = { (CGFloat)rc.origin.x, (CGFloat)rc.origin.y, (CGFloat)rc.size.width, (CGFloat)rc.size.height };
	return r;
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



#pragma mark Transform

OSMTransform OSMTransformInvert( OSMTransform t );


extern OSMPoint FromBirdsEye(OSMPoint point, CGPoint center, double birdsEyeDistance, double birdsEyeRotation );
extern OSMPoint ToBirdsEye(OSMPoint point, CGPoint center, double birdsEyeDistance, double birdsEyeRotation );

// point is 0..256
inline static OSMPoint LongitudeLatitudeFromMapPoint(OSMPoint point)
{
	double x = point.x / 256;
	double y = point.y / 256;
	x = x - floor(x);	// modulus
	y = y - floor(y);
	x = x - 0.5;
	y = y - 0.5;

	OSMPoint loc;
	loc.y = 90 - 360 * atan(exp(y * 2 * M_PI)) / M_PI;
	loc.x = 360 * x;
	return loc;
}
inline static OSMPoint MapPointForLatitudeLongitude(double latitude, double longitude)
{
	double x = (longitude + 180) / 360;
	double sinLatitude = sin(latitude * M_PI / 180);
	double y = 0.5 - log((1 + sinLatitude) / (1 - sinLatitude)) / (4 * M_PI);
	OSMPoint point = { x * 256, y * 256 };
	return point;
}

static inline CGAffineTransform CGAffineTransformFromOSMTransform( OSMTransform transform )
{
#if TRANSFORM_3D
	return CATransform3DGetAffineTransform(transform);
#else
	CGAffineTransform t;
	t.a = transform.a;
	t.b = transform.b;
	t.c = transform.c;
	t.d = transform.d;
	t.tx = transform.tx;
	t.ty = transform.ty;
	return t;
#endif
}


static inline OSMTransform OSMTransformIdentity(void)
{
#if TRANSFORM_3D
	return CATransform3DIdentity;
#else
	OSMTransform transform = { 0 };
	transform.a = transform.d = 1.0;
	return transform;
#endif
}

static inline BOOL OSMTransformEqual( OSMTransform t1, OSMTransform t2 )
{
	return memcmp( &t1, &t2, sizeof t1) == 0;
}

static inline double OSMTransformScaleX( OSMTransform t )
{
#if TRANSFORM_3D
	double d = sqrt( t.m11*t.m11 + t.m12*t.m12 + t.m13*t.m13 );
	return d;
#else
	return hypot(t.a,t.c);
#endif
}

static inline OSMTransform OSMTransformConcat( OSMTransform a, OSMTransform b )
{
#if TRANSFORM_3D
	return CATransform3DConcat(a, b);
#else
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
#endif
}

static inline double OSMTransformRotation( OSMTransform t )
{
#if TRANSFORM_3D
	return atan2( t.m12, t.m11 );
#else
	return atan2( t.b, t.a );
#endif
}

static inline OSMTransform OSMTransformMakeTranslation( double dx, double dy )
{
#if TRANSFORM_3D
	return CATransform3DMakeTranslation(dx, dy, 0);
#else
	OSMTransform t = { 1, 0, 0, 1, dx, dy };
	return t;
#endif
}

static inline OSMTransform OSMTransformTranslate( OSMTransform t, double dx, double dy )
{
#if TRANSFORM_3D
	return CATransform3DTranslate(t, dx, dy, 0);
#else
	t.tx += t.a * dx + t.c * dy;
	t.ty += t.b * dx + t.d * dy;
	return t;
#endif
}
static inline OSMTransform OSMTransformScale( OSMTransform t, double scale )
{
#if TRANSFORM_3D
	return CATransform3DScale(t, scale, scale, scale);
#else
	t.a *= scale;
	t.b *= scale;
	t.c *= scale;
	t.d *= scale;
	return t;
#endif
}

static inline OSMTransform OSMTransformScaleXY( OSMTransform t, double scaleX, double scaleY )
{
#if TRANSFORM_3D
	return CATransform3DScale(t, scaleX, scaleY, 1.0);
#else
	t.a *= scaleX;
	t.b *= scaleY;
	t.c *= scaleX;
	t.d *= scaleY;
	return t;
#endif
}

static inline OSMTransform OSMTransformRotate( OSMTransform transform, double angle )
{
#if TRANSFORM_3D
	return CATransform3DRotate( transform, angle, 0, 0, 1 );
#else
	double s = sin(angle);
	double c = cos(angle);
	OSMTransform t = { c, s, -s, c, 0, 0 };
	return OSMTransformConcat( t, transform );
#endif
}

static inline OSMPoint OSMPointApplyTransform( OSMPoint pt, OSMTransform t )
{
#if TRANSFORM_3D
	double zp = 0.0;
	double x = t.m11 * pt.x + t.m21 * pt.y + t.m31 * zp + t.m41;
	double y = t.m12 * pt.x + t.m22 * pt.y + t.m32 * zp + t.m42;
	return OSMPointMake( x, y );
#else
	OSMPoint p;
	p.x = pt.x * t.a + pt.y * t.c + t.tx;
	p.y = pt.x * t.b + pt.y * t.d + t.ty;
	return p;
#endif
}

static inline OSMRect OSMRectApplyTransform( OSMRect rc, OSMTransform transform )
{
	OSMPoint p1 = OSMPointApplyTransform( rc.origin, transform);
	OSMPoint p2 = OSMPointApplyTransform( OSMPointMake(rc.origin.x+rc.size.width, rc.origin.y+rc.size.height), transform);
	OSMRect r2 = { p1.x, p1.y, p2.x-p1.x, p2.y-p1.y };
	return r2;
}

static inline OSMPoint UnitX( OSMTransform t )
{
#if TRANSFORM_3D
	OSMPoint p = UnitVector(OSMPointMake(t.m11, t.m12));
	return p;
#else
	return UnitVector(OSMPointMake(t.a, t.b));
#endif
}

static inline OSMPoint Translation( OSMTransform t )
{
#if TRANSFORM_3D
	OSMPoint p = OSMPointMake(t.m41, t.m42);
	return p;
#else
	return OSMPointMake( t.tx, t.ty );
#endif
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
