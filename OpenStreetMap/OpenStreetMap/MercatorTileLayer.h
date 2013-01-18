//
//  MercatorTileLayer.h
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 10/5/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import "iosapi.h"
#import <QuartzCore/QuartzCore.h> 

@class MapView;


@interface MercatorTileLayer : CALayer <NSCacheDelegate>
{
	NSString						*	_tileCacheDirectory;
	NSCache							*	_memoryTileCache;
	NSString						*	_logoUrl;

	NSMutableDictionary				*	_layerDict;
}

@property (assign,nonatomic) int32_t	maxZoomLevel;
@property (assign,nonatomic) BOOL		roundZoomUp;
@property (copy,nonatomic) NSString *	tileServerUrl;
@property (copy,nonatomic) NSArray	*	tileServerSubdomains;
@property (copy,nonatomic) NSString *	metadataUrl;
@property (strong,nonatomic) NSData *	placeholderImage;

@property (assign,nonatomic) MapView	*	mapView;

-(id)initWithName:(NSString *)name mapView:(MapView *)mapView callback:(void(^)(NSImage * logo))completion;
-(IBAction)purgeTileCache;
-(NSInteger)diskCacheSize;
-(int32_t)zoomLevel;

-(NSMutableArray *)allTilesIntersectingVisibleRect;
-(void)downloadTileForKey:(NSString *)tileKey completion:(void(^)(void))completion;

-(void)metadata:(void(^)(NSData *,NSError *))callback;

@end
