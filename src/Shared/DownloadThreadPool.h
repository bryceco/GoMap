//
//  DownloadThreads.h
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 11/7/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <Foundation/Foundation.h>
#include <stdatomic.h>

@class ConnectionState;

@interface DownloadThreadPool : NSObject <NSURLSessionDataDelegate,NSURLSessionTaskDelegate>
{
	atomic_int			_downloadCount;
	NSURLSession	*	_urlSession;
}

+(DownloadThreadPool *)osmPool;

-(void)streamForUrl:(NSString *)url callback:(void(^)(NSInputStream * stream,NSError * error))callback;

-(void)cancelAllDownloads;
-(NSInteger)downloadsInProgress;

@end
