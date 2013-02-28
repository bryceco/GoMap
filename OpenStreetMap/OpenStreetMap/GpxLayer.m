//
//  GpxLayer.m
//  OpenStreetMap
//
//  Created by Bryce on 2/22/13.
//  Copyright (c) 2013 Bryce. All rights reserved.
//

#import "GpxLayer.h"
#import "DDXML.h"
#import "MapView.h"
#import "OsmObjects.h"


static double distance( double lat1, double lon1, double lat2, double lon2 )
{
	double R = 6371; // km
	lat1 *= M_PI/180;
	lat2 *= M_PI/180;
	double dLat = lat2 - lat1;
	double dLon = (lon2 - lon1)*M_PI/180;

	double a = sin(dLat/2) * sin(dLat/2) + sin(dLon/2) * sin(dLon/2) * cos(lat1) * cos(lat2);
	double c = 2 * atan2(sqrt(a), sqrt(1-a));
	double d = R * c;
	return d * 1000;
}

@implementation GpxPoint
@end

@implementation GpxTrack
@synthesize distance = _distance;
@synthesize startDate = _startDate;

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
	pt.elevation	= location.altitude;

	if ( _points == nil ) {
		_points = [NSMutableArray new];
	}
	[(NSMutableArray *)_points addObject:pt];

	NSLog( @"%f,%f (%f): %d gpx points", coordinate.longitude, coordinate.latitude, location.horizontalAccuracy, _points.count );
}

-(BOOL)saveXmlFile:(NSString * )path
{
	NSDateFormatter * dateFormatter = [OsmBaseObject rfc3339DateFormatter];

#if TARGET_OS_IPHONE
	NSXMLDocument * doc = [[NSXMLDocument alloc] initWithXMLString:@"<gpx creator=\"Go Map!!\" version=\"1.1\"></gpx>" options:0 error:NULL];
	NSXMLElement * root = [doc rootElement];
#else
	NSXMLElement * root = (NSXMLElement *)[NSXMLNode elementWithName:@"gpx"];
	NSXMLDocument * doc = [[NSXMLDocument alloc] initWithRootElement:root];
	[doc setCharacterEncoding:@"UTF-8"];
#endif
	NSXMLElement * trkElement = [NSXMLNode elementWithName:@"trk"];
	[root addChild:trkElement];
	NSXMLElement * segElement = [NSXMLNode elementWithName:@"trkseg"];
	[trkElement addChild:segElement];

	for ( GpxPoint * pt in self.points ) {

		NSXMLElement * ptElement = [NSXMLNode elementWithName:@"trkpt"];
		[segElement addChild:ptElement];

		NSXMLNode * attrLat   = [NSXMLNode attributeWithName:@"lat" stringValue:[NSString stringWithFormat:@"%f",pt.latitude]];
		NSXMLNode * attrLon = [NSXMLNode attributeWithName:@"lon" stringValue:[NSString stringWithFormat:@"%f",pt.longitude]];
		[ptElement addAttribute:attrLat];
		[ptElement addAttribute:attrLon];

		NSXMLElement * timeElement = [NSXMLNode elementWithName:@"time"];
		timeElement.stringValue = [dateFormatter stringFromDate:pt.timestamp];
		[root addChild:timeElement];

		NSXMLElement * eleElement = [NSXMLNode elementWithName:@"ele"];
		eleElement.stringValue = [NSString stringWithFormat:@"%f", pt.elevation];
		[root addChild:eleElement];
	}

	NSData * data = [doc XMLData];
	return [data writeToFile:path atomically:YES];
}

-(id)initWithXmlFile:(NSString * )path
{
	self = [self init];
	if ( self ) {
		NSData * data = [NSData dataWithContentsOfFile:path];
		if ( data == nil )
			return nil;
		NSXMLDocument * doc = [[NSXMLDocument alloc] initWithData:data options:0 error:NULL];
		if ( doc == nil )
			return nil;
		NSMutableArray * points = [NSMutableArray new];
		NSDateFormatter * dateFormatter = [OsmBaseObject rfc3339DateFormatter];
		NSArray * a = [doc nodesForXPath:@"./gpx/trk/trkseg/trkpt" error:nil];
		for ( NSXMLElement * pt in a ) {
			GpxPoint * point = [GpxPoint new];
			point.latitude  = [pt attributeForName:@"lat"].stringValue.doubleValue;
			point.longitude = [pt attributeForName:@"lon"].stringValue.doubleValue;
			NSArray * time = [pt elementsForName:@"time"];
			if ( time.count )
				point.timestamp = [dateFormatter dateFromString:time.lastObject];
			NSArray * ele = [pt elementsForName:@"ele"];
			if ( ele.count )
				point.elevation = [ele.lastObject doubleValue];
			[points addObject:point];
		}
		_points = [NSArray arrayWithArray:points];
	}
	return self;
}

-(double)distance
{
	if ( _distance == 0 ) {
		GpxPoint * prev = nil;
		for ( GpxPoint * pt in self.points ) {
			if ( prev ) {
				double d = distance( pt.latitude, pt.longitude, prev.latitude, prev.longitude );
				_distance += d;
			}
			prev = pt;
		}
	}
	return _distance;
}

-(NSDate *)startDate
{
	if ( _startDate == nil ) {
		if ( _points.count ) {
			GpxPoint * pt = _points[0];
			_startDate = pt.timestamp;
		}
	}
	return _startDate;
}

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

-(void)startNewTrack
{
	if ( self.activeTrack ) {
		[self endActiveTrack];
	}
	self.activeTrack = [GpxTrack new];
}

-(void)endActiveTrack
{
	if ( self.activeTrack ) {
		if ( self.previousTracks == nil ) {
			self.previousTracks = [NSMutableArray new];
		}
		[self.previousTracks addObject:self.activeTrack];
		self.activeTrack = nil;
	}
}

-(void)addPoint:(CLLocation *)location
{
	if ( self.activeTrack ) {
		[self.activeTrack addPoint:location];
	}
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
	for ( GpxPoint * point in self.activeTrack.points ) {
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
	if ( self.activeTrack ) {
		[self drawTrack:self.activeTrack.points context:ctx];
	}
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

