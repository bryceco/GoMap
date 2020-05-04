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
@class PersistentWebCache;

@interface MercatorTileLayer : CALayer <NSCacheDelegate>
{
	PersistentWebCache						*	_webCache;
	NSString						*	_logoUrl;

	NSMutableDictionary				*	_layerDict;				// map of tiles currently displayed
	int32_t								_isPerformingLayout;
}

@property (strong,nonatomic) AerialService	*	aerialService;
@property (assign,nonatomic) MapView		*	mapView;

-(id)initWithMapView:(MapView *)mapView;
-(IBAction)purgeTileCache;
-(void)diskCacheSize:(NSInteger *)pSize count:(NSInteger *)pCount;
-(int32_t)zoomLevel;

-(NSMutableArray *)allTilesIntersectingVisibleRect;
-(void)downloadTileForKey:(NSString *)tileKey completion:(void(^)(void))completion;

-(void)metadata:(void(^)(NSData *,NSError *))callback;

@end
