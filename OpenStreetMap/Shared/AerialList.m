//
//  CustomAerial.m
//  Go Map!!
//
//  Created by Bryce Cogswell on 8/21/14.
//  Copyright (c) 2014 Bryce Cogswell. All rights reserved.
//

#import "AerialList.h"
#import <CommonCrypto/CommonDigest.h>

static NSString * CUSTOMAERIALLIST_KEY = @"AerialList";
static NSString * CUSTOMAERIALSELECTION_KEY = @"AerialListSelection";

@implementation AerialService

-(instancetype)initWithName:(NSString *)name url:(NSString *)url maxZoom:(NSInteger)maxZoom roundUp:(BOOL)roundUp polygon:(CGPathRef)polygon
{
	self = [super init];
	if ( self ) {
		_name		= name ?: @"";
		_url		= url ?: @"";
		_maxZoom	= (int32_t)maxZoom ?: 21;
		_roundZoomUp = roundUp;
	}
	return self;
}

+(instancetype)aerialWithName:(NSString *)name url:(NSString *)url maxZoom:(NSInteger)maxZoom roundUp:(BOOL)roundUp polygon:(CGPathRef)polygon
{
	return [[AerialService alloc] initWithName:name url:url maxZoom:maxZoom roundUp:roundUp polygon:polygon];
}

-(BOOL)isBingAerial
{
	if ( [self.url containsString:@"tiles.virtualearth.net"] )
		return YES;
	return NO;
}

+(AerialService *)defaultBingAerial
{
	static AerialService * bing = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		bing = [AerialService aerialWithName:@"Bing Aerial"
										 url:@"http://ecn.{switch:t0,t1,t2,t3}.tiles.virtualearth.net/tiles/a{u}.jpeg?g=587&key=" BING_MAPS_KEY
									 maxZoom:21
									 roundUp:YES
									 polygon:NULL];
	});
	return bing;
}

+(instancetype)mapnik
{
	static AerialService * service = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		service = [AerialService aerialWithName:@"MapnikTiles"
											url:@"http://{switch:a,b,c}.tile.openstreetmap.org/{zoom}/{x}/{y}.png"
									   maxZoom:19
										roundUp:NO
										polygon:NULL];
	});
	return service;
}
+(instancetype)gpsTrace
{
	static AerialService * service = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		service = [AerialService aerialWithName:@"OSM GPS Traces"
											url:@"https://gps-{switch:a,b,c}.tile.openstreetmap.org/lines/{zoom}/{x}/{y}.png"
										maxZoom:20
										roundUp:NO
										polygon:NULL];
	});
	return service;
}
+(instancetype)mapboxLocator
{
	static AerialService * service = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		service = [AerialService aerialWithName:@"Mapbox Locator"
											url:@"http://{switch:a,b,c}.tiles.mapbox.com/v4/openstreetmap.map-inh76ba2/{zoom}/{x}/{y}.png?access_token=pk.eyJ1Ijoib3BlbnN0cmVldG1hcCIsImEiOiJhNVlHd29ZIn0.ti6wATGDWOmCnCYen-Ip7Q"
										maxZoom:20
										roundUp:NO
										polygon:NULL];
	});
	return service;
}



-(NSDictionary *)dictionary
{
	return @{ @"name" : _name,
			  @"url" : _url,
			  @"zoom" : @(_maxZoom),
			  @"roundUp" : @(_roundZoomUp)
			  };
}
-(instancetype)initWithDictionary:(NSDictionary *)dict
{
	NSString * url = dict[@"url"];

	// convert a saved aerial that uses a subdomain list to the new format
	NSArray * subdomains = dict[@"subdomains"];
	if ( subdomains.count > 0 ) {
		NSString * s = [subdomains componentsJoinedByString:@","];
		s = [NSString stringWithFormat:@"{switch:%@}",s];
		url = [url stringByReplacingOccurrencesOfString:@"{t}" withString:s];
	}
	// convert {z} to {zoom}
	url = [url stringByReplacingOccurrencesOfString:@"{z}" withString:@"{zoom}"];

	return [self initWithName:dict[@"name"] url:url maxZoom:[dict[@"zoom"] integerValue] roundUp:[dict[@"roundUp"] boolValue] polygon:NULL];
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
		[self fetchOsmLabAerials:^{

		}];
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
									   url:@"http://{switch:a,b,c}.tiles.mapbox.com/v4/openstreetmap.map-inh7ifmo/{zoom}/{x}/{y}.png?access_token=pk.eyJ1Ijoib3BlbnN0cmVldG1hcCIsImEiOiJhNVlHd29ZIn0.ti6wATGDWOmCnCYen-Ip7Q"
								   	maxZoom:19
								   roundUp:YES
								   polygon:NULL],
#if 0
			 [AerialService aerialWithName:@"MapQuest Open Aerial"
									   url:@"http://otile{switch:1,2,3,4}.mqcdn.com/tiles/1.0.0/sat/{zoom}/{x}/{y}.png"
								   maxZoom:20
								   roundUp:YES
								   polygon:NULL],
#endif
			 ];
}

-(void)fetchOsmLabAerials:(void (^)(void))completion
{
	NSString * urlString = @"https://raw.githubusercontent.com/osmlab/editor-layer-index/gh-pages/imagery.json";
	NSURL * downloadUrl = [NSURL URLWithString:urlString];
	NSURLSessionDataTask * downloadTask = [[NSURLSession sharedSession] dataTaskWithURL:downloadUrl completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
		id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
		if ( json ) {
			NSMutableArray * externalAerials = [NSMutableArray new];
			for ( NSDictionary * entry in json ) {
				if ( [entry[@"overlay"] integerValue] ) {
					// we don't support overlays yet
					continue;
				}

				CGPathRef polygon = NULL;
				NSArray * polygonPoints = entry[@"extent"][@"polygon"];
				if ( polygonPoints ) {
					CGMutablePathRef	path		= CGPathCreateMutable();

					for ( NSArray * loop in polygonPoints ) {
						BOOL	first		= YES;
						for ( NSArray * pt in loop ) {
							double lon = [pt[0] doubleValue];
							double lat = [pt[1] doubleValue];
							if ( first ) {
								CGPathMoveToPoint(path, NULL, lon, lat);
								first = NO;
							} else {
								CGPathAddLineToPoint(path, NULL, lon, lat);
							}
						}
						CGPathCloseSubpath( path );
					}
					polygon = CGPathCreateCopy( path );
					CGPathRelease( path );
				}
				NSString * name = entry[@"name"];
				NSString * url = entry[@"url"];
				NSInteger maxZoom = [entry[@"extent"][@"max_zoom"] integerValue];
				AerialService * service = [AerialService aerialWithName:name url:url maxZoom:maxZoom roundUp:YES polygon:polygon];
				[externalAerials addObject:service];
			}
			[externalAerials sortUsingComparator:^NSComparisonResult( AerialService * obj1, AerialService * obj2) {
				return [obj1.name caseInsensitiveCompare:obj2.name];
			}];
			dispatch_async(dispatch_get_main_queue(), ^{
				[_list addObjectsFromArray:externalAerials];
			});

		}
  	}];
	[downloadTask resume];
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
