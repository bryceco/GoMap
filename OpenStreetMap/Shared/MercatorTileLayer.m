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


#import "iosapi.h"

#import "AerialList.h"
#import "BingMapsGeometry.h"
#import "DLog.h"
#import "DownloadThreadPool.h"
#import "MapView.h"
#import "MercatorTileLayer.h"


#define CUSTOM_TRANSFORM 1


extern CGSize SizeForImage(NSImage * image);

// Disable animations
static NSDictionary * ActionDictionary = nil;

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
				 @"onOrderIn" : [NSNull null],
				 @"onOrderOut" : [NSNull null],
				 @"sublayers" : [NSNull null],
				 @"contents" : [NSNull null],
				 @"bounds" : [NSNull null],
				 @"position" : [NSNull null],
				 @"transform" : [NSNull null],
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

		[_mapView addObserver:self forKeyPath:@"mapTransform" options:0 context:NULL];
	}
	return self;
}

-(void)dealloc
{
	[_mapView removeObserver:self forKeyPath:@"mapTransform"];
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
	[self setNeedsDisplay];
}

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if ( object == _mapView && [keyPath isEqualToString:@"mapTransform"] ) {
#if CUSTOM_TRANSFORM
		[self setNeedsLayout];
#else
		self.affineTransform = CGAffineTransformFromOSMTransform( _mapView.mapTransform );
#endif
	}
}

-(int32_t)zoomLevel
{
	double z = _mapView.mapTransform.a;
	return self.aerialService.roundZoomUp	? (int32_t)ceil(log2(z))
											: (int32_t)floor(log2(z));
}


-(void)metadata:(void(^)(NSData *,NSError *))callback
{
	if ( self.aerialService.metadataUrl == nil ) {
		callback( nil, nil );
	} else {
		OSMRect rc = [self.mapView viewportLongitudeLatitude];

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
			if ( age > 60.0*60*24*14 ) {
				[[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
			}
		}
	});
}

-(NSInteger)diskCacheSize
{
	NSInteger size = 0;
	NSArray * files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:_tileCacheDirectory error:NULL];
	for ( NSString * file in files ) {
		NSString * path = [_tileCacheDirectory stringByAppendingPathComponent:file];
		struct stat status = { 0 };
		stat( path.fileSystemRepresentation, &status );
		size += (status.st_size + 511) & -512;
	}
	return size;
}


-(void)removeUnneededTilesForRect:(OSMRect)rect zoomLevel:(NSInteger)zoomLevel
{
	const int MAX_ZOOM = 30;

	NSMutableArray * removeList = [NSMutableArray array];

	for ( CALayer * layer in self.sublayers ) {
		OSMRect layerFrame = OSMRectFromCGRect( layer.frame );
		if ( ! OSMRectIntersectsRect( rect, layerFrame ) ) {
			[removeList addObject:layer];
		}
	}
	for ( CALayer * layer in removeList ) {
		NSString * key = [layer valueForKey:@"tileKey"];
		if ( key ) {
			[_layerDict removeObjectForKey:key];
			[layer removeFromSuperlayer];
			layer.contents = nil;
		}
	}

	[removeList removeAllObjects];

	NSMutableArray *	layerList[ MAX_ZOOM ] = { nil };
	BOOL				uncovered[ MAX_ZOOM ] = { NO };
	for ( CALayer * layer in self.sublayers ) {
		NSString * tileKey = [layer valueForKey:@"tileKey"];
		NSUInteger z = tileKey.integerValue;	// zoom level
		if ( z < MAX_ZOOM ) {
			if ( layer.contents == nil ) {
				uncovered[ z ] = YES;
			}
			if ( layerList[ z ] == nil ) {
				layerList[ z ] = [NSMutableArray arrayWithObject:layer];
			} else {
				[layerList[ z ] addObject:layer];
			}
		}
	}

	BOOL remove = NO;
	for ( NSInteger z = zoomLevel; z >= 0; --z ) {
		if ( remove ) {
			[removeList addObjectsFromArray:layerList[z]];
		}
		if ( !uncovered[z] ) {
			remove = YES;
		}
	}

	remove = NO;
	for ( NSInteger z = zoomLevel; z < MAX_ZOOM; ++z ) {
		if ( remove ) {
			[removeList addObjectsFromArray:layerList[z]];
		}
		if ( !uncovered[z] ) {
			remove = YES;
		}
	}

	for ( CALayer * layer in removeList ) {
		NSString * key = [layer valueForKey:@"tileKey"];
		if ( key ) {
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

-(NSString *)urlForZoom:(int32_t)zoom tileX:(int32_t)tileX tileY:(int32_t)tileY
{
	NSMutableString * url = [self.aerialService.url mutableCopy];
	NSString * t = self.aerialService.subdomains.count ? [self.aerialService.subdomains objectAtIndex:(tileX+tileY)%self.aerialService.subdomains.count] : @"{t}";
	NSString * u = [self quadKeyForZoom:zoom tileX:tileX tileY:tileY];
	NSString * x = [NSString stringWithFormat:@"%d",tileX];
	NSString * y = [NSString stringWithFormat:@"%d",tileY];
	NSString * z = [NSString stringWithFormat:@"%d",zoom];
	[url replaceOccurrencesOfString:@"{u}" withString:u options:0 range:NSMakeRange(0,url.length)];
	[url replaceOccurrencesOfString:@"{t}" withString:t options:0 range:NSMakeRange(0,url.length)];
	[url replaceOccurrencesOfString:@"{x}" withString:x options:0 range:NSMakeRange(0,url.length)];
	[url replaceOccurrencesOfString:@"{y}" withString:y options:0 range:NSMakeRange(0,url.length)];
	[url replaceOccurrencesOfString:@"{z}" withString:z options:0 range:NSMakeRange(0,url.length)];
	return url;
}

#if 0
-(void)setNeedsLayout
{
	[super setNeedsLayout];
}
#endif

-(void)fetchTileForTileX:(int32_t)tileX tileY:(int32_t)tileY
		   preferredZoom:(int32_t)preferredZoom
			   zoomLevel:(int32_t)zoomLevel
			  completion:(void(^)(NSError * error))completion
{
	int32_t tileModX = modulus( tileX, 1<<zoomLevel );
	int32_t tileModY = modulus( tileY, 1<<zoomLevel );

	NSString * tileKey = [NSString stringWithFormat:@"%d,%d,%d",zoomLevel,tileX,tileY];
	CALayer * layer = [_layerDict valueForKey:tileKey];
	if ( layer ) {
		completion(nil);
		return;
	}

	// create layer
	NSString * cacheKey = [self quadKeyForZoom:zoomLevel tileX:tileModX tileY:tileModY];
	layer = [CALayer layer];
	layer.actions = self.actions;
	layer.zPosition = zoomLevel;
	layer.anchorPoint = CGPointMake(0,1);
	layer.edgeAntialiasingMask = 0;	// don't AA edges of tiles or there will be a seam visible
	layer.opaque = YES;
	layer.hidden = YES;
	[layer setValue:tileKey forKey:@"tileKey"];
#if !CUSTOM_TRANSFORM
	double scale = 256.0 / (1 << zoomLevel);
	layer.frame = CGRectMake( tileX * scale, tileY * scale, scale, scale );
#endif
	[_layerDict setObject:layer forKey:tileKey];
	[self addSublayer:layer];

	// check memory cache
	NSImage * cachedImage = [_memoryTileCache objectForKey:cacheKey];
	if ( cachedImage ) {
#if TARGET_OS_IPHONE
		layer.contents = (__bridge id)cachedImage.CGImage;
#else
		layer.contents = image;
#endif
		layer.hidden = NO;
		completion(nil);
		return;
	}

	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void){
		
		// check disk cache
		NSString * cachePath = [[_tileCacheDirectory stringByAppendingPathComponent:cacheKey] stringByAppendingPathExtension:@"jpg"];
		NSData * fileData = [[NSData alloc] initWithContentsOfFile:cachePath];
		NSImage * fileImage = fileData ? [[NSImage alloc] initWithData:fileData] : nil;	// force read of data from disk prior to adding image to layer
		if ( fileImage ) {

			// image is in disk cache
			dispatch_async(dispatch_get_main_queue(), ^(void) {
#if TARGET_OS_IPHONE
				layer.contents = (__bridge id)fileImage.CGImage;
#else
				layer.contents = image;
#endif
				layer.hidden = NO;
				[_memoryTileCache setObject:fileImage forKey:cacheKey cost:fileData.length];
				[self removeUnneededTilesForRect:OSMRectFromCGRect(self.bounds) zoomLevel:zoomLevel];
				completion(nil);
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
#if TARGET_OS_IPHONE
						layer.contents = (__bridge id) image.CGImage;
#else
						layer.contents = image;
#endif
						layer.hidden = NO;
						[_memoryTileCache setObject:image forKey:cacheKey cost:data.length];
						[self removeUnneededTilesForRect:OSMRectFromCGRect(self.bounds) zoomLevel:zoomLevel];
						completion(nil);
					});
								   
					dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
						[data writeToFile:cachePath atomically:YES];
					});

				} else if ( zoomLevel > 1 && zoomLevel >= preferredZoom - 3 ) {

					// try to show tile at one zoom level higher
					dispatch_async(dispatch_get_main_queue(), ^(void){
						[self fetchTileForTileX:tileX>>1 tileY:tileY>>1
								  preferredZoom:preferredZoom
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

					dispatch_async(dispatch_get_main_queue(), ^(void){
						completion(error);
					});
				}
			
			}];
		}
	});
}

-(void)layoutSublayers
{
	if ( self.hidden )
		return;

	OSMRect	rect		= [_mapView mapRectFromVisibleRect];
	int32_t	zoomLevel	= [self zoomLevel];

#if 0
	static double prev = 0.0;
	DLog( @"origin = %f, %f, delta = %f", rect.origin.x, rect.origin.y, rect.origin.y - prev );
	prev = rect.origin.y;
#endif

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

#if 0
	DLog(@"tiling %d x %d", tileEast - tileWest, tileSouth - tileNorth );
	DLog(@"%d sublayers, %d dict", self.sublayers.count, _layerDict.count);
#endif

	// create any tiles that don't yet exist
	for ( int32_t tileX = tileWest; tileX < tileEast; ++tileX ) {
		for ( int32_t tileY = tileNorth; tileY < tileSouth; ++tileY ) {
			[_mapView progressIncrement:NO];
			[self fetchTileForTileX:tileX tileY:tileY
					  preferredZoom:zoomLevel
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
	[_layerDict enumerateKeysAndObjectsUsingBlock:^(NSString * tileKey, CALayer * layer, BOOL *stop) {
		NSArray * a = [tileKey componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@","]];
		int32_t tileZ = (int32_t) [a[0] integerValue];
		int32_t tileX = (int32_t) [a[1] integerValue];
		int32_t tileY = (int32_t) [a[2] integerValue];

		double scale = 256.0 / (1 << tileZ);
		OSMRect rc = { (tileX - 0.5) * scale, (tileY - 0.5) * scale, scale, scale };
		rc = [_mapView viewRectFromMapRect:rc];
		rc.origin.x -= 128;
		rc.origin.y -= 128;

		layer.frame = CGRectMake( rc.origin.x, rc.origin.y, rc.size.width, rc.size.height );
	}];

	[self removeUnneededTilesForRect:OSMRectFromCGRect(self.bounds) zoomLevel:zoomLevel];
#else
	[self removeUnneededTilesForRect:rect zoomLevel:zoomLevel];
#endif

	[_mapView progressAnimate];
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


-(NSMutableArray *)allTilesIntersectingVisibleRect
{
	NSArray * currentTiles = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:_tileCacheDirectory error:NULL];
	NSSet * currentSet = [NSSet setWithArray:currentTiles];

	OSMRect	rect			= [_mapView mapRectFromVisibleRect];
#if CUSTOM_TRANSFORM
	int32_t	minZoomLevel	= self.aerialService.roundZoomUp ? (int32_t)ceil(log2(_mapView.mapTransform.a))
															 : (int32_t)floor(log2(_mapView.mapTransform.a));
#else
	int32_t	minZoomLevel	= [self roundZoomUp] ? (int32_t)ceil(log2(self.affineTransform.a))
												 : (int32_t)floor(log2(self.affineTransform.a));
#endif
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
				if ( [currentSet containsObject:cacheKey] ) {
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
