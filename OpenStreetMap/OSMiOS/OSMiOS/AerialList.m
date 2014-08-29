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

@implementation AerialService

-(instancetype)initWithName:(NSString *)name url:(NSString *)url subdomains:(NSArray *)subdomains maxZoom:(NSInteger)maxZoom
{
	self = [super init];
	if ( self ) {
		_name = name ?: @"";
		_url = url ?: @"";
		_subdomains = subdomains;
		_maxZoom = maxZoom ?: 21;
	}
	return self;
}

+(instancetype)aerialWithName:(NSString *)name url:(NSString *)url subdomains:(NSArray *)subdomains maxZoom:(NSInteger)maxZoom
{
	return [[AerialService alloc] initWithName:name url:url subdomains:subdomains maxZoom:maxZoom];
}

-(BOOL)isBingAerial
{
	if ( [self.url hasPrefix:@"http://ecn.{t}.tiles.virtualearth.net"] )
		return YES;
	if ( [self.url hasPrefix:@"https://ecn.{t}.tiles.virtualearth.net"] )
		return YES;
	return NO;
}

+(AerialService *)defaultBingAerial
{
	static AerialService * bing = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		bing = [AerialService aerialWithName:@"Bing Aerial"
										 url:@"http://ecn.{t}.tiles.virtualearth.net/tiles/a{u}.jpeg?g=587&key=" BING_MAPS_KEY
								  subdomains:@[@"t0", @"t1", @"t2", @"t3"]
									 maxZoom:21];
	});
	return bing;
}

+(instancetype)mapnik
{
	static AerialService * mapnik = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		mapnik = [AerialService aerialWithName:@"MapnikTiles"
										   url:@"http://{t}.tile.openstreetmap.org/{z}/{x}/{y}.png"
									subdomains:@[ @"a", @"b", @"c" ]
									   maxZoom:18];
	});
	return mapnik;
}

-(NSDictionary *)dictionary
{
	return @{ @"name" : _name,
			  @"url" : _url,
			  @"subdomains" : _subdomains,
			  @"zoom" : @(_maxZoom)
			  };
}
-(instancetype)initWithDictionary:(NSDictionary *)dict
{
	return [self initWithName:dict[@"name"] url:dict[@"url"] subdomains:dict[@"subdomains"] maxZoom:[dict[@"zoom"] integerValue]];
}


-(NSString *)cacheName
{
	if ( self.isBingAerial )
		return @"BingAerialTiles";

	const char *cstr = [_url cStringUsingEncoding:NSUTF8StringEncoding];
	NSData * data = [NSData dataWithBytes:cstr length:_url.length];
	uint8_t digest[CC_SHA1_DIGEST_LENGTH];
	CC_SHA1(data.bytes, (CC_LONG)data.length, digest);
	return [NSString stringWithFormat:@"%08x", *(uint32_t *)digest];
}
-(NSString *)metadataUrl
{
	if ( self.isBingAerial ) {
		return @"http://dev.virtualearth.net/REST/V1/Imagery/Metadata/Aerial/%f,%f?zl=%d&include=ImageryProviders&key=" BING_MAPS_KEY;
	}
	return nil;
}
-(NSData *)placeholderImage
{
	if ( self.isBingAerial ) {
		static NSData * data;
		static dispatch_once_t onceToken;
		dispatch_once(&onceToken, ^{
			data = [NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"BingPlaceholderImage" ofType:@"png"]];
		});
		return data;
	}
	return nil;
}

-(BOOL)roundZoomUp
{
	return self == [AerialService mapnik] ? NO : YES;
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

-(void)reset
{
	_list = [[self builtins] mutableCopy];
}

-(NSArray *)builtins
{
	return @[

			 [AerialService defaultBingAerial],

			 [AerialService aerialWithName:@"MapBox Aerial"
											 url:@"http://{t}.tiles.mapbox.com/v4/openstreetmap.map-inh7ifmo/{z}/{x}/{y}.png?access_token=pk.eyJ1Ijoib3BlbnN0cmVldG1hcCIsImEiOiJhNVlHd29ZIn0.ti6wATGDWOmCnCYen-Ip7Q"
									  subdomains:@[@"a", @"b", @"c"]
										 maxZoom:19],

			 [AerialService aerialWithName:@"MapQuest Open Aerial"
											 url:@"http://otile{t}.mqcdn.com/tiles/1.0.0/sat/{z}/{x}/{y}.png"
									  subdomains:@[ @"1", @"2", @"3", @"4" ]
										 maxZoom:20],

			 [AerialService aerialWithName:@"OSM GPS Traces"
											 url:@"https://gps-{t}.tile.openstreetmap.org/lines/{z}/{x}/{y}.png"
									  subdomains:@[ @"a", @"b", @"c" ]
										 maxZoom:20],
			 ];
}

-(void)load
{
	NSUserDefaults * defaults = [NSUserDefaults standardUserDefaults];
	_list = [[defaults objectForKey:CUSTOMAERIALLIST_KEY] mutableCopy];
	if ( _list.count == 0 ) {
		[self reset];
	} else {
		for ( NSInteger i = 0; i < _list.count; ++i ) {
			_list[i] = [[AerialService alloc] initWithDictionary:_list[i]];
		}
	}
	_currentIndex = [defaults integerForKey:CUSTOMAERIALSELECTION_KEY];
}

-(void)save
{
	NSUserDefaults * defaults = [NSUserDefaults standardUserDefaults];
	NSMutableArray * a = [_list mutableCopy];
	for ( NSInteger i = 0; i < a.count; ++i ) {
		a[i] = [a[i] dictionary];
	}
	[defaults setObject:a forKey:CUSTOMAERIALLIST_KEY];
	[defaults setInteger:_currentIndex forKey:CUSTOMAERIALSELECTION_KEY];
}

-(AerialService *)currentAerial
{
	if ( self.currentIndex >= _list.count )
		return [AerialService defaultBingAerial];
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
