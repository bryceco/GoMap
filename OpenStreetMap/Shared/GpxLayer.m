//
//  GpxLayer.m
//  OpenStreetMap
//
//  Created by Bryce on 2/22/13.
//  Copyright (c) 2013 Bryce. All rights reserved.
//

#import <sys/stat.h>

#import "BingMapsGeometry.h"
#import "DLog.h"
#import "GpxLayer.h"
#import "DDXML.h"
#import "MapView.h"
#import "OsmObjects.h"
#import "PathUtil.h"

#define PATH_SCALING	(256*256.0)		// scale up sizes in paths so Core Animation doesn't round them off


//static const NSTimeInterval	MAX_AGE		= 7.0 * 24 * 60 * 60;


// Distance in meters
static double metersApart( double lat1, double lon1, double lat2, double lon2 )
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




@interface GpxLayerProperties : NSObject
{
@public
	OSMPoint		position;
	double			lineWidth;
//	CATransform3D	transform;
//	BOOL			is3D;
}
@end
@implementation GpxLayerProperties
-(instancetype)init
{
	self = [super init];
	if ( self ) {
//		transform = CATransform3DIdentity;
	}
	return self;
}
@end





@implementation GpxPoint
-(instancetype)initWithCoder:(NSCoder *)aDecoder
{
	self = [super init];
	if ( self ) {
		_latitude	= [aDecoder decodeDoubleForKey:@"lat"];
		_longitude	= [aDecoder decodeDoubleForKey:@"lon"];
		_accuracy	= [aDecoder decodeDoubleForKey:@"acc"];
		_elevation	= [aDecoder decodeDoubleForKey:@"ele"];
		_timestamp	= [aDecoder decodeObjectForKey:@"time"];
	}
	return self;
}
-(void)encodeWithCoder:(NSCoder *)aCoder
{
	[aCoder encodeDouble:_latitude forKey:@"lat"];
	[aCoder encodeDouble:_longitude forKey:@"lon"];
	[aCoder encodeDouble:_accuracy forKey:@"acc"];
	[aCoder encodeDouble:_elevation forKey:@"ele"];
	[aCoder encodeObject:_timestamp forKey:@"time"];
}
@end

@implementation GpxTrack
-(void)addPoint:(CLLocation *)location
{
	_recording = YES;
	 
	CLLocationCoordinate2D coordinate = location.coordinate;

	GpxPoint * prev = [_points lastObject];
	if ( prev && prev.latitude == coordinate.latitude && prev.longitude == coordinate.longitude )
		return;

	GpxPoint * pt = [GpxPoint new];
	pt.latitude		= coordinate.latitude;
	pt.longitude	= coordinate.longitude;
	pt.timestamp	= location.timestamp;
	pt.elevation	= location.altitude;
	pt.accuracy		= location.horizontalAccuracy;

	if ( _points == nil ) {
		_points = [NSMutableArray new];
		_creationDate = [NSDate date];
	}
	[(NSMutableArray *)_points addObject:pt];

//	DLog( @"%f,%f (%f): %lu gpx points", coordinate.longitude, coordinate.latitude, location.horizontalAccuracy, (unsigned long)_points.count );
}

-(void)finishTrack
{
	_recording = NO;
	_points = [NSArray arrayWithArray:_points];
}

-(NSString *)gpxXmlString
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
		[ptElement addChild:timeElement];

		NSXMLElement * eleElement = [NSXMLNode elementWithName:@"ele"];
		eleElement.stringValue = [NSString stringWithFormat:@"%f", pt.elevation];
		[ptElement addChild:eleElement];
	}

	NSString * string = [doc XMLString];
	return string;
}
-(NSData *)gpxXmlData
{
	NSData * data = [[self gpxXmlString] dataUsingEncoding:NSUTF8StringEncoding];
	return data;
}
-(BOOL)saveXmlFile:(NSString * )path
{
	NSData * data = [self gpxXmlData];
	return [data writeToFile:path atomically:YES];
}

-(instancetype)initWithXmlData:(NSData *)data
{
	if ( data == nil || data.length == 0 )
		return nil;

	self = [self init];
	if ( self ) {
		NSXMLDocument * doc = [[NSXMLDocument alloc] initWithData:data options:0 error:NULL];
		if ( doc == nil )
			return nil;

		NSXMLElement * namespace1 = [NSXMLElement namespaceWithName:@"ns1" stringValue:@"http://www.topografix.com/GPX/1/0"];
		NSXMLElement * namespace2 = [NSXMLElement namespaceWithName:@"ns2" stringValue:@"http://www.topografix.com/GPX/1/1"];
		[doc.rootElement addNamespace:namespace1];
		[doc.rootElement addNamespace:namespace2];

		NSMutableArray * points = [NSMutableArray new];
		NSDateFormatter * dateFormatter = [OsmBaseObject rfc3339DateFormatter];
		NSArray * a = [doc nodesForXPath:@"./ns1:gpx/ns1:trk/ns1:trkseg/ns1:trkpt" error:nil];
		if ( a.count == 0 )
			a = [doc nodesForXPath:@"./ns2:gpx/ns2:trk/ns2:trkseg/ns2:trkpt" error:nil];
		if ( a.count == 0 )
			a = [doc nodesForXPath:@"./gpx/trk/trkseg/trkpt" error:nil];
		if ( a.count == 0 )
			return nil;
		for ( NSXMLElement * pt in a ) {
			GpxPoint * point = [GpxPoint new];
			point.latitude  = [pt attributeForName:@"lat"].stringValue.doubleValue;
			point.longitude = [pt attributeForName:@"lon"].stringValue.doubleValue;
			NSArray * time = [pt elementsForName:@"time"];
			if ( time.count ) {
				NSString * s = [time.lastObject stringValue];
				point.timestamp = [dateFormatter dateFromString:s];
			}
			NSArray * ele = [pt elementsForName:@"ele"];
			if ( ele.count )
				point.elevation = [[ele.lastObject stringValue] doubleValue];
			[points addObject:point];
		}
		if ( points.count < 2 )
			return nil;
		_points = [NSArray arrayWithArray:points];

		self.creationDate = [NSDate date];
	}

	return self;
}

-(instancetype)initWithXmlFile:(NSString * )path
{
	NSData * data = [NSData dataWithContentsOfFile:path];
	if ( data == nil )
		return nil;
	self = [self initWithXmlData:data];
	return self;
}

-(double)distance
{
	if ( _distance == 0 ) {
		GpxPoint * prev = nil;
		for ( GpxPoint * pt in self.points ) {
			if ( prev ) {
				double d = metersApart( pt.latitude, pt.longitude, prev.latitude, prev.longitude );
				_distance += d;
			}
			prev = pt;
		}
	}
	return _distance;
}

-(NSString *)fileName
{
	return [NSString stringWithFormat:@"%.3f.track", self.creationDate.timeIntervalSince1970];
}


-(NSTimeInterval)duration
{
	if ( _points.count == 0 )
		return 0.0;

	GpxPoint * start = _points[0];
	GpxPoint * finish = _points.lastObject;
	return [finish.timestamp timeIntervalSinceDate:start.timestamp];
}

-(instancetype)initWithCoder:(NSCoder *)aDecoder
{
	self = [super init];
	if ( self ) {
		_points			= [aDecoder decodeObjectForKey:@"points"];
		_name			= [aDecoder decodeObjectForKey:@"name"];
		_creationDate	= [aDecoder decodeObjectForKey:@"creationDate"];
	}
	return self;
}
-(void)encodeWithCoder:(NSCoder *)aCoder
{
	[aCoder encodeObject:_points			forKey:@"points"];
	[aCoder encodeObject:_name				forKey:@"name"];
	[aCoder encodeObject:_creationDate		forKey:@"creationDate"];
}
-(void)dealloc
{
	for ( NSInteger i = 0; i < sizeof(shapePaths)/sizeof(shapePaths[0]); ++i ) {
		CGPathRef p = shapePaths[i];
		if ( p ) {
			CGPathRelease(p);
		}
	}
}
@end



@implementation GpxLayer

@synthesize activeTrack = _activeTrack;

-(id)initWithMapView:(MapView *)mapView
{
	self = [super init];
	if ( self ) {
		_mapView = mapView;

		[[NSUserDefaults standardUserDefaults] registerDefaults:@{ USER_DEFAULTS_GPX_EXPIRATIION_KEY : @(7) }];

		self.actions = @{
						 @"onOrderIn"	: [NSNull null],
						 @"onOrderOut"	: [NSNull null],
						 @"hidden"		: [NSNull null],
						 @"sublayers"	: [NSNull null],
						 @"contents"	: [NSNull null],
						 @"bounds"		: [NSNull null],
						 @"position"	: [NSNull null],
						 @"transform"	: [NSNull null],
						 @"lineWidth"	: [NSNull null],
						 };

		// observe changes to geometry
		[_mapView addObserver:self forKeyPath:@"screenFromMapTransform" options:0 context:NULL];

		[self setNeedsDisplay];
		[self setNeedsLayout];
	}
	return self;
}


-(void)startNewTrack
{
	if ( _activeTrack ) {
		[self endActiveTrack];
	}
	_activeTrack = [GpxTrack new];
	_stabilizingCount = 0;
}

-(void)endActiveTrack
{
	if ( _activeTrack ) {

		// add to list of previous tracks
		if ( _activeTrack.points.count > 1 ) {
			if ( self.previousTracks == nil ) {
				self.previousTracks = [NSMutableArray new];
			}
			[self.previousTracks addObject:_activeTrack];
		}

		[self saveToDisk:_activeTrack];
		_activeTrack = nil;
	}
}

-(void)saveToDisk:(GpxTrack *)track
{
	if ( track.points.count >= 2 ) {
		// make sure save directory exists
		NSTimeInterval time = CACurrentMediaTime();
		NSString * dir = [self saveDirectory];
		NSString * path = [dir stringByAppendingPathComponent:[track fileName]];
		[[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
		[NSKeyedArchiver archiveRootObject:track toFile:path];
		time = CACurrentMediaTime() - time;
		DLog(@"GPX track save time = %f\n", time);
	}
}

-(void)saveActiveTrack
{
	if ( _activeTrack ) {
		[self saveToDisk:_activeTrack];
	}
}

-(void)deleteTrack:(GpxTrack *)track
{
	NSString * path = [[self saveDirectory] stringByAppendingPathComponent:[track fileName]];
	[[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
	[_previousTracks removeObject:track];
	[track.shapeLayer removeFromSuperlayer];
	[self setNeedsDisplay];
	[self setNeedsLayout];
}


-(void)trimTracksOlderThan:(NSDate *)date
{
	// trim off old tracks
	for (;;) {
		if ( _previousTracks.count == 0 )
			break;
		GpxTrack * track = _previousTracks[0];
		GpxPoint * point = track.points[0];
		if ( [date timeIntervalSinceDate:point.timestamp] > 0 ) {
			// delete oldest
			[self deleteTrack:_previousTracks[0]];
		} else {
			break;
		}
	}
}

-(NSInteger)totalPointCount
{
	NSInteger total = _activeTrack.points.count;
	for ( GpxTrack * track in _previousTracks ) {
		total += track.points.count;
	}
	return total;
}

-(void)addPoint:(CLLocation *)location
{
	if ( self.activeTrack ) {

		// need to recompute shape layer
		[_activeTrack.shapeLayer removeFromSuperlayer];
		_activeTrack.shapeLayer = nil;

		// ignore bad data while starting up
		if ( _stabilizingCount++ >= 5 ) {
			// take it
		} else if ( _stabilizingCount == 1 ) {
			// always skip first point
			return;
		} else if ( location.horizontalAccuracy > 10.0 ) {
			// skip it
			return;
		}

#if 0
		for ( NSInteger i = 0; i < 1000; ++i ) {
			CLLocation * loc = [[CLLocation alloc] initWithCoordinate:CLLocationCoordinate2DMake(location.coordinate.latitude+i/1000000.0, location.coordinate.longitude) altitude:location.altitude horizontalAccuracy:location.horizontalAccuracy verticalAccuracy:location.verticalAccuracy course:location.course speed:location.speed timestamp:location.timestamp];
			[self.activeTrack addPoint:loc];
		}
#else
		[self.activeTrack addPoint:location];
#endif

		// automatically save periodically
		if ( self.activeTrack.points.count % 10 == 0 ) {
			[self saveActiveTrack];
		}

		[self setNeedsDisplay];
		[self setNeedsLayout];
	}
}


- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if ( object == _mapView && [keyPath isEqualToString:@"screenFromMapTransform"] )  {
		[self setNeedsDisplay];
		[self setNeedsLayout];
	} else {
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
	}
}


-(NSArray *)allTracks
{
	return self.activeTrack ? self.previousTracks ? [self.previousTracks arrayByAddingObject:self.activeTrack] : @[self.activeTrack] : self.previousTracks;
}


-(NSString *)saveDirectory
{
	NSArray * documentPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
	NSString * docsDir = documentPaths[0];
	NSString * filePathInDocsDir = [docsDir stringByAppendingPathComponent:@"gpxPoints"];
	return filePathInDocsDir;
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

#pragma mark Caching


// load data if not already loaded
-(void)loadTracksInBackgroundWithProgress:(void(^)(void))progressCallback
{
	if ( _previousTracks == nil ) {
		_previousTracks = [NSMutableArray new];

		NSNumber * expiration = [[NSUserDefaults standardUserDefaults] objectForKey:USER_DEFAULTS_GPX_EXPIRATIION_KEY];
		NSDate * cutoff = [NSDate dateWithTimeIntervalSinceNow:-expiration.doubleValue*24*60*60];

		dispatch_async(dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0), ^{
			NSString * dir = [self saveDirectory];
			NSArray * files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:NULL];
			for ( NSString * file in files ) {
				if ( [file hasSuffix:@".track"] ) {
					NSString * path = [dir stringByAppendingPathComponent:file];
					GpxTrack * track = [NSKeyedUnarchiver unarchiveObjectWithFile:path];
					if ( [track.creationDate timeIntervalSinceDate:cutoff] < 0 ) {
						// skip because its too old
						dispatch_sync(dispatch_get_main_queue(), ^{
							[self deleteTrack:track];
						});
						continue;
					}
					dispatch_sync(dispatch_get_main_queue(), ^{
						//DLog(@"track %@: %ld points\n",track.startDate, (long)track.points.count);
						[_previousTracks addObject:track];
						[self setNeedsDisplay];
						[self setNeedsLayout];
						if ( progressCallback ) {
							progressCallback();
						}
#if 1
						if ( track.creationDate == nil ) {
							GpxPoint * first = track.points[0];
							track.creationDate = first.timestamp;
							[self saveToDisk:track];
						}
#endif
					});
				}
			}
		});
	}
}

-(void)diskCacheSize:(NSInteger *)pSize count:(NSInteger *)pCount
{
	NSInteger size = 0;
	NSString * dir = [self saveDirectory];
	NSArray * files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:NULL];
	for ( NSString * file in files ) {
		if ( [file hasSuffix:@".track"] ) {
			NSString * path = [dir stringByAppendingPathComponent:file];
			struct stat status = { 0 };
			stat( path.fileSystemRepresentation, &status );
			size += (status.st_size + 511) & -512;
		}
	}
	*pSize  = size;
	*pCount = files.count + (_activeTrack != nil);
}

-(void)purgeTileCache
{
	BOOL active = _activeTrack != nil;
	NSInteger stable = _stabilizingCount;

	[self endActiveTrack];
	self.previousTracks = nil;
	self.sublayers = nil;
	
	NSString * dir = [self saveDirectory];
	[[NSFileManager defaultManager] removeItemAtPath:dir error:NULL];
	[[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];

	[self setNeedsLayout];
	[self setNeedsDisplay];

	if ( active ) {
		[self startNewTrack];
		_stabilizingCount = stable;
	}
}

-(void)centerOnTrack:(GpxTrack *)track
{
	// get midpoint
	NSInteger mid = track.points.count / 2;
	if ( mid >= track.points.count )
		mid = 0;
	GpxPoint * pt = track.points[ mid ];
	double widthDegrees = 20.0 / EarthRadius * 360;
	[_mapView setTransformForLatitude:pt.latitude longitude:pt.longitude width:widthDegrees];
}

-(BOOL)loadGPXData:(NSData *)data center:(BOOL)center
{
	GpxTrack * newTrack = [[GpxTrack alloc] initWithXmlData:data];
	if ( newTrack == nil ) {
		return NO;
	}
	if ( _previousTracks == nil ) {
		[self loadTracksInBackgroundWithProgress:nil];
	}
	[_previousTracks addObject:newTrack];
	if ( center ) {
		[self centerOnTrack:newTrack];
	}
	[self saveToDisk:newTrack];
	return YES;
}

#pragma mark Drawing


-(void)drawTrack:(NSArray *)way context:(CGContextRef)ctx
{
	CGMutablePathRef	path = CGPathCreateMutable();
	NSInteger			count = 0;
	for ( GpxPoint * point in way ) {
		CGPoint pt = [_mapView screenPointForLatitude:point.latitude longitude:point.longitude birdsEye:YES];
		if ( count == 0 ) {
			CGPathMoveToPoint(path, NULL, pt.x, pt.y );
		} else {
			CGPathAddLineToPoint(path, NULL, pt.x, pt.y );
		}
		++count;
	}

	CGContextBeginPath(ctx);
	CGContextAddPath(ctx, path);

//	CGFloat red = 0.5, green = 0.5, blue = 1.0, alpha = 1;	// blue
	CGFloat red = 1.0, green = 99/255.0, blue = 249/255.0, alpha = 1;	// pink
	CGContextSetRGBStrokeColor(ctx, red, green, blue, alpha);
	CGFloat lineWidth = 2;
	CGContextSetLineWidth(ctx, lineWidth);
	CGContextStrokePath(ctx);

	CGPathRelease(path);
}



-(void)setBounds:(CGRect)bounds
{
	[super setBounds:bounds];
//	_baseLayer.frame = bounds;
	[self setNeedsLayout];
}

-(CGPathRef)pathForTrack:(GpxTrack *)track refPoint:(OSMPoint *)refPoint CF_RETURNS_RETAINED
{
	CGMutablePathRef	path		= CGPathCreateMutable();
	OSMPoint			initial		= { 0, 0 };
	BOOL				haveInitial	= NO;
	BOOL				first		= YES;

	for ( GpxPoint * point in track.points ) {
		OSMPoint pt = MapPointForLatitudeLongitude( point.latitude, point.longitude );
		if ( isinf(pt.x) )
			break;
		if ( !haveInitial ) {
			initial = pt;
			haveInitial = YES;
		}
		pt.x -= initial.x;
		pt.y -= initial.y;
		pt.x *= PATH_SCALING;
		pt.y *= PATH_SCALING;
		if ( first ) {
			CGPathMoveToPoint(path, NULL, pt.x, pt.y);
			first = NO;
		} else {
			CGPathAddLineToPoint(path, NULL, pt.x, pt.y);
		}
	}

	if ( refPoint && haveInitial ) {
		// place refPoint at upper-left corner of bounding box so it can be the origin for the frame/anchorPoint
		CGRect bbox	= CGPathGetPathBoundingBox( path );
		if ( !isinf(bbox.origin.x) ) {
			CGAffineTransform tran = CGAffineTransformMakeTranslation( -bbox.origin.x, -bbox.origin.y );
			CGPathRef path2 = CGPathCreateCopyByTransformingPath( path, &tran );
			CGPathRelease( path );
			path = (CGMutablePathRef)path2;
			*refPoint = OSMPointMake( initial.x + (double)bbox.origin.x/PATH_SCALING, initial.y + (double)bbox.origin.y/PATH_SCALING );
		} else {
		}
	}

	return path;
}

-(CAShapeLayer *)getShapeLayerForTrack:(GpxTrack *)track
{
	if ( track.shapeLayer )
		return track.shapeLayer;

	OSMPoint refPoint = { 0, 0 };
	CGPathRef path = [self pathForTrack:track refPoint:&refPoint];
	if ( path == nil )
		return nil;
	track->shapePaths[0] = CGPathRetain( path );

	CAShapeLayer * layer = [CAShapeLayer new];
	layer.anchorPoint	= CGPointMake(0, 0);
	layer.position		= CGPointFromOSMPoint( refPoint );
	layer.path			= path;
	layer.strokeColor	= [UIColor colorWithRed:1.0 green:99/255.0 blue:249/255.0 alpha:1.0].CGColor;
	layer.fillColor		= nil;
	layer.lineWidth		= 2.0;
	layer.lineCap		= kCALineCapSquare;
	layer.lineJoin		= kCALineJoinMiter;
	layer.zPosition		= 0.0;
	layer.actions		= self.actions;
	GpxLayerProperties * props = [GpxLayerProperties new];
	[layer setValue:props forKey:@"properties"];
	props->position		= refPoint;
	props->lineWidth	= layer.lineWidth;
	track.shapeLayer	= layer;
	CGPathRelease(path);
	return layer;
}

-(void)layoutSublayersSafe
{
	const double	tRotation		= OSMTransformRotation( _mapView.screenFromMapTransform );
	const double	tScale			= OSMTransformScaleX( _mapView.screenFromMapTransform );
	const double	pScale			= tScale / PATH_SCALING;

	NSInteger scale = floor(-log(pScale));
//	DLog(@"gpx scale = %f, %ld",log(pScale),scale);
	if ( scale < 0 )
		scale = 0;

	for ( GpxTrack * track in [self allTracks] ) {

		CAShapeLayer * layer = [self getShapeLayerForTrack:track];

		if ( track->shapePaths[scale] == NULL ) {
			double epsilon = pow(10.0,scale) / 256.0;
			track->shapePaths[scale] = PathWithReducePoints( track->shapePaths[0], epsilon );
		}
//		DLog(@"reduce %ld to %ld\n",CGPathPointCount(track->shapePaths[0]),CGPathPointCount(track->shapePaths[scale]));
		layer.path = track->shapePaths[scale];

		// configure the layer for presentation
		GpxLayerProperties * props = [layer valueForKey:@"properties"];
		OSMPoint pt = props->position;
		OSMPoint pt2 = [_mapView screenPointFromMapPoint:pt birdsEye:NO];

		// rotate and scale
		CGAffineTransform t = CGAffineTransformMakeTranslation( pt2.x-pt.x, pt2.y-pt.y);
		t = CGAffineTransformScale( t, pScale, pScale );
		t = CGAffineTransformRotate( t, tRotation );
		layer.affineTransform = t;

		CAShapeLayer * shape = (id)layer;
		shape.lineWidth = props->lineWidth / pScale;

		// add the layer if not already present
		if ( layer.superlayer == nil ) {
			[self addSublayer:layer];
		}
	}
}

-(void)layoutSublayers
{
	[self layoutSublayersSafe];
}


#pragma mark Properties

-(void)setHidden:(BOOL)hidden
{
	BOOL wasHidden = self.hidden;
	[super setHidden:hidden];

	if ( wasHidden && !hidden ) {

		[self loadTracksInBackgroundWithProgress:nil];
		[self setNeedsDisplay];
		[self setNeedsLayout];
	}
}


@end

