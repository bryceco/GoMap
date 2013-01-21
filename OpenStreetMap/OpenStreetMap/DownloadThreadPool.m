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

static NSString * g_UserAgent = nil;

typedef void (^dequeueBlock)(void);


@implementation DownloadAgent
{
	NSOperationQueue	*	_operationQueue;
	NSURLConnection		*	_connection;
	NSURLResponse		*	_response;

	void				(^	_partialCallback)(NSData *);
	void				(^	_completionCallback)(NSURLResponse * response, NSError * error);
	void				(^	_dequeue)(void);

	// stream interface
	void				(^	_streamCallback)(DownloadAgent *);
	NSInputStream		*	_readStream;
	NSOutputStream		*	_writeStream;
	NSMutableData		*	_data;
	NSData				*	_dataHeader;
	NSInteger				_downloadBytes;
}

-(NSInputStream *)stream
{
	return _readStream;
}
-(NSURLResponse *)response
{
	return _response;
}
-(NSData *)dataHeader
{
	return nil;
}


-(void)cleanupAndDealloc
{
	if ( _writeStream ) {
		[_writeStream close];
		_writeStream = nil;
	}
	if ( _dequeue ) {
		_dequeue();
		_dequeue		= nil;
	}
	_connection			= nil;
	_partialCallback	= nil;
	_completionCallback = nil;
}

-(void)dealloc
{
}

-(id)initWithURL:(NSURL *)url partialCallback:(void(^)(NSData *))particalCallback completionCallback:(void(^)(NSURLResponse * response, NSError * error))completionCallback
{
	self = [super init];
	if ( self ) {

		_operationQueue = [[NSOperationQueue alloc] init];
		_operationQueue.maxConcurrentOperationCount = 1;

		NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];
		[request setHTTPMethod:@"GET"];
		[request addValue:@"8bit" forHTTPHeaderField:@"Content-Transfer-Encoding"];

		if ( g_UserAgent ) {
			[request setValue:g_UserAgent forHTTPHeaderField:@"User-Agent"];
		}

		_connection	= [[NSURLConnection alloc] initWithRequest:request delegate:self startImmediately:NO];
		[_connection setDelegateQueue:_operationQueue];

		_partialCallback = particalCallback;
		_completionCallback = completionCallback;
	}
	return self;
}

-(id)initWithURL:(NSURL *)url streamCallback:(void(^)(DownloadAgent *))streamCallback
{
	self = [self initWithURL:url partialCallback:^(NSData * partial) {
		
			assert( [NSOperationQueue currentQueue] == _operationQueue );
			[_data appendData:partial];
			if ( _dataHeader == nil )
				_dataHeader = partial;
			_downloadBytes += partial.length;
			NSInteger len = [_writeStream write:_data.bytes maxLength:_data.length];
			if ( len > 0 ) {
				[_data replaceBytesInRange:NSMakeRange(0,len) withBytes:NULL length:0];
			}

		} completionCallback:^(NSURLResponse *response, NSError *error) {

			assert( [NSOperationQueue currentQueue] == _operationQueue );
			NSHTTPURLResponse * httpResponse = (id)response;
			if ( error == nil && [httpResponse isKindOfClass:[NSHTTPURLResponse class]] && httpResponse.statusCode >= 400 ) {
				error = [NSError errorWithDomain:@"HTTP" code:httpResponse.statusCode userInfo:@{ NSLocalizedDescriptionKey:[NSString stringWithFormat:@"HTTP error %d",httpResponse.statusCode]}];
			}
		}];


	_data = [NSMutableData data];
	CFReadStreamRef		cfReadStream;
	CFWriteStreamRef	cfWriteStream;
	CFStreamCreateBoundPair( NULL, &cfReadStream, &cfWriteStream, 64*1024 );
	_readStream		= (__bridge id)cfReadStream;
	_writeStream	= (__bridge id)cfWriteStream;
	_streamCallback = streamCallback;

	[_writeStream setDelegate:self];
	[_writeStream scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
	[_writeStream open];

	return self;
}

-(void)startWithDequeue:(void(^)(void))dequeue
{
	_dequeue = dequeue;

	assert( _partialCallback && _completionCallback );

	if ( _streamCallback ) {
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
			_streamCallback( self );
		});
	}

	[_connection start];
}

#pragma mark Connection delegate methods

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
	_response = response;
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
	assert( [NSOperationQueue currentQueue] == _operationQueue );
	_partialCallback( data );
}

- (void)connection:(NSURLConnection *)connection didSendBodyData:(NSInteger)bytesWritten totalBytesWritten:(NSInteger)totalBytesWritten totalBytesExpectedToWrite:(NSInteger)totalBytesExpectedToWrite
{
	DLog(@"upload %d/%d", (int)totalBytesWritten, (int)totalBytesExpectedToWrite);
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
	_connection	= nil;
	_completionCallback( _response, error );
	[self cleanupAndDealloc];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
	assert( _operationQueue == [NSOperationQueue currentQueue] );

	_connection	= nil;
	_completionCallback( _response, nil );
	if ( _writeStream  &&  _data.length == 0 ) {
		[_writeStream close];
		_writeStream = nil;
	}
	if ( _writeStream == nil ) {
		[self cleanupAndDealloc];
	}
}

#pragma mark Stream delegate method

- (void)stream:(NSStream *)stream handleEvent:(NSStreamEvent)eventCode
{
	switch ( eventCode ) {
		case NSStreamEventHasSpaceAvailable:
		{
			assert( stream == _writeStream );
			[_operationQueue addOperationWithBlock:^{
				assert( [NSOperationQueue currentQueue] == _operationQueue );
				if ( _data.length ) {
					NSInteger len = [_writeStream write:_data.bytes maxLength:_data.length];
					if ( len > 0 ) {
						[_data replaceBytesInRange:NSMakeRange(0,len) withBytes:NULL length:0];
					}
				}
				// check if we're finished
				if (  _connection == nil  &&  _data.length == 0 ) {
					[_writeStream close];
					[self cleanupAndDealloc];
				}
			}];
			break;
		}
			
		default:
			break;
	}
}

@end


@implementation DownloadThreadPool

-(id)initWithMaxConnections:(NSInteger)max
{
	self = [super init];
	if ( self ) {
		_maxConnections			= max;
		_queue					= dispatch_queue_create("openstreetmap.DownloadQueue", DISPATCH_QUEUE_SERIAL );
		_connectionSemaphore	= dispatch_semaphore_create( _maxConnections );
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
		pool = [[DownloadThreadPool alloc] initWithMaxConnections:1];	// FIXME
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



-(void)submitBlockToQueue:(void(^)(dequeueBlock))block
{
	dispatch_async(_queue, ^{
		dispatch_semaphore_wait( _connectionSemaphore, DISPATCH_TIME_FOREVER );
		block( ^{
			dispatch_semaphore_signal( _connectionSemaphore );
		});
	});
}


-(void)dataForUrl:(NSString *)url partialCallback:(void(^)(NSData *))partialCallback completion:(void(^)(NSURLResponse * response, NSError * error))completion
{
	[self submitBlockToQueue:^(dequeueBlock dequeue){
		DownloadAgent * download = [[DownloadAgent alloc] initWithURL:[NSURL URLWithString:url]
													  partialCallback:^( NSData * data ) {
														  partialCallback( data );
													  }
												   completionCallback:^( NSURLResponse * response, NSError * error ) {
													   completion( response, error );
												   }];
		[download startWithDequeue:dequeue];
	}];
}


-(void)streamForUrl:(NSString *)url callback:(void(^)(DownloadAgent *))callback
{
	[self submitBlockToQueue:^(dequeueBlock dequeue){
		DownloadAgent * download = [[DownloadAgent alloc] initWithURL:[NSURL URLWithString:url] streamCallback:callback];
		[download startWithDequeue:dequeue];
	}];
}


-(void)dataForUrl:(NSString *)url completeOnMain:(BOOL)completeOnMain completion:(void(^)(NSData * data,NSError * error))completion
{
	__block NSMutableData * data = [NSMutableData new];

	[self dataForUrl:url partialCallback:^(NSData * partial) {
		[data appendData:partial];
	} completion:^(NSURLResponse *response, NSError *error) {
		NSHTTPURLResponse * httpResponse = (id)response;
		if ( error ) {
			DLog(@"Error: %@", error.localizedDescription);
			data = nil;
		} else if ( [httpResponse isKindOfClass:[NSHTTPURLResponse class]] && httpResponse.statusCode >= 400 ) {
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
}

-(void)dataForUrl:(NSString *)url completion:(void(^)(NSData * data,NSError * error))completion
{
	[self dataForUrl:url completeOnMain:YES completion:completion];
}

@end
