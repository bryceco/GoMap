//
//  GpxLayer.m
//  OpenStreetMap
//
//  Created by Bryce on 2/22/13.
//  Copyright (c) 2013 Bryce. All rights reserved.
//

#import "GpxLayer.h"
#import "MapView.h"



@implementation GpxPoint
@end



@implementation GpxLayer

-(id)initWithMapView:(MapView *)mapView
{
	self = [super init];
	if ( self ) {
		_mapView = mapView;

		// observe changes to geometry
		[_mapView addObserver:self forKeyPath:@"mapTransform" options:0 context:NULL];

		[self setNeedsDisplay];
	}
	return self;
}


-(void)setPoints:(NSArray *)points
{
	_points = [points mutableCopy];
}

-(NSArray *)points
{
	return [NSArray arrayWithArray:_points];
}

-(void)addPoint:(CLLocation *)location
{
	CLLocationCoordinate2D coordinate = location.coordinate;

	GpxPoint * prev = [_points lastObject];
	if ( prev && prev.latitude == coordinate.latitude && prev.longitude == coordinate.longitude )
		return;

	GpxPoint * pt = [GpxPoint new];
	pt.latitude		= coordinate.latitude;
	pt.longitude	= coordinate.longitude;
	pt.timestamp	= location.timestamp;

	if ( _points == nil ) {
		_points = [NSMutableArray new];
	}
	[_points addObject:pt];

	NSLog( @"%f,%f (%f): %d gpx points", coordinate.longitude, coordinate.latitude, location.horizontalAccuracy, _points.count );
}


- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if ( object == _mapView && [keyPath isEqualToString:@"mapTransform"] )  {
		[self setNeedsDisplay];
	} else {
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
	}
}


#if 0
-(void)setBounds:(CGRect)bounds
{
	[super setBounds:bounds];
	[self setNeedsDisplay];
}
#endif


- (void)save
{
}

- (id < CAAction >)actionForKey:(NSString *)key
{
	if ( [key isEqualToString:@"transform"] )
		return nil;
	if ( [key isEqualToString:@"bounds"] )
		return nil;
	if ( [key isEqualToString:@"position"] )
		return nil;
	//	DLog(@"actionForKey: %@",key);
	return [super actionForKey:key];
}


#pragma mark Drawing

-(OSMPoint)pointForLat:(double)lat lon:(double)lon
{
	OSMPoint pt = [MapView mapPointForLatitude:lat longitude:lon];
	OSMTransform transform = _mapView.mapTransform;
#if 1
	OSMPoint p2 = { pt.x - 128, pt.y - 128 };
	p2 = OSMPointApplyAffineTransform( p2, transform );
	pt.x = p2.x;
	pt.y = p2.y;
#else
	pt.x = (pt.x-128)*transform.a + transform.tx;
	pt.y = (pt.y-128)*transform.a + transform.ty;
#endif

	// modulus
	double denom = 256*transform.a;
	if ( pt.x > denom/2 )
		pt.x -= denom;
	else if ( pt.x < -denom/2 )
		pt.x += denom;

	return pt;
}



-(void)drawTrack:(NSArray *)way context:(CGContextRef)ctx
{
	CGMutablePathRef	path = CGPathCreateMutable();
	NSInteger			count = 0;
	for ( GpxPoint * point in _points ) {
		OSMPoint pt = [self pointForLat:point.latitude lon:point.longitude];
		if ( count == 0 ) {
			CGPathMoveToPoint(path, NULL, pt.x, pt.y );
		} else {
			CGPathAddLineToPoint(path, NULL, pt.x, pt.y );
		}
		++count;
	}

	CGContextBeginPath(ctx);
	CGContextAddPath(ctx, path);

	CGFloat red = 0, green = 0, blue = 1, alpha = 1;
	CGContextSetRGBStrokeColor(ctx, red, green, blue, alpha);
	CGFloat lineWidth = 2;
	CGContextSetLineWidth(ctx, lineWidth);
	CGContextStrokePath(ctx);

	CGPathRelease(path);
}

- (void)drawInContext:(CGContextRef)ctx
{
	[self drawTrack:_points context:ctx];
}


#pragma mark Properties

-(void)setHidden:(BOOL)hidden
{
	BOOL wasHidden = self.hidden;
	[super setHidden:hidden];

	if ( wasHidden && !hidden ) {
		[self setNeedsDisplay];
	}
}


@end

