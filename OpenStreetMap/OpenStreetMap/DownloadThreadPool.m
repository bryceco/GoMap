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


#define SHOW_PROGRESS 1

@interface Download : NSObject <NSURLConnectionDataDelegate>
{
	NSURLConnection		*	_connection;
	NSMutableData		*	_data;
	NSHTTPURLResponse	*	_response;
	void				(^	_completion)(NSURLResponse * response, NSData * data, NSError * error);
}
@end
@implementation Download
-(id)initWithRequest:(NSURLRequest *)request
{
	self = [super init];
	if ( self ) {
		_connection	= [[NSURLConnection alloc] initWithRequest:request delegate:self startImmediately:NO];
		[_connection setDelegateQueue:[NSOperationQueue new]];
		_data		= [NSMutableData new];
	}
	return self;
}
-(void)startWithCompletionHandler:(void(^)(NSURLResponse * response, NSData * data, NSError * error))completion
{
	_completion = completion;
	[_connection start];
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
	_response = (id)response;
	[_data setLength:0];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
	[_data appendData:data];
//	DLog(@"received %d bytes",data.length);
}
- (void)connection:(NSURLConnection *)connection didSendBodyData:(NSInteger)bytesWritten totalBytesWritten:(NSInteger)totalBytesWritten totalBytesExpectedToWrite:(NSInteger)totalBytesExpectedToWrite
{
	DLog(@"upload %d/%d", (int)totalBytesWritten, (int)totalBytesExpectedToWrite);
}
- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
	_completion( _response, _data, error );
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
	_completion( _response, _data, nil );
}
@end


@implementation DownloadThreadPool

static NSString * g_UserAgent = nil;

-(id)initWithMaxConnections:(NSInteger)max
{
	self = [super init];
	if ( self ) {
		_maxConnections			= max;
		_queue					= dispatch_queue_create("openstreetmap.DownloadQueue", DISPATCH_QUEUE_SERIAL );
		_connectionSemaphore	= dispatch_semaphore_create( _maxConnections );
		_pendingCount			= 0;
#if SHOW_PROGRESS
		_downloadSet			= [NSMutableSet new];
#endif
	}
	return self;
}

+(void)setUserAgent:(NSString *)userAgent
{
	g_UserAgent = [userAgent copy];
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


-(void)dataForUrl:(NSString *)url completeOnMain:(BOOL)completeOnMain completion:(void(^)(NSData * data,NSError * error))completion
{
	OSAtomicIncrement32(&_pendingCount);
	dispatch_async(_queue, ^{

		dispatch_semaphore_wait( _connectionSemaphore, DISPATCH_TIME_FOREVER );

		NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:url]];
		[request setHTTPMethod:@"GET"];
		[request addValue:@"8bit" forHTTPHeaderField:@"Content-Transfer-Encoding"];

		if ( g_UserAgent ) {
			[request setValue:g_UserAgent forHTTPHeaderField:@"User-Agent"];
		}

#if SHOW_PROGRESS
		Download * download = [[Download alloc] initWithRequest:request];
		@synchronized( _downloadSet) {
			[_downloadSet addObject:download];
		}
		[download startWithCompletionHandler:^(NSURLResponse * response, NSData * data, NSError * error) {
#else
		[NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue new] completionHandler:^(NSURLResponse * response, NSData * data, NSError * error) {
#endif
			OSAtomicDecrement32(&_pendingCount);
			dispatch_semaphore_signal( _connectionSemaphore );

			@synchronized( _downloadSet ) {
				[_downloadSet removeObject:download];
			}

			NSHTTPURLResponse * httpResponse = (id)response;
			if ( error ) {
				DLog(@"Error: %@", error.localizedDescription);
				data = nil;
			} else if ( httpResponse.statusCode >= 400 ) {
				DLog(@"HTTP error %ld: %@", (long)httpResponse.statusCode, [NSHTTPURLResponse localizedStringForStatusCode:httpResponse.statusCode] );
				NSString * text = [[NSString alloc] initWithBytes:data.bytes length:data.length encoding:NSUTF8StringEncoding];
#if !TARGET_OS_IPHONE
				if ( [text hasPrefix:@"<html>" ] ) {
					NSXMLDocument * doc = [[NSXMLDocument alloc] initWithXMLString:text options:0 error:nil];
					NSArray * a = [doc nodesForXPath:@"./html/body/p" error:nil];
					if ( a.count ) {
						text = [a.lastObject stringValue];
					}
				}
#endif
				error = [NSError errorWithDomain:@"HTTP" code:httpResponse.statusCode userInfo:@{ NSLocalizedDescriptionKey:text}];
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
	});
}

-(void)dataForUrl:(NSString *)url completion:(void(^)(NSData * data,NSError * error))completion
{
	[self dataForUrl:url completeOnMain:YES completion:completion];
}

@end
