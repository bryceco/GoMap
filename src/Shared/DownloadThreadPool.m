//
//  DownloadThreads.m
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 11/7/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#include <libkern/OSAtomic.h>

#import "DLog.h"
#import "DownloadThreadPool.h"

@implementation DownloadThreadPool

-(id)init
{
	self = [super init];
	if ( self ) {
		NSURLSessionConfiguration * config = [NSURLSessionConfiguration defaultSessionConfiguration];
		_urlSession	= [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:nil];
		_downloadCount = 0;
	}
	return self;
}

+(DownloadThreadPool *)osmPool;
{
	static dispatch_once_t		onceToken = 0;
	static DownloadThreadPool * pool = nil;

	dispatch_once( &onceToken, ^{
		pool = [[DownloadThreadPool alloc] init];
	});
	return pool;
}

-(void)streamForUrl:(NSString *)url callback:(void(^)(NSInputStream * stream,NSError * error))callback
{
	NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:url]];
	[request setHTTPMethod:@"GET"];
	[request addValue:@"8bit" forHTTPHeaderField:@"Content-Transfer-Encoding"];
	[request setCachePolicy:NSURLRequestReloadIgnoringLocalCacheData];

	OSAtomicIncrement32(&_downloadCount);

	NSURLSessionDataTask * task = [_urlSession dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
		OSAtomicDecrement32(&_downloadCount);

		NSHTTPURLResponse * httpResponse = (id)response;
		if ( error ) {
			DLog(@"Error: %@", error.localizedDescription);
			data = nil;
		} else if ( [httpResponse isKindOfClass:[NSHTTPURLResponse class]] && httpResponse.statusCode >= 400 ) {
			DLog(@"HTTP error %ld: %@", (long)httpResponse.statusCode, [NSHTTPURLResponse localizedStringForStatusCode:httpResponse.statusCode] );
			DLog(@"URL: %@", url );
			NSString * text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
			if ( text.length == 0 )
				text = [NSHTTPURLResponse localizedStringForStatusCode:httpResponse.statusCode];
			error = [NSError errorWithDomain:@"HTTP" code:httpResponse.statusCode userInfo:@{ NSLocalizedDescriptionKey:text?:@""}];
			data = nil;
		}

		if ( data && !error ) {
			NSInputStream * inputStream = [NSInputStream inputStreamWithData:data];
			callback(inputStream,nil);
		} else {
			callback(nil,error);
		}
	}];
	[task resume];
}

-(void)cancelAllDownloads
{
	[_urlSession getAllTasksWithCompletionHandler:^(NSArray<__kindof NSURLSessionTask *> * _Nonnull tasks) {
		for ( NSURLSessionTask * task in tasks ) {
			[task cancel];
		}
	}];
}

-(NSInteger)downloadsInProgress
{
	return _downloadCount;
}

@end
