//
//  MercatorTileLayer.h
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 10/5/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import "iosapi.h"
#import <QuartzCore/QuartzCore.h> 

@class AerialService;
@class MapView;


@interface MercatorTileLayer : CALayer <NSCacheDelegate>
{
	NSString						*	_tileCacheDirectory;
	NSCache							*	_memoryTileCache;
	NSString						*	_logoUrl;

	NSMutableDictionary				*	_layerDict;
}

@property (strong,nonatomic) AerialService	*	aerialService;
@property (assign,nonatomic) MapView		*	mapView;

-(id)initWithMapView:(MapView *)mapView;
-(IBAction)purgeTileCache;
-(NSInteger)diskCacheSize;
-(int32_t)zoomLevel;

-(NSMutableArray *)allTilesIntersectingVisibleRect;
-(void)downloadTileForKey:(NSString *)tileKey completion:(void(^)(void))completion;

-(void)metadata:(void(^)(NSData *,NSError *))callback;

@end
