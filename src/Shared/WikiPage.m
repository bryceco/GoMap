//
//  WikiPage.m
//  Go Map!!
//
//  Created by Bryce Cogswell on 5/26/20.
//  Copyright © 2020 Bryce. All rights reserved.
//

#import "WikiPage.h"

@implementation WikiPage

+(instancetype)shared
{
	static WikiPage * g_shared;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		g_shared = [WikiPage new];
	});
	return g_shared;
}

- (NSString *)wikiLanguageForLanguageCode:(NSString *)code
{
	if ( code.length == 0 ) {
		return @"";
	}
	NSDictionary * special = @{
		@"en" : @"",
		@"de" : @"DE:",
		@"es" : @"ES:",
		@"fr" : @"FR:",
		@"it" : @"IT:",
		@"ja" : @"JA:",
		@"nl" : @"NL:",
		@"ru" : @"RU:",
		@"zh-CN" : @"Zh-hans:",
		@"zh-HK" : @"Zh-hant:",
		@"zh-TW" : @"Zh-hant:",
	};
	NSString * result =  special[ code ];
	if ( result )
		return result;

	result = [[[code substringToIndex:1].uppercaseString stringByAppendingString:[code substringFromIndex:1]] stringByAppendingString:@":"];
	return result;
}

- (void)ifUrlExists:(NSURL *)url completion:(void (^)(BOOL exists))completion
{
	NSMutableURLRequest * request = [[NSMutableURLRequest alloc] initWithURL:url];
	request.HTTPMethod = @"HEAD";
	request.cachePolicy = NSURLRequestReturnCacheDataElseLoad;
	NSURLSessionDownloadTask * task = [[NSURLSession sharedSession] downloadTaskWithRequest:request
																		  completionHandler:^(NSURL *purl, NSURLResponse *response, NSError *error) {
		BOOL exists = NO;
		if ( error == nil ) {
			NSHTTPURLResponse * httpResponse = (NSHTTPURLResponse *)response;
			switch ( httpResponse.statusCode ) {
				case 200:
				case 301:
				case 302:
					exists = YES;
			}
		}
		completion( exists );
	}];
	[task resume];
}

- (void)bestWikiPageForKey:(NSString *)tagKey
					 value:(NSString *)tagValue
				  language:(NSString *)language
				completion:(void (^)(NSURL * url))completion
{
	language = [self wikiLanguageForLanguageCode:language];

	NSMutableArray * pageList = [NSMutableArray new];

	tagKey   = [tagKey stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
	tagValue = [tagValue stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];

	// key+value
	if ( tagValue.length ) {
		// exact language
		[pageList addObject:[NSString stringWithFormat:@"%@Tag:%@=%@",language,tagKey,tagValue]];
		if ( language.length )
			[pageList addObject:[NSString stringWithFormat:@"Tag:%@=%@",tagKey,tagValue]];
	}
	[pageList addObject:[NSString stringWithFormat:@"%@Key:%@",language,tagKey]];
	if ( language.length )
		[pageList addObject:[NSString stringWithFormat:@"Key:%@",tagKey]];

	NSMutableDictionary * urlDict = [NSMutableDictionary new];

	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{

		dispatch_group_t group = dispatch_group_create();
		NSURL * baseURL = [NSURL URLWithString:@"https://wiki.openstreetmap.org/wiki/"];

		for ( NSString * page in pageList ) {
			NSURL * url = [baseURL URLByAppendingPathComponent:page];
			if ( url == nil ) {
				continue;
			}
			dispatch_group_enter( group );
			[self ifUrlExists:url completion:^(BOOL exists) {
				if ( exists ) {
					dispatch_async(dispatch_get_main_queue(), ^{
						urlDict[ page ] = url;
					});
				}
				dispatch_group_leave( group );
			}];
		}
		dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

		dispatch_async(dispatch_get_main_queue(), ^{
			for ( NSString * page in pageList ) {
				NSURL * url = urlDict[ page ];
				if ( url ) {
					completion( url );
					return;
				}
			}
			completion( nil );
		});
	});

#if 0
	// query wiki metadata for which pages match
	NSURLComponents * urlComponents = [[NSURLComponents alloc] initWithString:@"https://wiki.openstreetmap.org/w/api.php?action=wbgetentities&sites=wiki&languages=en&format=json"];
	NSURLQueryItem * newItem = [NSURLQueryItem queryItemWithName:@"titles" value:titles];
	urlComponents.queryItems = [urlComponents.queryItems arrayByAddingObject:newItem];
	NSURLRequest * request = [[NSURLRequest alloc] initWithURL:urlComponents.URL];
	NSURLSessionDataTask * task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {

		if ( error == nil && data.length ) {
			@try {
				id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
				NSDictionary * entitiesDict = json[@"entities"];
				[entitiesDict enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull name, NSDictionary * _Nonnull entityDict, BOOL * _Nonnull stop) {
					NSDictionary * claims = entityDict[@"claims"];
					for ( id lang in claims[@"P31"] ) {
						NSDictionary * value = lang[ @"mainsnak" ][ @"datavalue" ][ @"value" ];
						NSString * pageTitle = value[ @"text" ];
						NSString * pageLanguage = value[ @"language" ];
						NSLog(@"%@ = %@",pageLanguage, pageTitle);
					}
				}];
			} @catch (NSException *exception) {
			} @finally {
			}
		}
		completion( error );
	}];
	[task resume];
#endif
}

@end
