//
//  PersistentWebCache.m
//  Go Map!!
//
//  Created by Bryce on 5/3/20.
//  Copyright © 2020 Bryce. All rights reserved.
//

#import "DLog.h"
#import "PersistentWebCache.h"

@implementation PersistentWebCache

+(NSString *)encodeKeyForFilesystem:(NSString *)string
{
	NSCharacterSet * allowed = [[NSCharacterSet characterSetWithCharactersInString:@"/"] invertedSet];
	string = [string stringByAddingPercentEncodingWithAllowedCharacters:allowed];
	return string;
}

-(NSDirectoryEnumerator<NSURL *> *)fileEnumeratorWithAttributes:(NSArray *)attr
{
	return [[NSFileManager defaultManager] enumeratorAtURL:_cacheDirectory
								includingPropertiesForKeys:attr
												   options:NSDirectoryEnumerationSkipsSubdirectoryDescendants|NSDirectoryEnumerationSkipsPackageDescendants|NSDirectoryEnumerationSkipsHiddenFiles
											  errorHandler:NULL];
}

-(NSArray *)allKeys
{
	NSMutableArray * a = [NSMutableArray new];
	for ( NSURL * url in [self fileEnumeratorWithAttributes:nil] ) {
		NSString * s = url.lastPathComponent;	// automatically removes escape encoding
		[a addObject:s];
	}
	return a;
}

-(instancetype)initWithName:(NSString *)name memorySize:(NSInteger)memorySize
{
	if ( self = [super init] ) {
		name = [PersistentWebCache encodeKeyForFilesystem:name];

		_memoryCache = [NSCache new];
		_memoryCache.countLimit = 10000;
		_memoryCache.totalCostLimit = memorySize;

		_pending = [NSMutableDictionary new];

		NSString * bundleName = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleIdentifier"];
		_cacheDirectory = [[[[NSFileManager defaultManager] URLForDirectory:NSCachesDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:NULL] URLByAppendingPathComponent:bundleName isDirectory:YES] URLByAppendingPathComponent:name isDirectory:YES];
		[[NSFileManager defaultManager] createDirectoryAtURL:_cacheDirectory withIntermediateDirectories:YES attributes:nil error:NULL];
	}
	return self;
}

-(void)removeAllObjects
{
	for ( NSURL * url in [self fileEnumeratorWithAttributes:nil] ) {
		[[NSFileManager defaultManager] removeItemAtURL:url error:NULL];
	}
	[_memoryCache removeAllObjects];
}

-(void)removeObjectsAsyncOlderThan:(NSDate *)expiration
{
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
		for ( NSURL * url in [self fileEnumeratorWithAttributes:@[NSURLContentModificationDateKey]] ) {
			NSDate * date = nil;
			if ( ![url getResourceValue:&date forKey:NSURLContentModificationDateKey error:NULL]
				|| [date compare:expiration] < 0 )
			{
				[[NSFileManager defaultManager] removeItemAtURL:url error:NULL];
			}
		}
	});
}

-(void)diskCacheSize:(NSInteger *)pSize count:(NSInteger *)pCount
{
	NSInteger count = 0;
	NSInteger size = 0;
	for ( NSURL * url in [self fileEnumeratorWithAttributes:@[NSURLFileAllocatedSizeKey]] ) {
		NSNumber * len = nil;
		[url getResourceValue:&len forKey:NSURLFileAllocatedSizeKey error:NULL];
		count ++;
		size += len.integerValue;
	}
	*pSize  = size;
	*pCount = count;
}

-(id)objectWithKey:(NSString *)cacheKey
	   fallbackURL:(NSString *(^)(void))urlFunction
	 objectForData:(id(^)(NSData * data))objectForData
		completion:(void(^)(id object))completion
{
	DbgAssert( [NSThread isMainThread] );

	id cachedObject = [_memoryCache objectForKey:cacheKey];
	if ( cachedObject ) {
		return cachedObject;
	}

	NSMutableArray * plist = _pending[ cacheKey ];
	if ( plist ) {
		// already being downloaded
		[plist addObject:completion];
		return nil;
	}
	_pending[cacheKey] = [NSMutableArray arrayWithObject:completion];

	BOOL (^gotData)(NSData * data) = ^BOOL(NSData * data){
		id obj = objectForData ? objectForData(data) : data;
		dispatch_async(dispatch_get_main_queue(), ^{
			if ( obj ) {
				[_memoryCache setObject:obj forKey:cacheKey cost:data.length];
			}
			NSArray * completionList = _pending[ cacheKey ];
			for ( void(^innerCompletion)(id) in completionList ) {
				innerCompletion( obj );
			}
			[_pending removeObjectForKey:cacheKey];
		});
		return obj != nil;
	};

	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^(void){
		// check disk cache
		NSString * fileName = [PersistentWebCache encodeKeyForFilesystem:cacheKey];
		NSURL * filePath = [_cacheDirectory URLByAppendingPathComponent:fileName];
		NSData * fileData = [[NSData alloc] initWithContentsOfURL:filePath];
		if ( fileData ) {
			gotData( fileData );
		} else {
			// fetch from server
			NSURL * url = [NSURL URLWithString:urlFunction()];
			NSURLRequest * request = [NSURLRequest requestWithURL:url];
			NSURLSessionDataTask * task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData * data, NSURLResponse * response, NSError * error) {
				if ( gotData(data) ) {
					dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
						[data writeToURL:filePath atomically:YES];
					});
				}
			}];
			[task resume];
		}
	});
	return nil;
}

@end
