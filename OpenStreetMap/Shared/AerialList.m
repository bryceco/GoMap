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

#define BING_IDENTIFIER	 			@"BingIdentifier"
#define MAPNIK_IDENTIFIER			@"MapnikIdentifier"
#define OSM_GPS_TRACE_IDENTIFIER	@"OsmGpsTraceIdentifier"
#define MAPBOX_LOCATOR_IDENTIFIER	@"MapboxLocatorIdentifier"



@implementation AerialService

-(instancetype)initWithName:(NSString *)name identifier:(NSString *)identifier url:(NSString *)url maxZoom:(NSInteger)maxZoom roundUp:(BOOL)roundUp polygon:(CGPathRef)polygon attribString:(NSString *)attribString attribIcon:(UIImage *)attribIcon attribUrl:(NSString *)attribUrl
{
	self = [super init];
	if ( self ) {
		_name				= name ?: @"";
		_identifier			= identifier;
		_url				= url ?: @"";
		_maxZoom			= (int32_t)maxZoom ?: 21;
		_roundZoomUp 		= roundUp;
		_polygon			= polygon;
		_attributionString 	= attribString;
		_attributionIcon	= attribIcon;
		_attributionUrl		= attribUrl;
	}
	return self;
}

+(instancetype)aerialWithName:(NSString *)name identifier:(NSString *)identifier url:(NSString *)url maxZoom:(NSInteger)maxZoom roundUp:(BOOL)roundUp polygon:(CGPathRef)polygon attribString:(NSString *)attribString attribIcon:(UIImage *)attribIcon attribUrl:(NSString *)attribUrl
{
	return [[AerialService alloc] initWithName:name identifier:identifier url:url maxZoom:maxZoom roundUp:roundUp polygon:polygon attribString:attribString attribIcon:attribIcon attribUrl:attribUrl];
}

-(BOOL)isBingAerial
{
	if ( [self.identifier isEqualToString:BING_IDENTIFIER] )
		return YES;
	return NO;
}

+(AerialService *)defaultBingAerial
{
	static AerialService * bing = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		bing = [AerialService aerialWithName:@"Bing Aerial"
								  identifier:BING_IDENTIFIER
										 url:@"http://ecn.{switch:t0,t1,t2,t3}.tiles.virtualearth.net/tiles/a{u}.jpeg?g=587&key=" BING_MAPS_KEY
									 maxZoom:21
									 roundUp:YES
									 polygon:NULL
								attribString:@""
								  attribIcon:[UIImage imageNamed:@"BingLogo.png"]
								   attribUrl:nil];
	});
	return bing;
}

+(instancetype)mapnik
{
	static AerialService * service = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		service = [AerialService aerialWithName:@"MapnikTiles"
									 identifier:MAPNIK_IDENTIFIER
											url:@"http://{switch:a,b,c}.tile.openstreetmap.org/{zoom}/{x}/{y}.png"
									   maxZoom:19
										roundUp:NO
										polygon:NULL
								   attribString:nil
									 attribIcon:nil
									  attribUrl:nil];
	});
	return service;
}
+(instancetype)gpsTrace
{
	static AerialService * service = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		service = [AerialService aerialWithName:@"OSM GPS Traces"
									 identifier:OSM_GPS_TRACE_IDENTIFIER
											url:@"https://gps-{switch:a,b,c}.tile.openstreetmap.org/lines/{zoom}/{x}/{y}.png"
										maxZoom:20
										roundUp:NO
										polygon:NULL
								   attribString:nil
									 attribIcon:nil
									  attribUrl:nil];
	});
	return service;
}
+(instancetype)mapboxLocator
{
	static AerialService * service = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		service = [AerialService aerialWithName:@"Mapbox Locator"
									 identifier:MAPBOX_LOCATOR_IDENTIFIER
											url:@"http://{switch:a,b,c}.tiles.mapbox.com/v4/openstreetmap.map-inh76ba2/{zoom}/{x}/{y}.png?access_token=pk.eyJ1Ijoib3BlbnN0cmVldG1hcCIsImEiOiJhNVlHd29ZIn0.ti6wATGDWOmCnCYen-Ip7Q"
										maxZoom:20
										roundUp:NO
										polygon:NULL
								   attribString:nil
									 attribIcon:nil
									  attribUrl:nil];
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

	return [self initWithName:dict[@"name"]
				   identifier:url
						  url:url
					  maxZoom:[dict[@"zoom"] integerValue]
					  roundUp:[dict[@"roundUp"] boolValue]
					  polygon:NULL
				 attribString:nil
				   attribIcon:nil
					attribUrl:nil];
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

-(void)scaleAttributionIconToHeight:(CGFloat)height
{
	if ( _attributionIcon && fabs(_attributionIcon.size.height - height) > 0.1 ) {
		CGFloat scale = _attributionIcon.size.height / height;
		_attributionIcon = [[UIImage alloc] initWithCGImage:_attributionIcon.CGImage scale:scale orientation:_attributionIcon.imageOrientation];
	}
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

-(NSArray *)builtinServices
{
	return @[
			 [AerialService defaultBingAerial],
		 ];
}

-(NSArray *)userDefinedServices
{
	return _userDefinedList;
}

-(void)fetchOsmLabAerials:(void (^)(void))completion
{
	NSString * urlString = @"https://raw.githubusercontent.com/osmlab/editor-layer-index/gh-pages/imagery.json";

	NSDate * now = [NSDate date];
	NSDate * lastDownload = [[NSUserDefaults standardUserDefaults] objectForKey:@"lastImageryDownloadDate"];
	if ( lastDownload && [now timeIntervalSinceDate:lastDownload] < 60*60*24*7 ) {
		// intentionally fail so we get cached version
		urlString = @"";
	}

	NSURL * downloadUrl = [NSURL URLWithString:urlString];
	NSURLSessionDataTask * downloadTask = [[NSURLSession sharedSession] dataTaskWithURL:downloadUrl completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
		if ( error )
			data = nil;
		id json = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
		if ( json == nil ) {
			// read cached version
			NSData * data2 = [[NSUserDefaults standardUserDefaults] objectForKey:@"lastImageryDownloadData"];
			json = [NSJSONSerialization JSONObjectWithData:data2 options:0 error:NULL];
		} else {
			// cache download for next time
			[[NSUserDefaults standardUserDefaults] setObject:now  forKey:@"lastImageryDownloadDate"];
			[[NSUserDefaults standardUserDefaults] setObject:data forKey:@"lastImageryDownloadData"];
		}

		if ( json ) {
			NSMutableArray * externalAerials = [NSMutableArray new];
			for ( NSDictionary * entry in json ) {
				NSString * url = entry[@"url"];
				NSString * name	 = entry[@"name"];
				NSString * identifier = entry[@"id"];
				NSInteger maxZoom = [entry[@"extent"][@"max_zoom"] integerValue];
				NSString * attribIconString = entry[@"icon"];
				NSString * attribString = entry[@"attribution"][@"text"];
				NSString * attribUrl = entry[@"attribution"][@"url"];

#if 0
				if ( [url containsString:@"{-y}"] ) {
					NSLog(@"%@ %@ %@\n",name,url,entry[@"extent"][@"polygon"] );
				}
#endif
				NSString * type = entry[@"type"];
				if ( !([type isEqualToString:@"tms"] || [type isEqualToString:@"wms"]) ) {
					NSLog(@"unsupported %@\n",type);
					continue;
				}
				if ( [entry[@"overlay"] integerValue] ) {
					// we don't support overlays yet
					continue;
				}
				if ( !( [url hasPrefix:@"http:"] || [url hasPrefix:@"https:"]) ) {
					// invalid url
					NSLog(@"skip url = %@\n",urlString);
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

				UIImage * attribIcon = nil;
				if ( attribIconString.length > 0 ) {
					NSArray * prefixList = @[ @"data:image/png;base64,",
											  @"data:image/png:base64,",
											  @"png:base64," ];
					for ( NSString * prefix in prefixList ) {
						if ( [attribIconString hasPrefix:prefix] ) {
							attribIconString = [attribIconString substringFromIndex:prefix.length];
							NSData * decodedData = [[NSData alloc] initWithBase64EncodedString:attribIconString options:0];
							attribIcon = [UIImage imageWithData:decodedData];
							if ( attribIcon == nil ) {
								NSLog(@"bad icon decode: %@\n",attribIconString);
							}
							break;
						}
					}
					if ( attribIcon == nil ) {
						if ( [attribIconString hasPrefix:@"http"] ) {
							// unsupported
						} else {
							NSLog(@"unsupported icon format: %@\n",attribIconString);
						}
					}
				}
				AerialService * service = [AerialService aerialWithName:name identifier:identifier url:url maxZoom:maxZoom roundUp:YES polygon:polygon attribString:attribString attribIcon:attribIcon attribUrl:attribUrl];
				[externalAerials addObject:service];
			}
			[externalAerials sortUsingComparator:^NSComparisonResult( AerialService * obj1, AerialService * obj2) {
				return [obj1.name caseInsensitiveCompare:obj2.name];
			}];
			dispatch_async(dispatch_get_main_queue(), ^{
				self->_downloadedList = [NSArray arrayWithArray:externalAerials];
			});
		}
  	}];
	[downloadTask resume];
}

-(void)load
{
	NSUserDefaults * defaults = [NSUserDefaults standardUserDefaults];
	_userDefinedList = [[defaults objectForKey:CUSTOMAERIALLIST_KEY] mutableCopy];
	if ( _userDefinedList.count == 0 ) {
		_userDefinedList = [NSMutableArray new];
	} else {
		for ( NSInteger i = 0; i < _userDefinedList.count; ++i ) {
			_userDefinedList[i] = [[AerialService alloc] initWithDictionary:_userDefinedList[i]];
		}
	}
	NSString * currentIdentifier = [defaults objectForKey:CUSTOMAERIALSELECTION_KEY];
	if ( currentIdentifier == nil || [currentIdentifier isKindOfClass:[NSNumber class]] ) {
		currentIdentifier = BING_IDENTIFIER;
	}
	NSArray * a = [[self.builtinServices arrayByAddingObjectsFromArray:self.userDefinedServices] arrayByAddingObjectsFromArray:_userDefinedList];
	for ( AerialService * service in a ) {
		if ( [currentIdentifier isEqualToString:service.identifier] ) {
			_currentAerial = service;
			break;
		}
	}
	if ( _currentAerial == nil ) {
		_currentAerial = self.builtinServices[0];
	}
}

-(void)save
{
	NSUserDefaults * defaults = [NSUserDefaults standardUserDefaults];
	NSMutableArray * a = [_userDefinedList mutableCopy];
	for ( NSInteger i = 0; i < a.count; ++i ) {
		a[i] = [a[i] dictionary];
	}
	[defaults setObject:a forKey:CUSTOMAERIALLIST_KEY];
	[defaults setObject:_currentAerial.identifier forKey:CUSTOMAERIALSELECTION_KEY];
}

-(NSArray *)servicesForRegion:(OSMRect)rect
{
	// find imagery relavent to the viewport
	CGPoint center = { rect.origin.x + rect.size.width/2, rect.origin.y + rect.size.height/2 };
	NSMutableArray * result = [NSMutableArray new];
	for ( AerialService * service in _downloadedList ) {
		if ( service.polygon == NULL || CGPathContainsPoint(service.polygon, NULL, center, NO ) ) {
			[result addObject:service];
		}
	}
	return result;
}

-(NSInteger)count
{
	return _userDefinedList.count;
}

-(AerialService *)serviceAtIndex:(NSUInteger)index
{
	return [_userDefinedList objectAtIndex:index];
}

-(void)addUserDefinedService:(AerialService *)service atIndex:(NSInteger)index
{
	[_userDefinedList insertObject:service atIndex:index];
}

-(void)removeUserDefinedServiceAtIndex:(NSInteger)index
{
	if ( index >= _userDefinedList.count )
		return;
	AerialService * s = _userDefinedList[index];
	[_userDefinedList removeObjectAtIndex:index];
	if ( s == _currentAerial ) {
		_currentAerial = self.builtinServices[0];
	}
}

@end
