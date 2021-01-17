//
//  CustomAerial.m
//  Go Map!!
//
//  Created by Bryce Cogswell on 8/21/14.
//  Copyright (c) 2014 Bryce Cogswell. All rights reserved.
//

#import "iosapi.h"
#import "AerialList.h"
#import "aes.h"
#import <CommonCrypto/CommonDigest.h>

static NSString * CUSTOMAERIALLIST_KEY = @"AerialList";
static NSString * CUSTOMAERIALSELECTION_KEY = @"AerialListSelection";
static NSString * RECENTLY_USED_KEY = @"AerialListRecentlyUsed";

#define BING_IDENTIFIER	 			@"BingIdentifier"
#define MAPNIK_IDENTIFIER			@"MapnikIdentifier"
#define OSM_GPS_TRACE_IDENTIFIER	@"OsmGpsTraceIdentifier"
#define MAPBOX_LOCATOR_IDENTIFIER	@"MapboxLocatorIdentifier"
#define NO_NAME_IDENTIFIER          @"No Name Identifier"
#define MAXAR_PREMIUM_IDENTIFIER	@"Maxar-Premium"
#define MAXAR_STANDARD_IDENTIFIER	@"Maxar-Standard"



@implementation AerialService

@synthesize placeholderImage = _placeholderImage;

+(NSArray<NSString *> *)supportedProjections
{
	static NSArray<NSString *> * list = nil;
	if ( list == nil ) {
		list = @[
			@"EPSG:3857",
			@"EPSG:4326",
			@"EPSG:900913",
			@"EPSG:3587",
			@"EPSG:54004",
			@"EPSG:41001",
			@"EPSG:102113",
			@"EPSG:102100",
			@"EPSG:3785"
		];
	}
	return list;
}

-(instancetype)initWithName:(NSString *)name
				 identifier:(NSString *)identifier
						url:(NSString *)url
					maxZoom:(NSInteger)maxZoom
					roundUp:(BOOL)roundUp
				  startDate:(NSString *)startDate
					endDate:(NSString *)endDate
			  wmsProjection:(NSString *)projection
					polygon:(CGPathRef)polygon
			   attribString:(NSString *)attribString
				 attribIcon:(UIImage *)attribIcon
				  attribUrl:(NSString *)attribUrl
{
	self = [super init];
	if ( self ) {
		// normalize URLs
		url = [url stringByReplacingOccurrencesOfString:@"{ty}" withString:@"{-y}"];
		url = [url stringByReplacingOccurrencesOfString:@"{zoom}" withString:@"{z}"];

		_name				= name ?: @"";
		_identifier			= identifier;
		_url				= url ?: @"";
		_maxZoom			= (int32_t)maxZoom ?: 21;
		_roundZoomUp 		= roundUp;
		_startDate			= startDate;
		_endDate			= endDate;
		_wmsProjection		= projection;
		_polygon			= CGPathCreateCopy( polygon );
		_attributionString 	= attribString.length ? attribString : name;
		_attributionIcon	= attribIcon;
		_attributionUrl		= attribUrl;
	}
	return self;
}

+(instancetype)aerialWithName:(NSString *)name
				   identifier:(NSString *)identifier
						  url:(NSString *)url
					  maxZoom:(NSInteger)maxZoom
					  roundUp:(BOOL)roundUp
					startDate:(NSString *)startDate
					  endDate:(NSString *)endDate
				wmsProjection:(NSString *)projection
					  polygon:(CGPathRef)polygon
				 attribString:(NSString *)attribString
				   attribIcon:(UIImage *)attribIcon
					attribUrl:(NSString *)attribUrl
{
	return [[AerialService alloc] initWithName:name
									identifier:identifier
										   url:url
									   maxZoom:maxZoom
									   roundUp:roundUp
									 startDate:startDate
									   endDate:endDate
								 wmsProjection:projection
									   polygon:polygon
								  attribString:attribString
									attribIcon:attribIcon
									 attribUrl:attribUrl];
}

-(BOOL)isBingAerial
{
	return [self.identifier isEqualToString:BING_IDENTIFIER];
}
-(BOOL)isMapnik
{
	return [self.identifier isEqualToString:MAPNIK_IDENTIFIER];
}
-(BOOL)isOsmGpxOverlay
{
	return [self.identifier isEqualToString:OSM_GPS_TRACE_IDENTIFIER];
}
-(BOOL)isMaxar
{
	return [self.identifier isEqualToString:MAXAR_PREMIUM_IDENTIFIER] ||
		   [self.identifier isEqualToString:MAXAR_STANDARD_IDENTIFIER];
}


+(NSDate *)dateFromString:(NSString *)string
{
	static NSArray * formatterList;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		NSDateFormatter * formatterYYYYMMDD = [NSDateFormatter new];
		formatterYYYYMMDD.dateFormat = @"yyyy-MM-dd";
		formatterYYYYMMDD.timeZone	 = [NSTimeZone timeZoneForSecondsFromGMT:0];

		NSDateFormatter * formatterYYYYMM = [NSDateFormatter new];
		formatterYYYYMM.dateFormat = @"yyyy-MM";
		formatterYYYYMM.timeZone	 = [NSTimeZone timeZoneForSecondsFromGMT:0];

		NSDateFormatter * formatterYYYY = [NSDateFormatter new];
		formatterYYYY.dateFormat = @"yyyy";
		formatterYYYY.timeZone	 = [NSTimeZone timeZoneForSecondsFromGMT:0];

		formatterList = @[
			formatterYYYYMMDD,
			formatterYYYYMM,
			formatterYYYY
		];
	});
	if ( string == nil )
		return nil;
	for ( NSDateFormatter * formatter in formatterList ) {
		NSDate * date = [formatter dateFromString:string];
		if ( date )
			return date;
	}
	return nil;
}


+(AerialService *)defaultBingAerial
{
	static AerialService * bing = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		bing = [AerialService aerialWithName:@"Bing Aerial"
								  identifier:BING_IDENTIFIER
										 url:@"https://ecn.{switch:t0,t1,t2,t3}.tiles.virtualearth.net/tiles/a{u}.jpeg?g=587&key=" BING_MAPS_KEY
									 maxZoom:21
									 roundUp:YES
								   startDate:nil
									 endDate:nil
								  wmsProjection:nil
									 polygon:NULL
								attribString:@""
								  attribIcon:[UIImage imageNamed:@"bing-logo-white"]
								   attribUrl:nil];
	});
	return bing;
}


+(AerialService *)maxarPremiumAerial
{
	static AerialService * service = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		NSString * url = @"eZ5AGZGcRQyKahl/+UTyIm+vENuJECB4Hvu4ytCzjBoCBDeRMbsOkaQ7zD5rUAYfRDaQwnQRiqE4lj0KYTenPe1d1spljlcYgvYRsqjEtYp6AhCoBPO4Rz6d0Z9enlPqPj7KCvxyOcB8A/+3HkYjpMGMEcvA6oeSX9I0RH/PS9lQzmJACnINv3lFIonIZ1gY/yFVqi2FWnWCbTyFdy2+FlyrWqTfyeG8tstR+5wQsC+xmsaCmW8e41jROh1O0z+U";
		service = [AerialService aerialWithName:@"Maxar Premium Aerial"
								  identifier:MAXAR_PREMIUM_IDENTIFIER
										 url:[aes decryptString:url]
									 maxZoom:21
									 roundUp:YES
									  startDate:nil
									 endDate:nil
								  wmsProjection:nil
									 polygon:NULL
								attribString:@"Maxar Premium"
								  attribIcon:nil
								   attribUrl:@"https://wiki.openstreetmap.org/wiki/DigitalGlobe"];

		[service loadIconFromWeb:@"https://osmlab.github.io/editor-layer-index/sources/world/Maxar.png"];
	});
	return service;
}

+(AerialService *)maxarStandardAerial
{
	static AerialService * service = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		NSString * url = @"eZ5AGZGcRQyKahl/+UTyIm+vENuJECB4Hvu4ytCzjBoCBDeRMbsOkaQ7zD5rUAYfRDaQwnQRiqE4lj0KYTenPe1d1spljlcYgvYRsqjEtYp6AhCoBPO4Rz6d0Z9enlPqPj7KCvxyOcB8A/+3HkYjpMGMEcvA6oeSX9I0RH/PS9mdAZEC5TmU3odUJQ0hNzczrKtUDmNujrTNfFVHhZZWPLEVZUC9cE94VF/AJkoIigdmXooJ+5UcPtH/uzc6NbOb";
		service = [AerialService aerialWithName:@"Maxar Standard Aerial"
								  identifier:MAXAR_STANDARD_IDENTIFIER
										 url:[aes decryptString:url]
									 maxZoom:21
									 roundUp:YES
								   startDate:nil
									 endDate:nil
								  wmsProjection:nil
									 polygon:NULL
								attribString:@"Maxar Standard"
								  attribIcon:nil
								   attribUrl:@"https://wiki.openstreetmap.org/wiki/DigitalGlobe"];
		[service loadIconFromWeb:@"https://osmlab.github.io/editor-layer-index/sources/world/Maxar.png"];
	});
	return service;
}

+(instancetype)mapnik
{
	static AerialService * service = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		service = [AerialService aerialWithName:@"MapnikTiles"
									 identifier:MAPNIK_IDENTIFIER
											url:@"https://{switch:a,b,c}.tile.openstreetmap.org/{z}/{x}/{y}.png"
									   maxZoom:19
										roundUp:NO
									  startDate:nil
										endDate:nil
									 wmsProjection:nil
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
											url:@"https://gps-{switch:a,b,c}.tile.openstreetmap.org/lines/{z}/{x}/{y}.png"
										maxZoom:20
										roundUp:NO
									  startDate:nil
										endDate:nil
									 wmsProjection:nil
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
											url:@"https://api.mapbox.com/styles/v1/openstreetmap/ckasmteyi1tda1ipfis6wqhuq/tiles/256/{zoom}/{x}/{y}{@2x}?access_token=pk.eyJ1Ijoib3BlbnN0cmVldG1hcCIsImEiOiJjaml5MjVyb3MwMWV0M3hxYmUzdGdwbzE4In0.q548FjhsSJzvXsGlPsFxAQ"
										maxZoom:20
										roundUp:NO
									  startDate:nil
										endDate:nil
									 wmsProjection:nil
										polygon:NULL
								   attribString:nil
									 attribIcon:nil
									  attribUrl:nil];
	});
	return service;
}
+(instancetype)noName
{
    static AerialService * service = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        service = [AerialService aerialWithName:@"QA Poole No Name"
                                     identifier:NO_NAME_IDENTIFIER
                                            url:@"https://tile{switch:2,3}.poole.ch/noname/{zoom}/{x}/{y}.png"
                                        maxZoom:25
                                        roundUp:NO
										startDate:nil
										endDate:nil
                                  wmsProjection:nil
                                        polygon:NULL
                                   attribString:nil
                                     attribIcon:nil
                                      attribUrl:nil];
    });
    return service;
}

-(NSDictionary *)dictionary
{
	return @{ @"name" 		: _name,
			  @"url" 		: _url,
			  @"zoom" 		: @(_maxZoom),
			  @"roundUp" 	: @(_roundZoomUp),
			  @"projection"	: _wmsProjection ?: @""
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

	NSString * projection = dict[@"projection"];
	if ( projection.length == 0 )
		projection = nil;

	return [self initWithName:dict[@"name"]
				   identifier:url
						  url:url
					  maxZoom:[dict[@"zoom"] integerValue]
					  roundUp:[dict[@"roundUp"] boolValue]
					startDate:nil
					  endDate:nil
				wmsProjection:projection
					  polygon:NULL
				 attribString:nil
				   attribIcon:nil
					attribUrl:nil];
}


-(NSString *)metadataUrl
{
	if ( self.isBingAerial ) {
		return @"https://dev.virtualearth.net/REST/V1/Imagery/Metadata/Aerial/%f,%f?zl=%d&include=ImageryProviders&key=" BING_MAPS_KEY;
	}
	return nil;
}
-(NSData *)placeholderImage
{
	if ( _placeholderImage ) {
		return _placeholderImage.length ? _placeholderImage : nil;
	}
	NSString * name = nil;
	if ( self.isBingAerial ) {
		name = @"BingPlaceholderImage";
	} else if ( [_identifier isEqualToString:@"EsriWorldImagery"] ) {
		name = @"EsriPlaceholderImage";
	}
	if ( name ) {
		NSString * path = [[NSBundle mainBundle] pathForResource:name ofType:@"png"];
		if ( path == nil )
			path = [[NSBundle mainBundle] pathForResource:name ofType:@"jpg"];
		NSData * data = [NSData dataWithContentsOfFile:path];
		if ( data.length ) {
			dispatch_sync(dispatch_get_main_queue(), ^{
				_placeholderImage = data;
			});
		}
		return _placeholderImage;
	}
	_placeholderImage = [NSData new];
	return nil;
}

-(void)scaleAttributionIconToHeight:(CGFloat)height
{
	if ( _attributionIcon && fabs(_attributionIcon.size.height - height) > 0.1 ) {
		CGFloat scale = _attributionIcon.size.height / height;
#if TARGET_OS_IPHONE
		CGSize size = _attributionIcon.size;
		size.height /= scale;
		size.width  /= scale;
		UIGraphicsBeginImageContext(size);
		[_attributionIcon drawInRect:CGRectMake(0.0, 0.0, size.width, size.height)];
		UIImage * imageCopy = UIGraphicsGetImageFromCurrentImageContext();
		UIGraphicsEndImageContext();
		_attributionIcon = imageCopy;
#else
		NSSize size = { _attributionIcon.size.width * scale, _attributionIcon.size.height * scale };
		NSImage * result = [[NSImage alloc] initWithSize:size];
		[result lockFocus];
		NSAffineTransform * transform = [NSAffineTransform transform];
		[transform scaleBy:scale];
		[transform concat];
		[_attributionIcon drawAtPoint:NSZeroPoint fromRect:NSZeroRect operation:NSCompositingOperationCopy fraction:1.0];
		[result unlockFocus];
		_attributionIcon = result;
#endif
	}
}

-(void)loadIconFromWeb:(NSString *)url
{
	NSURLRequest * request = [NSURLRequest requestWithURL:[NSURL URLWithString:url]
											  cachePolicy:NSURLRequestReturnCacheDataElseLoad
										  timeoutInterval:60];
	NSURLSessionDataTask * task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData * data, NSURLResponse * response, NSError * error) {
		if ( data ) {
			UIImage * image = [[NSImage alloc] initWithData:data];
			dispatch_async(dispatch_get_main_queue(), ^{
				_attributionIcon = image;
			});
		}
	}];
	[task resume];
}

-(NSString *)description
{
	return self.name;
}

@end



@implementation AerialList

@synthesize currentAerial = _currentAerial;

-(instancetype)init
{
	self = [super init];
	if ( self ) {
		[self fetchOsmLabAerials:^{
			// if a non-builtin aerial service is current then we need to select it once the list is loaded
			[self load];
		}];
	}
	return self;
}

-(NSArray *)builtinServices
{
	return @[
			 [AerialService defaultBingAerial]
		 ];
}

-(NSArray *)userDefinedServices
{
	return _userDefinedList;
}


-(NSString *)pathToExternalAerialsCache
{
	// get tile cache folder
	NSArray *paths = NSSearchPathForDirectoriesInDomains( NSCachesDirectory, NSUserDomainMask, YES );
	if ( paths.count ) {
		NSString * bundleName = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleIdentifier"];
		NSString * path = [[paths[0]
							stringByAppendingPathComponent:bundleName]
						   stringByAppendingPathComponent:@"OSM Aerial Providers.json"];
		[[NSFileManager defaultManager] createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:NULL error:NULL];
		return path;
	}
	return nil;
}


-(void)addPoints:(NSArray *)points toPath:(CGMutablePathRef)path
{
	BOOL first = YES;
	for ( NSArray * pt in points ) {
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

-(NSArray *)processOsmLabAerialsList:(NSArray *)featureArray isGeoJSON:(BOOL)isGeoJSON
{
	if ( ![featureArray isKindOfClass:[NSArray class]] )
		return nil;

	NSDictionary * categories = @{
		@"photo" 		: @YES,
		@"elevation" 	: @YES
	};

	NSDictionary * supportedTypes = @{
		@"tms" 			: @YES,
		@"wms" 			: @YES,
		@"scanex" 		: @NO,
		@"wms_endpoint" : @NO,
		@"wmts" 		: @NO,
		@"bing" 		: @NO,
	};

	NSSet * supportedProjections = [NSSet setWithArray:AerialService.supportedProjections];

	NSMutableArray * externalAerials = [NSMutableArray new];
	for ( NSDictionary * entry in featureArray ) {

		@try {

			if ( isGeoJSON && ![entry[@"type"] isEqualToString:@"Feature"] ) {
				NSLog(@"Aerial: skipping type %@", entry[@"type"]);
				continue;
			}
			NSDictionary * properties = isGeoJSON ? entry[@"properties"] : entry;
			NSString * 	name 				= properties[@"name"];
			if ( [name hasPrefix:@"Maxar "] ) {
				// we special case their imagery because they require a special key
				continue;
			}
			NSString * 	identifier			= properties[@"id"];
			NSString *  category			= properties[@"category"];
			if ( categories[category] == nil ) {
				// NSLog(@"category %@ - %@",category,identifier);
				continue;
			}
			NSString *	startDateString		= properties[@"start_date"];
			NSString *	endDateString		= properties[@"end_date"];
			NSDate 	 *  endDate   = [AerialService dateFromString:endDateString];
			if ( endDate && [endDate timeIntervalSinceNow] < -20*365.0*24*60*60 )
				continue;
			NSString * 	type 				= properties[@"type"];
			NSArray  *	projections			= properties[@"available_projections"];
			NSString * 	url 				= properties[@"url"];
			NSInteger 	maxZoom 			= isGeoJSON ? [properties[@"max_zoom"] integerValue] : [properties[@"extent"][@"max_zoom"] integerValue];
			NSString * 	attribIconString	= properties[@"icon"];
			NSString * 	attribString 		= properties[@"attribution"][@"text"];
			NSString * 	attribUrl 			= properties[@"attribution"][@"url"];
			NSInteger	overlay				= [properties[@"overlay"] integerValue];
			NSNumber * supported = supportedTypes[ type ];
			if ( supported == nil ) {
				NSLog(@"Aerial: unsupported type %@: %@\n",type,name);
				continue;
			} else if ( supported.boolValue == NO ) {
				continue;
			}
			if ( overlay ) {
				// we don@"t support overlays yet
				continue;
			}
			if ( !( [url hasPrefix:@"http:"] || [url hasPrefix:@"https:"]) ) {
				// invalid url
				NSLog(@"Aerial: bad url %@: %@\n",url,name);
				continue;
			}

			// we only support some types of WMS projections
			NSString * projection = nil;
			if ( [type isEqualToString:@"wms"] ) {
				for ( NSString * proj in projections ) {
					if ( [supportedProjections containsObject:proj] ) {
						projection = proj;
						break;
					}
				}
				if ( projection == nil )
					continue;
			}

			NSArray  * 	polygonPoints 		= nil;
			BOOL		isMultiPolygon		= NO;	// a GeoJSON multipolygon, which has an extra layer of nesting
			if ( isGeoJSON ) {
				NSDictionary * 	geometry = entry[@"geometry"];
				if ( [geometry isKindOfClass:[NSDictionary class]] ) {
					polygonPoints = geometry[@"coordinates"];
					isMultiPolygon = [geometry[@"type"] isEqualToString:@"MultiPolygon"];
				}
			} else {
				polygonPoints = properties[@"extent"][@"polygon"];
			}

			CGPathRef polygon = NULL;
			if ( polygonPoints ) {
				CGMutablePathRef path = CGPathCreateMutable();
				if ( isMultiPolygon ) {
					for ( NSArray * outer in polygonPoints ) {
						for ( NSArray * loop in outer ) {
							[self addPoints:loop toPath:path];
						}
					}
				} else {
					for ( NSArray * loop in polygonPoints ) {
						[self addPoints:loop toPath:path];
					}
				}
				polygon = CGPathCreateCopy( path );
				CGPathRelease( path );
			}

			UIImage * attribIcon = nil;
			BOOL httpIcon = NO;
			if ( attribIconString.length > 0 ) {
				NSArray * prefixList = @[ @"data:image/png;base64,",
										  @"data:image/png:base64,",
										  @"png:base64," ];
				for ( NSString * prefix in prefixList ) {
					if ( [attribIconString hasPrefix:prefix] ) {
						attribIconString = [attribIconString substringFromIndex:prefix.length];
						NSData * decodedData = [[NSData alloc] initWithBase64EncodedString:attribIconString options:0];
						attribIcon = [[UIImage alloc] initWithData:decodedData];
						if ( attribIcon == nil ) {
							NSLog(@"bad icon decode: %@\n",attribIconString);
						}
						break;
					}
				}
				if ( attribIcon == nil ) {
					if ( [attribIconString hasPrefix:@"http"] ) {
						httpIcon = YES;
					} else {
						NSLog(@"Aerial: unsupported icon format in %@: %@\n",name,attribIconString);
					}
				}
			}

			// support for {apikey}
			if ( [url containsString:@"{apikey}"] ) {
				NSString * apikey = nil;
				if ( [url containsString:@".thunderforest.com/"] ) {
					apikey = @"be3dc024e3924c22beb5f841d098a8a3";	// Please don't use in other apps. Sign up for a free account at Thunderforest.com insead.
				} else {
					NSLog(@"*** Aerial needs {apikey): %@",name);
					continue;
				}
				url = [url stringByReplacingOccurrencesOfString:@"{apikey}" withString:apikey];
			}

			AerialService * service = [AerialService aerialWithName:name identifier:identifier url:url maxZoom:maxZoom roundUp:YES startDate:startDateString endDate:endDateString wmsProjection:projection polygon:polygon attribString:attribString attribIcon:attribIcon attribUrl:attribUrl];
			[externalAerials addObject:service];
			CGPathRelease( polygon );

			if ( httpIcon ) {
				[service loadIconFromWeb:attribIconString];
			}
		} @catch (id exception) {
			NSLog(@"*** Aerial skipped\n");
		}
	}
	[externalAerials sortUsingComparator:^NSComparisonResult( AerialService * obj1, AerialService * obj2) {
		return [obj1.name caseInsensitiveCompare:obj2.name];
	}];
	return [NSArray arrayWithArray:externalAerials];	// return immutable copy
}

-(NSArray *)processOsmLabAerialsData:(NSData *)data
{
	if ( data == nil || data.length == 0 )
		return nil;

	@try {
		id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
		if ( json == nil )
			return nil;
		if ( [json isKindOfClass:[NSArray class]] ) {
			// unversioned (old ELI) variety
			return [self processOsmLabAerialsList:json isGeoJSON:NO];
		} else {
			NSDictionary * meta = json[@"meta"];
			if ( meta == nil ) {
				// josm variety
			} else {
				// new ELI variety
				NSString * formatVersion = meta[@"format_version"];
				if ( ![formatVersion isEqualToString:@"1.0"] )
					return nil;
				NSString * metaType = json[@"type"];
				if ( ![metaType isEqualToString:@"FeatureCollection"] )
					return nil;
			}
			NSArray * features = json[@"features"];
			return [self processOsmLabAerialsList:features isGeoJSON:YES];
		}
	} @catch (id exception) {
		return nil;
	}
}


-(void)fetchOsmLabAerials:(void (^)(void))completion
{
	// get cached data
	NSData * cachedData = [NSData dataWithContentsOfFile:[self pathToExternalAerialsCache]];
	NSDate * now = [NSDate date];
	_lastDownloadDate = [[NSUserDefaults standardUserDefaults] objectForKey:@"lastImageryDownloadDate"];
	if ( cachedData == nil || (_lastDownloadDate && [now timeIntervalSinceDate:_lastDownloadDate] >= 60*60*24*7) ) {
		// download newer version periodically
		NSString * urlString = @"https://josm.openstreetmap.de/maps?format=geojson";
		//NSString * urlString = @"https://osmlab.github.io/editor-layer-index/imagery.geojson";
		NSURL * downloadUrl = [NSURL URLWithString:urlString];
		NSURLSessionDataTask * downloadTask = [[NSURLSession sharedSession] dataTaskWithURL:downloadUrl completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
			[[NSUserDefaults standardUserDefaults] setObject:now forKey:@"lastImageryDownloadDate"];
			NSArray * externalAerials = [self processOsmLabAerialsData:data];
			if ( externalAerials.count > 100 ) {
				// cache download for next time
				[data writeToFile:[self pathToExternalAerialsCache] options:NSDataWritingAtomic error:NULL];
				// notify caller of update
				dispatch_async(dispatch_get_main_queue(), ^{
					self->_downloadedList = externalAerials;
					completion();
				});
			}
		}];
	   	[downloadTask resume];
		_lastDownloadDate = now;
	}

   	// read cached version
	NSArray * externalAerials = [self processOsmLabAerialsData:cachedData];
	self->_downloadedList = externalAerials;
	completion();
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

	// fetch and decode recently used list
	NSMutableDictionary * dict = [NSMutableDictionary new];
	for ( AerialService * service in _downloadedList ) {
		dict[service.identifier] = service;
	}
	for ( AerialService * service in _userDefinedList ) {
		dict[service.identifier] = service;
	}
	for ( AerialService * service in @[[AerialService maxarPremiumAerial], [AerialService maxarStandardAerial] ] ) {
		dict[service.identifier] = service;
	}

	NSArray * recentIdentiers = [defaults objectForKey:RECENTLY_USED_KEY] ?: @[];
	_recentlyUsed = [NSMutableArray arrayWithCapacity:recentIdentiers.count];
	for ( NSString * identifier in recentIdentiers ) {
		AerialService * service = dict[identifier];
		if ( service ) {
			[_recentlyUsed addObject:service];
		}
	}

	NSString * currentIdentifier = [defaults objectForKey:CUSTOMAERIALSELECTION_KEY];
	if ( currentIdentifier == nil || [currentIdentifier isKindOfClass:[NSNumber class]] ) {
		currentIdentifier = BING_IDENTIFIER;
	}
	NSArray * a = [[self.builtinServices arrayByAddingObjectsFromArray:self.userDefinedServices] arrayByAddingObjectsFromArray:_downloadedList];
	for ( AerialService * service in a ) {
		if ( [currentIdentifier isEqualToString:service.identifier] ) {
			self.currentAerial = service;
			break;
		}
	}
	if ( _currentAerial == nil ) {
		self.currentAerial = self.builtinServices[0];
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

	NSMutableArray * recents = [NSMutableArray new];
	for ( AerialService * service in _recentlyUsed ) {
		[recents addObject:service.identifier];
	}
	[defaults setObject:recents forKey:RECENTLY_USED_KEY];
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
	[result addObject: [AerialService maxarPremiumAerial]];
	[result addObject: [AerialService maxarStandardAerial]];

	[result sortUsingComparator:^NSComparisonResult(AerialService * _Nonnull obj1, AerialService * _Nonnull obj2) {
		return [obj1.name compare:obj2.name];
	}];
	return result;
}

-(AerialService *)currentAerial
{
	return _currentAerial;
}
-(void)setCurrentAerial:(AerialService *)currentAerial
{
	_currentAerial = currentAerial;

	// update recently used
	const NSInteger MAX_ITEMS = 6;
	[_recentlyUsed removeObject:currentAerial];
	[_recentlyUsed insertObject:currentAerial atIndex:0];
	while ( _recentlyUsed.count > MAX_ITEMS ) {
		[_recentlyUsed removeLastObject];
	}
}

-(NSArray<AerialService *> *)recentlyUsed
{
	return _recentlyUsed;
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
		self.currentAerial = self.builtinServices[0];
	}
	[_recentlyUsed removeObject:s];
}

@end
