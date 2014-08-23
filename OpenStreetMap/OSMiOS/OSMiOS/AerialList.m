//
//  CustomAerial.m
//  Go Map!!
//
//  Created by Bryce on 8/21/14.
//  Copyright (c) 2014 Bryce. All rights reserved.
//

#import "AerialList.h"
#import <CommonCrypto/CommonDigest.h>

static NSString * CUSTOMAERIALLIST_KEY = @"AerialList";
static NSString * CUSTOMAERIALSELECTION_KEY = @"AerialListSelection";
static NSString * CUSTOMAERIALENABLED_KEY = @"AerialListEnabled";

@implementation AerialService

-(instancetype)initWithName:(NSString *)name url:(NSString *)url servers:(NSString *)servers maxZoom:(NSInteger)maxZoom
{
	self = [super init];
	if ( self ) {
		_name = name ?: @"";
		_url = url ?: @"";
		_tileServers = servers ?: @"";
		_maxZoom = maxZoom;
	}
	return self;
}

+(instancetype)aerialWithName:(NSString *)name url:(NSString *)url servers:(NSString *)servers maxZoom:(NSInteger)maxZoom
{
	return [[AerialService alloc] initWithName:name url:url servers:servers maxZoom:maxZoom];
}

-(NSString *)cacheName
{
	const char *cstr = [_url cStringUsingEncoding:NSUTF8StringEncoding];
	NSData * data = [NSData dataWithBytes:cstr length:_url.length];
	uint8_t digest[CC_SHA1_DIGEST_LENGTH];
	CC_SHA1(data.bytes, (CC_LONG)data.length, digest);
	return [NSString stringWithFormat:@"%08x", *(uint32_t *)digest];
}

-(NSString *)description
{
	return self.name;
}

@end



@implementation AerialList

-(instancetype)init
{
	self = [super init];
	if ( self ) {
		[self load];
	}
	return self;
}

+(NSDictionary *)dictForService:(AerialService *)service
{
	return @{ @"name" : service.name,
			  @"url" : service.url,
			  @"servers" : service.tileServers ?: @"",
			  @"zoom" : @(service.maxZoom)
			  };
}
+(AerialService *)serviceForDict:(NSDictionary *)dict
{
	return [AerialService aerialWithName:dict[@"name"] url:dict[@"url"] servers:dict[@"servers"] maxZoom:[dict[@"zoom"] integerValue]];
}


-(NSArray *)builtins
{
	return @[

			 [AerialService aerialWithName:@"MapBox Satellite"
											 url:@"http://{t}.tiles.mapbox.com/v4/openstreetmap.map-inh7ifmo/{z}/{x}/{y}.png?access_token=pk.eyJ1Ijoib3BlbnN0cmVldG1hcCIsImEiOiJhNVlHd29ZIn0.ti6wATGDWOmCnCYen-Ip7Q"
										 servers:@"a,b,c"
										 maxZoom:19],

			 [AerialService aerialWithName:@"MapQuest Open Aerial"
											 url:@"http://oatile{t}.mqcdn.com/tiles/1.0.0/sat/{z}/{x}/{y}.png"
										 servers:@"1,2,3,4"
										 maxZoom:0],

			 [AerialService aerialWithName:@"OSM GPS Traces"
											 url:@"https://gps-{t}.tile.openstreetmap.org/lines/{z}/{x}/{y}.png"
										 servers:@"a,b,c"
										 maxZoom:20],
			 ];
}

-(void)load
{
	NSUserDefaults * defaults = [NSUserDefaults standardUserDefaults];
	_list = [[defaults objectForKey:CUSTOMAERIALLIST_KEY] mutableCopy];
	if ( _list == nil ) {
		_list = [[self builtins] mutableCopy];
	} else {
		for ( NSInteger i = 0; i < _list.count; ++i ) {
			_list[i] = [self.class serviceForDict:_list[i]];
		}
	}
	_currentIndex = [defaults integerForKey:CUSTOMAERIALSELECTION_KEY];
	_enabled = [defaults boolForKey:CUSTOMAERIALENABLED_KEY];
}

-(void)save
{
	NSUserDefaults * defaults = [NSUserDefaults standardUserDefaults];
	NSMutableArray * a = [_list mutableCopy];
	for ( NSInteger i = 0; i < a.count; ++i ) {
		a[i] = [self.class dictForService:a[i]];
	}
	[defaults setObject:a forKey:CUSTOMAERIALLIST_KEY];
	[defaults setInteger:_currentIndex forKey:CUSTOMAERIALSELECTION_KEY];
	[defaults setBool:_enabled forKey:CUSTOMAERIALENABLED_KEY];
}

-(AerialService *)bingAerial
{
	static AerialService * bing = nil;
	if ( bing == nil ) {
		bing = [AerialService aerialWithName:@"Bing"
											   url:@"http://ecn.{t}.tiles.virtualearth.net/tiles/a{u}.jpeg?g=1049&key=" BING_MAPS_KEY
										   servers:@"t0,t1,t2,t3"
										   maxZoom:21];
	}
	return bing;
}

-(AerialService *)currentAerial
{
	return _list[ self.currentIndex ];
}

-(NSInteger)count
{
	return _list.count;
}

-(AerialService *)serviceAtIndex:(NSUInteger)index
{
	return [_list objectAtIndex:index];
}

-(void)addService:(AerialService *)service atIndex:(NSInteger)index
{
	[_list insertObject:service atIndex:index];
}

-(void)removeServiceAtIndex:(NSInteger)index
{
	[_list removeObjectAtIndex:index];
}

@end
