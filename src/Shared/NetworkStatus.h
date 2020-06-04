//
//  NetworkStatus.m
//  Go Map!!
//
//  Created by Bryce Cogswell on 5/13/18.
//  Copyright © 2018 Bryce. All rights reserved.
//

#import <Foundation/Foundation.h>

extern NSString * NetworkStatusChangedNotification;

typedef enum : NSInteger {
	NetworkNone = 0,
	NetworkWiFi,
	NetworkCel
} NetworkConnectivity;


@interface NetworkStatus : NSObject

@property (readonly,assign)		uint32_t			currentFlags;
@property (readonly,nonatomic)	NetworkConnectivity	currentConnectivity;

+ (instancetype)networkStatusWithHostName:(NSString *)hostName;

- (BOOL)startNotifier;
- (void)stopNotifier;

- (BOOL)connectionRequired;
@end
