//
//  CustomAerial.h
//  Go Map!!
//
//  Created by Bryce Cogswell on 8/21/14.
//  Copyright (c) 2014 Bryce Cogswell. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "VectorMath.h"


#define BING_MAPS_KEY	@"ApunJH62__wQs1qE32KVrf6Fmncn7OZj6gWg_wtr27DQLDCkwkxGl4RsItKW4Fkk"


@interface AerialService : NSObject
@property (readonly) NSString	*	name;
@property (readonly) NSString	*	identifier;
@property (readonly) NSString	*	url;
@property (readonly) int32_t		maxZoom;
@property (readonly) NSString	*	cacheName;
@property (readonly) NSString	*	metadataUrl;
@property (readonly) NSData		*	placeholderImage;
@property (readonly) CGPathRef 		polygon;
@property (readonly) BOOL			roundZoomUp;
@property (readonly) NSString	*	startDate;
@property (readonly) NSString	*	endDate;
@property (readonly) NSString	*	wmsProjection;
@property (readonly) NSString	*	attributionString;
@property (readonly) UIImage	*	attributionIcon;
@property (readonly) NSString	*	attributionUrl;


-(BOOL)isBingAerial;
-(BOOL)isMapnik;
-(BOOL)isOsmGpxOverlay;
-(BOOL)isMaxar;

+(NSDate *)dateFromString:(NSString *)string;

-(void)scaleAttributionIconToHeight:(CGFloat)height;
-(void)loadIconFromWeb:(NSString *)url;

-(instancetype)initWithName:(NSString *)name identifier:(NSString *)identifier url:(NSString *)url maxZoom:(NSInteger)maxZoom roundUp:(BOOL)roundUp startDate:(NSString *)startDate endDate:(NSString *)endDate wmsProjection:(NSString *)projection polygon:(CGPathRef)polygon attribString:(NSString *)attribString attribIcon:(UIImage *)attribIcon attribUrl:(NSString *)attribUrl;
+(instancetype)aerialWithName:(NSString *)name identifier:(NSString *)identifier url:(NSString *)url maxZoom:(NSInteger)maxZoom roundUp:(BOOL)roundUp startDate:(NSString *)startDate endDate:(NSString *)endDate wmsProjection:(NSString *)projection polygon:(CGPathRef)polygon attribString:(NSString *)attribString attribIcon:(UIImage *)attribIcon attribUrl:(NSString *)attribUrl;
+(instancetype)mapnik;
+(instancetype)gpsTrace;
+(instancetype)mapboxLocator;
+(instancetype)noName;

@end


@interface AerialList : NSObject
{
	NSMutableArray 	*	_userDefinedList;	// built-in and user-defined tiles
	NSArray			*	_downloadedList;	// downloaded on each launch
}

@property (nonatomic) 	AerialService	*	currentAerial;
@property (readonly) 	NSDate			*	lastDownloadDate;

-(void)load;
-(void)save;

-(NSArray *)builtinServices;
-(NSArray *)userDefinedServices;
-(NSArray *)servicesForRegion:(OSMRect)rect;

-(void)addUserDefinedService:(AerialService *)service atIndex:(NSInteger)index;
-(void)removeUserDefinedServiceAtIndex:(NSInteger)index;
@end
