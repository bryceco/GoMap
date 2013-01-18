//
//  DownloadThreads.h
//  OpenStreetMap
//
//  Created by Bryce on 11/7/12.
//  Copyright (c) 2012 Bryce. All rights reserved.
//

#import <Foundation/Foundation.h>

@class ConnectionState;

@interface DownloadThreadPool : NSObject
{
	NSInteger				_maxConnections;
	dispatch_queue_t		_queue;
	dispatch_semaphore_t	_connectionSemaphore;
	int32_t					_pendingCount;
}
@property (strong,nonatomic)	NSMutableSet	*	downloadSet;


+(DownloadThreadPool *)osmPool;
+(DownloadThreadPool *)generalPool;

+(void)setUserAgent:(NSString *)userAgent;

-(void)dataForUrl:(NSString *)url completion:(void(^)(NSData * data,NSError * error))completion;
-(void)dataForUrl:(NSString *)url completeOnMain:(BOOL)completeOnMain completion:(void(^)(NSData * data,NSError * error))completion;

@end
