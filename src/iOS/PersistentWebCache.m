//
//  PersistentWebCache.m
//  Go Map!!
//
//  Created by Bryce on 5/3/20.
//  Copyright © 2020 Bryce. All rights reserved.
//

#include <sys/stat.h>

#import "DLog.h"
#import "PersistentWebCache.h"

@implementation PersistentWebCache

-(instancetype)initWithName:(NSString *)name memorySize:(NSInteger)memorySize
{
	name = [name stringByReplacingOccurrencesOfString:@"/" withString:@"_"];

	_memoryCache = [NSCache new];
	_memoryCache.countLimit = 10000;
	_memoryCache.totalCostLimit = memorySize;

	_pending = [NSMutableDictionary new];

	NSArray * paths = NSSearchPathForDirectoriesInDomains( NSCachesDirectory, NSUserDomainMask, YES );
	if ( [paths count] ) {
		NSString * bundleName = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleIdentifier"];
		_cacheDirectory = [[paths.firstObject stringByAppendingPathComponent:bundleName] stringByAppendingPathComponent:name];
		[[NSFileManager defaultManager] createDirectoryAtPath:_cacheDirectory withIntermediateDirectories:YES attributes:NULL error:NULL];
	} else {
		return nil;
	}
	return self;
}

-(NSArray *)allFiles
{
	return [[NSFileManager defaultManager] contentsOfDirectoryAtPath:_cacheDirectory error:NULL];
}

-(void)removeAllObjects
{
	for ( NSString * file in self.allFiles ) {
		NSString * path = [_cacheDirectory stringByAppendingPathComponent:file];
		[[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
	}
	[_memoryCache removeAllObjects];
}

-(void)removeObjectsAsyncOlderThan:(NSDate *)expiration
{
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
		for ( NSString * file in self.allFiles ) {
			NSString * path = [_cacheDirectory stringByAppendingPathComponent:file];
			struct stat status = { 0 };
			stat( path.fileSystemRepresentation, &status );
			NSDate * date = [NSDate dateWithTimeIntervalSince1970:status.st_mtimespec.tv_sec];
			if ( [date compare:expiration] < 0 ) {
				[[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
				dispatch_async(dispatch_get_main_queue(), ^{
					[_memoryCache removeObjectForKey:file];
				});
			}
		}
	});
}

-(void)diskCacheSize:(NSInteger *)pSize count:(NSInteger *)pCount
{
	NSInteger size = 0;
	NSArray * files = self.allFiles;
	for ( NSString * file in files ) {
		NSString * path = [_cacheDirectory stringByAppendingPathComponent:file];
		struct stat status = { 0 };
		stat( path.fileSystemRepresentation, &status );
		size += (status.st_size + 511) & -512;
	}
	*pSize  = size;
	*pCount = files.count;
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

	void (^gotData)(NSData * data) = ^(NSData * data){
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
	};

	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^(void){

		// check disk cache
		NSString * filePath = [_cacheDirectory stringByAppendingPathComponent:cacheKey];
		NSData * fileData = [[NSData alloc] initWithContentsOfFile:filePath];
		if ( fileData ) {
			gotData( fileData );
		} else {
			// fetch from server
			NSURL * url = [NSURL URLWithString:urlFunction()];
			NSURLRequest * request = [NSURLRequest requestWithURL:url];
			NSURLSessionDataTask * task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData * data, NSURLResponse * response, NSError * error) {
				gotData(data);
				dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
					[data writeToFile:filePath atomically:YES];
				});
			}];
			[task resume];
		}
	});
	return nil;
}

@end
