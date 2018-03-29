//
//  CustomAerial.h
//  Go Map!!
//
//  Created by Bryce Cogswell on 8/21/14.
//  Copyright (c) 2014 Bryce Cogswell. All rights reserved.
//

#import <Foundation/Foundation.h>

#define BING_MAPS_KEY	@"ApunJH62__wQs1qE32KVrf6Fmncn7OZj6gWg_wtr27DQLDCkwkxGl4RsItKW4Fkk"


@interface AerialService : NSObject
@property (readonly) NSString	*	name;
@property (readonly) NSString	*	url;
@property (readonly) int32_t		maxZoom;
@property (readonly) NSString	*	cacheName;
@property (readonly) NSString	*	metadataUrl;
@property (readonly) NSData		*	placeholderImage;
@property (readonly) CGPathRef 	*	polygon;
@property (readonly) BOOL			roundZoomUp;

-(BOOL)isBingAerial;

-(instancetype)initWithName:(NSString *)name url:(NSString *)url maxZoom:(NSInteger)maxZoom roundUp:(BOOL)roundUp polygon:(CGPathRef)polygon;
+(instancetype)aerialWithName:(NSString *)name url:(NSString *)url maxZoom:(NSInteger)maxZoom roundUp:(BOOL)roundUp polygon:(CGPathRef)polygon;
+(instancetype)mapnik;
+(instancetype)gpsTrace;
+(instancetype)mapboxLocator;

@end


@interface AerialList : NSObject
{
	NSMutableArray *	_list;
}

@property (readonly) AerialService *	currentAerial;
@property NSInteger						currentIndex;

-(void)load;
-(void)save;
-(void)reset;

-(NSInteger)count;
-(AerialService *)serviceAtIndex:(NSUInteger)index;
-(void)addService:(AerialService *)service atIndex:(NSInteger)index;
-(void)removeServiceAtIndex:(NSInteger)index;

@end
