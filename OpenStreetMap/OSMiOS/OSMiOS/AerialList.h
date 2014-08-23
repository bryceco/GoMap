//
//  CustomAerial.h
//  Go Map!!
//
//  Created by Bryce on 8/21/14.
//  Copyright (c) 2014 Bryce. All rights reserved.
//

#import <Foundation/Foundation.h>

#define BING_MAPS_KEY	@"ApunJH62__wQs1qE32KVrf6Fmncn7OZj6gWg_wtr27DQLDCkwkxGl4RsItKW4Fkk"


@interface AerialService : NSObject
@property (readonly) NSString * name;
@property (readonly) NSString * url;
@property (readonly) NSString * tileServers;
@property (readonly) NSInteger	maxZoom;
@property (readonly) NSString * cacheName;

-(instancetype)initWithName:(NSString *)name url:(NSString *)url servers:(NSString *)servers maxZoom:(NSInteger)maxZoom;
+(instancetype)aerialWithName:(NSString *)name url:(NSString *)url servers:(NSString *)servers maxZoom:(NSInteger)maxZoom;

@end


@interface AerialList : NSObject
{
	NSMutableArray *	_list;
}

@property BOOL								enabled;
@property (readonly) AerialService *	currentAerial;
@property NSInteger							currentIndex;

-(AerialService *)bingAerial;

-(void)load;
-(void)save;

-(NSInteger)count;
-(AerialService *)serviceAtIndex:(NSUInteger)index;
-(void)addService:(AerialService *)service atIndex:(NSInteger)index;
-(void)removeServiceAtIndex:(NSInteger)index;

@end
