//
//  PersistentWebCache.h
//  Go Map!!
//
//  Created by Bryce on 5/3/20.
//  Copyright © 2020 Bryce. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PersistentWebCache : NSObject
{
	NSURL 				*	_cacheDirectory;
	NSCache				* 	_memoryCache;
	NSMutableDictionary	*	_pending;		// track objects we're already downloading so we don't issue multiple requests
}

-(instancetype)initWithName:(NSString *)name memorySize:(NSInteger)memorySize;

-(id _Nullable)objectWithKey:(NSString * _Nonnull)cacheKey
				 fallbackURL:(NSURL *(^_Nonnull)(void))url
			   objectForData:(id(^)(NSData *_Nullable))objectForData
				  completion:(void(^_Nonnull)(id))completion;

-(void)removeAllObjects;
-(void)removeObjectsAsyncOlderThan:(NSDate *_Nonnull)expiration;
-(void)getDiskCacheSize:(NSInteger *_Nonnull)pSize count:(NSInteger *_Nonnull)pCount;
-(NSArray<NSString *> *)allKeys;
@end

NS_ASSUME_NONNULL_END
