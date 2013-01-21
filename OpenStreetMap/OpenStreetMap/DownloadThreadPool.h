//
//  DownloadThreads.h
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 11/7/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <Foundation/Foundation.h>

@class ConnectionState;

@interface DownloadAgent : NSObject <NSURLConnectionDataDelegate, NSStreamDelegate>
-(NSInputStream *)stream;
-(NSURLResponse *)response;
-(NSData *)dataHeader;
@end

@interface DownloadThreadPool : NSObject
{
	NSInteger				_maxConnections;
	dispatch_queue_t		_queue;
	dispatch_semaphore_t	_connectionSemaphore;
}


+(DownloadThreadPool *)osmPool;
+(DownloadThreadPool *)generalPool;

+(void)setUserAgent:(NSString *)userAgent;

-(void)dataForUrl:(NSString *)url completion:(void(^)(NSData * data,NSError * error))completion;
-(void)dataForUrl:(NSString *)url completeOnMain:(BOOL)completeOnMain completion:(void(^)(NSData * data,NSError * error))completion;
-(void)dataForUrl:(NSString *)url partialCallback:(void(^)(NSData *))partialCallback completion:(void(^)(NSURLResponse * response, NSError * error))completion;
-(void)streamForUrl:(NSString *)url callback:(void(^)(DownloadAgent *))callback;

@end
