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

-(id)initWithMaxConnections:(NSInteger)max
{
	self = [super init];
	if ( self ) {
		NSURLSessionConfiguration * config = [NSURLSessionConfiguration defaultSessionConfiguration];
		// config.HTTPMaximumConnectionsPerHost = max;	// use iOS defaults for now (4)
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
		pool = [[DownloadThreadPool alloc] initWithMaxConnections:2];
	});
	return pool;
}

+(DownloadThreadPool *)generalPool;
{
	static dispatch_once_t		onceToken = 0;
	static DownloadThreadPool * pool = nil;

	dispatch_once( &onceToken, ^{
		pool = [[DownloadThreadPool alloc] initWithMaxConnections:5];
	});
	return pool;
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data
{
	[data enumerateByteRangesUsingBlock:^(const void * _Nonnull bytes, NSRange byteRange, BOOL * _Nonnull stop) {
	}];
	NSLog(@"download partial data\n");
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(nullable NSError *)error
{
	NSLog(@"download complete\n");
}


-(void)dataForUrl:(NSString *)url completeOnMain:(BOOL)completeOnMain completion:(void(^)(NSData * data,NSError * error))completion
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
		
		if ( completeOnMain ) {
			dispatch_async(dispatch_get_main_queue(), ^{
				completion(data,error);
			});
		} else {
			completion(data,error);
		}
	}];
	[task resume];
}

-(void)dataForUrl:(NSString *)url completion:(void(^)(NSData * data,NSError * error))completion
{
	[self dataForUrl:url completeOnMain:YES completion:completion];
}

-(void)streamForUrl:(NSString *)url callback:(void(^)(NSInputStream * stream,NSError * error))callback
{
	[self dataForUrl:url completeOnMain:NO completion:^(NSData *data, NSError *error) {
		if ( data && !error ) {
			NSInputStream * inputStream = [NSInputStream inputStreamWithData:data];
			callback(inputStream,error);
		} else {
			callback(nil,error);
		}
	}];
}


-(void)cancelAllDownloads
{
	@synchronized(self) {
		[_urlSession getTasksWithCompletionHandler:^(NSArray *dataTasks, NSArray *uploadTasks, NSArray *downloadTasks) {
			for (NSURLSessionTask *task in dataTasks) {
				[task cancel];
			}
		}];
	}
}

-(NSInteger)downloadsInProgress
{
	return _downloadCount;
}

@end
