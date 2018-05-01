//
//  MercatorTileLayer.m
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 10/5/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#include <sys/stat.h>
#import <QuartzCore/QuartzCore.h>
#include <dirent.h>
#include <libkern/OSAtomic.h>

#import "iosapi.h"

#import "AerialList.h"
#import "BingMapsGeometry.h"
#import "DLog.h"
#import "DownloadThreadPool.h"
#import "MapView.h"
#import "MercatorTileLayer.h"


#define CUSTOM_TRANSFORM 1


extern CGSize SizeForImage(NSImage * image);



@implementation MercatorTileLayer

@synthesize mapView = _mapView;


#pragma mark Implementation


-(instancetype)initWithMapView:(MapView *)mapView
{
	self = [super init];
	if ( self ) {
		//self.opaque = YES;

		self.needsDisplayOnBoundsChange = YES;

		// disable animations
		self.actions = @{
				 @"onOrderIn"	: [NSNull null],
				 @"onOrderOut"	: [NSNull null],
				 @"sublayers"	: [NSNull null],
				 @"contents"	: [NSNull null],
				 @"bounds"		: [NSNull null],
				 @"position"	: [NSNull null],
				 @"anchorPoint"	: [NSNull null],
				 @"transform"	: [NSNull null],
				 @"hidden"		: [NSNull null],
		 };

		_mapView = mapView;

		_layerDict = [NSMutableDictionary dictionary];

		_memoryTileCache = [[NSCache alloc] init];
		_memoryTileCache.delegate = self;
#if TARGET_OS_IPHONE
		_memoryTileCache.totalCostLimit = 20*1000*1000; // 20 MB
		_memoryTileCache.countLimit = _memoryTileCache.totalCostLimit / 4000;
#else
		_memoryTileCache.totalCostLimit = 100*1000*1000; // 100 MB
#endif

		[_mapView addObserver:self forKeyPath:@"screenFromMapTransform" options:0 context:NULL];
	}
	return self;
}

-(void)dealloc
{
	[_mapView removeObserver:self forKeyPath:@"screenFromMapTransform"];
}

-(void)setAerialService:(AerialService *)service
{
	if ( service == _aerialService )
		return;

	// remove previous data
	self.sublayers = nil;
	[_memoryTileCache removeAllObjects];
	[_layerDict removeAllObjects];

	// update service
	_aerialService = service;

	// get tile cache folder
	_tileCacheDirectory = nil;
	NSArray *paths = NSSearchPathForDirectoriesInDomains( NSCachesDirectory, NSUserDomainMask, YES );
	if ( [paths count] ) {
		NSString *bundleName = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleIdentifier"];
		_tileCacheDirectory = [[[paths objectAtIndex:0]
								stringByAppendingPathComponent:bundleName]
							   stringByAppendingPathComponent:service.cacheName];
		[[NSFileManager defaultManager] createDirectoryAtPath:_tileCacheDirectory withIntermediateDirectories:YES attributes:NULL error:NULL];
	}

	[self purgeOldCacheItemsAsync];
	[self setNeedsLayout];
}

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if ( object == _mapView && [keyPath isEqualToString:@"screenFromMapTransform"] ) {
#if !CUSTOM_TRANSFORM
		self.affineTransform = CGAffineTransformFromOSMTransform( _mapView.screenFromMapTransform );
#endif
		CATransform3D t = CATransform3DIdentity;
		t.m34 = -1/_mapView.birdsEyeDistance;
		t = CATransform3DRotate( t, _mapView.birdsEyeRotation, 1, 0, 0);
		self.sublayerTransform = t;

		[self setNeedsLayout];
	}
}


-(int32_t)zoomLevel
{
	double scaleX = OSMTransformScaleX( _mapView.screenFromMapTransform );
	return self.aerialService.roundZoomUp	? (int32_t)ceil(log2(scaleX))
											: (int32_t)floor(log2(scaleX));
}


-(void)metadata:(void(^)(NSData *,NSError *))callback
{
	if ( self.aerialService.metadataUrl == nil ) {
		callback( nil, nil );
	} else {
		OSMRect rc = [self.mapView screenLongitudeLatitude];

		int32_t	zoomLevel	= [self zoomLevel];
		if ( zoomLevel > 21 )
			zoomLevel = 21;
		NSString * url = [NSString stringWithFormat:self.aerialService.metadataUrl, rc.origin.y+rc.size.height/2, rc.origin.x+rc.size.width/2, zoomLevel];

		[[DownloadThreadPool generalPool] dataForUrl:url completeOnMain:YES completion:callback];
	}
}

- (void)cache:(NSCache *)cache willEvictObject:(id)obj
{
}

-(void)purgeTileCache
{
	NSArray * files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:_tileCacheDirectory error:NULL];
	for ( NSString * file in files ) {
		NSString * path = [_tileCacheDirectory stringByAppendingPathComponent:file];
		[[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
	}
	[_memoryTileCache removeAllObjects];
	[_layerDict removeAllObjects];
	self.sublayers = nil;
	[[NSURLCache sharedURLCache] removeAllCachedResponses];
	DLog(@"purge");
	[self setNeedsLayout];
}

-(void)purgeOldCacheItemsAsync
{
	NSString * cacheDir = _tileCacheDirectory;
	if ( cacheDir.length == 0 )
		return;

	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
		NSDate * now = [NSDate date];
		NSArray * files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:cacheDir error:NULL];
		for ( NSString * file in files ) {
			NSString * path = [cacheDir stringByAppendingPathComponent:file];
			struct stat status = { 0 };
			stat( path.UTF8String, &status );
			NSDate * date = [NSDate dateWithTimeIntervalSince1970:status.st_mtimespec.tv_sec];
			NSTimeInterval age = [now timeIntervalSinceDate:date];
			if ( age > 7.0 * 24*60*60 ) {
				[[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
			}
		}
	});
}

-(void)diskCacheSize:(NSInteger *)pSize count:(NSInteger *)pCount
{
	NSInteger size = 0;
	NSArray * files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:_tileCacheDirectory error:NULL];
	for ( NSString * file in files ) {
		NSString * path = [_tileCacheDirectory stringByAppendingPathComponent:file];
		struct stat status = { 0 };
		stat( path.fileSystemRepresentation, &status );
		size += (status.st_size + 511) & -512;
	}
	*pSize  = size;
	*pCount = files.count;
}


-(BOOL)layerOverlapsScreen:(CALayer *)layer
{
	CGRect rc = layer.frame;
	CGPoint center = CGRectCenter( rc );

	OSMPoint p1 = { rc.origin.x, rc.origin.y };
	OSMPoint p2 = { rc.origin.x, rc.origin.y+rc.size.height };
	OSMPoint p3 = { rc.origin.x+rc.size.width, rc.origin.y+rc.size.height };
	OSMPoint p4 = { rc.origin.x+rc.size.width, rc.origin.y };
	p1 = ToBirdsEye( p1, center, _mapView.birdsEyeDistance, _mapView.birdsEyeRotation );
	p2 = ToBirdsEye( p2, center, _mapView.birdsEyeDistance, _mapView.birdsEyeRotation );
	p3 = ToBirdsEye( p3, center, _mapView.birdsEyeDistance, _mapView.birdsEyeRotation );
	p4 = ToBirdsEye( p4, center, _mapView.birdsEyeDistance, _mapView.birdsEyeRotation );

	OSMRect rect = OSMRectFromCGRect(rc);
	return	OSMRectContainsPoint(rect, p1) ||
			OSMRectContainsPoint(rect, p2) ||
			OSMRectContainsPoint(rect, p3) ||
			OSMRectContainsPoint(rect, p4);
}

-(void)removeUnneededTilesForRect:(OSMRect)rect zoomLevel:(NSInteger)zoomLevel
{
	const int MAX_ZOOM = 30;

	NSMutableArray * removeList = [NSMutableArray array];

	// remove any tiles that don't intersect the current view
	for ( CALayer * layer in self.sublayers ) {
		if ( ! [self layerOverlapsScreen:layer] ) {
			[removeList addObject:layer];
		}
	}
	for ( CALayer * layer in removeList ) {
		NSString * key = [layer valueForKey:@"tileKey"];
		if ( key ) {
			// DLog(@"discard %@ - %@",key,layer);
			[_layerDict removeObjectForKey:key];
//			NSLog(@"prune %@",key);
			[layer removeFromSuperlayer];
			layer.contents = nil;
		}
	}
	[removeList removeAllObjects];

	// next remove objects that are covered by a parent (larger) object
	NSMutableArray *	layerList[ MAX_ZOOM ] = { nil };
	BOOL				transparent[ MAX_ZOOM ] = { NO };	// some objects at this level are transparent
	// place each object in a zoom level bucket
	for ( CALayer * layer in self.sublayers ) {
		NSString * tileKey = [layer valueForKey:@"tileKey"];
		NSUInteger z = tileKey.integerValue;	// zoom level
		if ( z < MAX_ZOOM ) {
			if ( layer.contents == nil ) {
				transparent[ z ] = YES;
			}
			if ( layerList[ z ] == nil ) {
				layerList[ z ] = [NSMutableArray arrayWithObject:layer];
			} else {
				[layerList[ z ] addObject:layer];
			}
		}
	}

	// remove tiles at zoom levels less than us if we don't have any transparent tiles (we've tiled everything in greater detail)
	BOOL remove = NO;
	for ( NSInteger z = zoomLevel; z >= 0; --z ) {
		if ( remove ) {
			[removeList addObjectsFromArray:layerList[z]];
		}
		if ( !transparent[z] ) {
			remove = YES;
		}
	}

	// remove tiles at zoom levels greater than us if we're not transparent (we cover the more detailed tiles)
	remove = NO;
	for ( NSInteger z = zoomLevel; z < MAX_ZOOM; ++z ) {
		if ( remove ) {
			[removeList addObjectsFromArray:layerList[z]];
		}
		if ( !transparent[z] ) {
			remove = YES;
		}
	}

	for ( CALayer * layer in removeList ) {
		NSString * key = [layer valueForKey:@"tileKey"];
		if ( key ) {
			// DLog(@"prune %@ - %@",key,layer);
//			NSLog(@"prune %@",key);
			[_layerDict removeObjectForKey:key];
			[layer removeFromSuperlayer];
			layer.contents = nil;
		}
	}
}

static inline int32_t modulus( int32_t a, int32_t n)
{
	int32_t m = a % n;
	if ( m < 0 )
		m += n;
	assert( m >= 0 );
	return m;
}

-(BOOL)isPlaceholderImage:(NSData *)data
{
	return [self.aerialService.placeholderImage isEqualToData:data];
}

-(NSString *)quadKeyForZoom:(int32_t)zoom tileX:(int32_t)tileX tileY:(int32_t)tileY
{
	return TileXYToQuadKey(tileX, tileY, zoom);
}

static OSMPoint TileToWMSCoords(NSInteger tx,NSInteger ty,NSInteger z,NSString * projection)
{
	double zoomSize = 1 << z;
	double lon = tx / zoomSize * M_PI * 2 - M_PI;
	double lat = atan( sinh( M_PI*(1-2*ty/zoomSize)));
	OSMPoint loc;
	if ( [projection isEqualToString:@"EPSG:4326"] ) {
		loc = OSMPointMake(lon*180/M_PI, lat*180/M_PI);
	} else {
		// EPSG:3857 and others
		loc = OSMPointMake( lon, log(tan((M_PI_2+lat)/2)) );	// mercatorRaw
		loc = Mult( loc, 20037508.34 / M_PI );
	}
	return loc;
}

-(NSString *)urlForZoom:(int32_t)zoom tileX:(int32_t)tileX tileY:(int32_t)tileY
{
	NSMutableString * url = [self.aerialService.url mutableCopy];

	// handle switch in URL
	NSRange start = [url rangeOfString:@"{switch:"];
	if ( start.location != NSNotFound ) {
		NSRange subs = { start.location+start.length, url.length-start.location-start.length };
		NSRange end = [url rangeOfString:@"}" options:0 range:subs];
		if ( end.location != NSNotFound ) {
			subs.length = end.location - subs.location;
			NSString * subdomains = [url substringWithRange:subs];
			NSArray * a = [subdomains componentsSeparatedByString:@","];
			if ( a.count ) {
				NSString * t = [a objectAtIndex:(tileX+tileY) % a.count];
				start.length = end.location - start.location + 1;
				[url replaceCharactersInRange:start withString:t];
			}
		}
	}

	NSString * projection = self.aerialService.projection;
	if ( projection ) {
		// WMS
		OSMPoint minXmaxY = TileToWMSCoords( tileX, tileY, zoom, projection );
		OSMPoint maxXminY = TileToWMSCoords( tileX+1, tileY+1, zoom, projection );
		NSString * bbox = [NSString stringWithFormat:@"%f,%f,%f,%f",minXmaxY.x,maxXminY.y,maxXminY.x,minXmaxY.y];
		[url replaceOccurrencesOfString:@"{width}" withString:@"256" options:0 range:NSMakeRange(0, url.length)];
		[url replaceOccurrencesOfString:@"{height}" withString:@"256" options:0 range:NSMakeRange(0, url.length)];
		[url replaceOccurrencesOfString:@"{proj}" withString:projection options:0 range:NSMakeRange(0, url.length)];
		[url replaceOccurrencesOfString:@"{bbox}" withString:bbox options:0 range:NSMakeRange(0, url.length)];

	} else {
		// TMS
		NSString * u = [self quadKeyForZoom:zoom tileX:tileX tileY:tileY];
		NSString * x = [NSString stringWithFormat:@"%d",tileX];
		NSString * y = [NSString stringWithFormat:@"%d",tileY];
		NSString * negY = [NSString stringWithFormat:@"%d",(1<<zoom)-tileY-1];
		NSString * z = [NSString stringWithFormat:@"%d",zoom];
		[url replaceOccurrencesOfString:@"{u}" withString:u options:0 range:NSMakeRange(0,url.length)];
		[url replaceOccurrencesOfString:@"{x}" withString:x options:0 range:NSMakeRange(0,url.length)];
		[url replaceOccurrencesOfString:@"{y}" withString:y options:0 range:NSMakeRange(0,url.length)];
		[url replaceOccurrencesOfString:@"{-y}" withString:negY options:0 range:NSMakeRange(0,url.length)];
		[url replaceOccurrencesOfString:@"{z}" withString:z options:0 range:NSMakeRange(0,url.length)];
	}

	return [url stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
}


typedef enum {
	DOWNLOAD_STATUS_DISK_FETCH,
	DOWNLOAD_STATUS_NETWORK_FETCH,
} DOWNLOAD_STATUS;

-(BOOL)fetchTileForTileX:(int32_t)tileX tileY:(int32_t)tileY
				 minZoom:(int32_t)minZoom
			   zoomLevel:(int32_t)zoomLevel
			  completion:(void(^)(NSError * error))completion
{
	int32_t tileModX = modulus( tileX, 1<<zoomLevel );
	int32_t tileModY = modulus( tileY, 1<<zoomLevel );

	NSString * tileKey = [NSString stringWithFormat:@"%d,%d,%d",zoomLevel,tileX,tileY];
	CALayer * layer = [_layerDict objectForKey:tileKey];
	if ( layer ) {
		if ( completion )
			completion(nil);
		return YES;
	}

	// create layer
	layer = [CALayer layer];
	layer.actions = self.actions;
	layer.zPosition = zoomLevel * 0.01 - 0.25;
	layer.edgeAntialiasingMask = 0;	// don't AA edges of tiles or there will be a seam visible
	layer.opaque = YES;
	layer.hidden = YES;
	[layer setValue:tileKey	forKey:@"tileKey"];
#if !CUSTOM_TRANSFORM
	layer.anchorPoint = CGPointMake(0,1);
	double scale = 256.0 / (1 << zoomLevel);
	layer.frame = CGRectMake( tileX * scale, tileY * scale, scale, scale );
#endif
	[_layerDict setObject:layer forKey:tileKey];

	OSAtomicIncrement32( &_isPerformingLayout );
	[self addSublayer:layer];
	OSAtomicDecrement32( &_isPerformingLayout );

	// check memory cache
	NSString * cacheKey = [self quadKeyForZoom:zoomLevel tileX:tileModX tileY:tileModY];
	NSImage * cachedImage = [_memoryTileCache objectForKey:cacheKey];
	if ( cachedImage ) {
#if TARGET_OS_IPHONE
		layer.contents = (__bridge id)cachedImage.CGImage;
#else
		layer.contents = image;
#endif
		layer.hidden = NO;
		if ( completion )
			completion(nil);
		return YES;
	}

	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^(void){

		// check disk cache
		NSString * cachePath = [[_tileCacheDirectory stringByAppendingPathComponent:cacheKey] stringByAppendingPathExtension:@"jpg"];
		NSData * fileData = [[NSData alloc] initWithContentsOfFile:cachePath];
		NSImage * fileImage = fileData ? [[NSImage alloc] initWithData:fileData] : nil;	// force read of data from disk prior to adding image to layer
		if ( fileImage ) {

			// image is in disk cache
			dispatch_async(dispatch_get_main_queue(), ^(void) {
				[_memoryTileCache setObject:fileImage forKey:cacheKey cost:fileData.length];
				if ( layer.superlayer ) {
#if TARGET_OS_IPHONE
					layer.contents = (__bridge id)fileImage.CGImage;
#else
					layer.contents = image;
#endif
					layer.hidden = NO;
#if CUSTOM_TRANSFORM
					[self setSublayerPositions:@{ tileKey : layer }];
#else
					OSMRect rc = [_mapView boundingMapRectForScreen];
					[self removeUnneededTilesForRect:rc zoomLevel:zoomLevel];
#endif
				} else {
					// layer no longer needed
				}
				if ( completion ) {
					completion(nil);
				}
			});

		} else {

			// fetch image from server
			NSString * url = [self urlForZoom:zoomLevel	tileX:tileModX tileY:tileModY];
			[[DownloadThreadPool generalPool] dataForUrl:url completeOnMain:NO completion:^(NSData * data,NSError * error) {

				NSImage * image = nil;
				if ( error ) {
					data = nil;
				} else if ( [self isPlaceholderImage:data] ) {
					error = [NSError errorWithDomain:@"Image" code:100 userInfo:@{ NSLocalizedDescriptionKey : NSLocalizedString(@"No image data at current zoom level",nil),
																								@"Ignorable" : @(YES)}];
				} else {
					image = [[NSImage alloc] initWithData:data];
				}

				if ( image ) {

					dispatch_sync(dispatch_get_main_queue(), ^(void){
						[_memoryTileCache setObject:image forKey:cacheKey cost:data.length];
						if ( layer.superlayer ) {
#if TARGET_OS_IPHONE
							layer.contents = (__bridge id) image.CGImage;
#else
							layer.contents = image;
#endif
							layer.hidden = NO;
#if CUSTOM_TRANSFORM
							[self setSublayerPositions:@{ tileKey : layer }];
#else
							OSMRect rc = [_mapView boundingMapRectForScreen];
							[self removeUnneededTilesForRect:rc zoomLevel:zoomLevel];
#endif
						} else {
							// no longer needed
							[_memoryTileCache setObject:image forKey:cacheKey cost:data.length];
						}
						if ( completion ) {
							completion(nil);
						}
					});

					dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
						[data writeToFile:cachePath atomically:YES];
					});

				} else if ( zoomLevel > minZoom ) {

					// try to show tile at one zoom level higher
					dispatch_async(dispatch_get_main_queue(), ^(void){
						[self fetchTileForTileX:tileX>>1 tileY:tileY>>1
								  minZoom:minZoom
									  zoomLevel:zoomLevel-1
									 completion:completion];
					});

				} else {
					
					// report error
					if ( error == nil ) {
						NSString * text = nil;
						if ( data ) {
							id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
							if ( json ) {
								text = [json description];
							} else {
								text = [[NSString alloc] initWithBytes:data.bytes length:data.length encoding:NSUTF8StringEncoding];
							}
						}
						if ( text.length < 5 ) {
							text = NSLocalizedString(@"No image data available",nil);
						}
						error = [NSError errorWithDomain:@"Image" code:100 userInfo:@{NSLocalizedDescriptionKey:text}];
					}

					if ( completion ) {
						dispatch_async(dispatch_get_main_queue(), ^(void){
							completion(error);
						});
					}
				}
			
			}];
		}
	});
	return NO;	// not immediately satisfied
}

-(void)setNeedsLayout
{
	if ( _isPerformingLayout )
		return;
	[super setNeedsLayout];
}


#if CUSTOM_TRANSFORM
-(void)setSublayerPositions:(NSDictionary *)layerDict
{
	// update locations of tiles
	double tRotation	= OSMTransformRotation( _mapView.screenFromMapTransform );
	double tScale		= OSMTransformScaleX( _mapView.screenFromMapTransform );

	[layerDict enumerateKeysAndObjectsUsingBlock:^(NSString * tileKey, CALayer * layer, BOOL *stop) {
		int32_t tileZ, tileX, tileY;
		sscanf( tileKey.UTF8String, "%d,%d,%d", &tileZ, &tileX, &tileY );

		double scale = 256.0 / (1 << tileZ);
		OSMPoint pt = { tileX * scale, tileY * scale };
		pt = [_mapView screenPointFromMapPoint:pt birdsEye:NO];
		layer.position		= CGPointFromOSMPoint( pt );
		layer.bounds		= CGRectMake( 0, 0, 256, 256 );
		layer.anchorPoint	= CGPointMake(0, 0);

		scale *= tScale / 256;
		CGAffineTransform t	= CGAffineTransformScale( CGAffineTransformMakeRotation( tRotation), scale, scale );
		layer.affineTransform = t;
	}];
}
#endif

-(void)layoutSublayersSafe
{
	OSMRect	rect		= [_mapView boundingMapRectForScreen];
	int32_t	zoomLevel	= [self zoomLevel];

	if ( zoomLevel < 1 ) {
		zoomLevel = 1;
	} else if ( zoomLevel > self.aerialService.maxZoom ) {
		zoomLevel = self.aerialService.maxZoom;
	}

	double zoom = (1 << zoomLevel) / 256.0;
	int32_t tileNorth	= floor( rect.origin.y * zoom );
	int32_t tileWest	= floor( rect.origin.x * zoom );
	int32_t tileSouth	= ceil( (rect.origin.y + rect.size.height) * zoom );
	int32_t tileEast	= ceil( (rect.origin.x + rect.size.width ) * zoom );

	if ( (tileEast-tileWest)*(tileSouth-tileNorth) > 4000 ) {
		DLog(@"Bad tile transform: %f", ((double)tileEast-tileWest)*(tileSouth-tileNorth));
		return;	// something is wrong
	}

	// create any tiles that don't yet exist
	for ( int32_t tileX = tileWest; tileX < tileEast; ++tileX ) {
		for ( int32_t tileY = tileNorth; tileY < tileSouth; ++tileY ) {

			[_mapView progressIncrement:NO];
			[self fetchTileForTileX:tileX tileY:tileY
						minZoom:MAX(zoomLevel-8,1)
						  zoomLevel:zoomLevel
						 completion:^(NSError * error) {
				if ( error ) {
					[_mapView presentError:error flash:YES];
				}
				[_mapView progressDecrement];
			}];
		}
	}

#if CUSTOM_TRANSFORM
	// update locations of tiles
	[self setSublayerPositions:_layerDict];
	[self removeUnneededTilesForRect:OSMRectFromCGRect(self.bounds) zoomLevel:zoomLevel];
#else
	OSMRect rc = [_mapView boundingMapRectForScreen];
	[self removeUnneededTilesForRect:rc zoomLevel:zoomLevel];
#endif

	[_mapView progressAnimate];
}

-(void)layoutSublayers
{
	if ( self.hidden )
		return;
	OSAtomicIncrement32( &_isPerformingLayout );
	[self layoutSublayersSafe];
	OSAtomicDecrement32( &_isPerformingLayout );
}



-(void)downloadTileForKey:(NSString *)cacheKey completion:(void(^)(void))completion
{
	int tileX, tileY, zoomLevel;
	QuadKeyToTileXY( cacheKey, &tileX, &tileY, &zoomLevel );

	// fetch image from server
	NSString * url = [self urlForZoom:zoomLevel	tileX:tileX tileY:tileY];
	[[DownloadThreadPool generalPool] dataForUrl:url completeOnMain:NO completion:^(NSData * data,NSError * error) {
		if ( data == nil || error || [self isPlaceholderImage:data] ) {
			// skip
		} else {
			NSImage * image = [[NSImage alloc] initWithData:data];
			if ( image ) {
				NSString * cachePath = [[_tileCacheDirectory stringByAppendingPathComponent:cacheKey] stringByAppendingPathExtension:@"jpg"];
				[data writeToFile:cachePath atomically:YES];
			}
		}
		dispatch_async(dispatch_get_main_queue(), ^(void){
			completion();
		});
	}];
}

// Used for bulk downloading tiles for offline use
-(NSMutableArray *)allTilesIntersectingVisibleRect
{
	NSArray * currentTiles = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:_tileCacheDirectory error:NULL];
	NSSet * currentSet = [NSSet setWithArray:currentTiles];

	OSMRect	rect			= [_mapView boundingMapRectForScreen];
	int32_t	minZoomLevel	= self.aerialService.roundZoomUp ? (int32_t)ceil(log2(OSMTransformScaleX(_mapView.screenFromMapTransform)))
															 : (int32_t)floor(log2(OSMTransformScaleX(_mapView.screenFromMapTransform)));
	if ( minZoomLevel < 1 ) {
		minZoomLevel = 1;
	}
	int32_t maxZoomLevel = self.aerialService.maxZoom;
	if ( maxZoomLevel > minZoomLevel + 2 )
		maxZoomLevel = minZoomLevel + 2;

	NSMutableArray * neededTiles = [NSMutableArray new];
	for ( int32_t zoomLevel = minZoomLevel; zoomLevel <= maxZoomLevel; ++zoomLevel ) {
		double zoom = (1 << zoomLevel) / 256.0;
		int32_t tileNorth	= floor( rect.origin.y * zoom );
		int32_t tileWest	= floor( rect.origin.x * zoom );
		int32_t tileSouth	= ceil( (rect.origin.y + rect.size.height) * zoom );
		int32_t tileEast	= ceil( (rect.origin.x + rect.size.width ) * zoom );

		for ( int32_t tileX = tileWest; tileX < tileEast; ++tileX ) {
			for ( int32_t tileY = tileNorth; tileY < tileSouth; ++tileY ) {
				NSString * cacheKey = [self quadKeyForZoom:zoomLevel tileX:tileX tileY:tileY];
				NSString * file = [cacheKey stringByAppendingString:@".jpg"];
				if ( [currentSet containsObject:file] ) {
					// already have it
				} else {
					[neededTiles addObject:cacheKey];
				}
			}
		}
	}
	return neededTiles;
}




-(void)setTransform:(CATransform3D)transform
{
	[super setTransform:transform];
	[self setNeedsLayout];
}

-(void)setHidden:(BOOL)hidden
{
	[super setHidden:hidden];
	
	if ( !hidden ) {
		[self setNeedsLayout];
	}
}

@end
