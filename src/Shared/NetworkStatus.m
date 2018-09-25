//
//  NetworkStatus.m
//  Go Map!!
//
//  Created by Bryce Cogswell on 5/13/18.
//  Copyright © 2018 Bryce. All rights reserved.
//

#import <arpa/inet.h>
#import <ifaddrs.h>
#import <netdb.h>
#import <sys/socket.h>
#import <netinet/in.h>

#import <CoreFoundation/CoreFoundation.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import <netinet/in.h>

#import "NetworkStatus.h"

#pragma mark IPv6 Support

NSString * NetworkStatusChangedNotification = @"NetworkStatusChangedNotification";


#pragma mark - Supporting functions

#define kShouldPrintReachabilityFlags 1

static void PrintReachabilityFlags(SCNetworkReachabilityFlags flags, const char* comment)
{
#if kShouldPrintReachabilityFlags
	NSLog(@"Reachability Flag Status: %c%c %c%c%c%c%c%c%c %s\n",
#if TARGET_OS_IPHONE
		  (flags & kSCNetworkReachabilityFlagsIsWWAN)               ? 'W' : '-',
#else
		  '-',
#endif
		  (flags & kSCNetworkReachabilityFlagsReachable)            ? 'R' : '-',
		  
		  (flags & kSCNetworkReachabilityFlagsTransientConnection)  ? 't' : '-',
		  (flags & kSCNetworkReachabilityFlagsConnectionRequired)   ? 'c' : '-',
		  (flags & kSCNetworkReachabilityFlagsConnectionOnTraffic)  ? 'C' : '-',
		  (flags & kSCNetworkReachabilityFlagsInterventionRequired) ? 'i' : '-',
		  (flags & kSCNetworkReachabilityFlagsConnectionOnDemand)   ? 'D' : '-',
		  (flags & kSCNetworkReachabilityFlagsIsLocalAddress)       ? 'l' : '-',
		  (flags & kSCNetworkReachabilityFlagsIsDirect)             ? 'd' : '-',
		  comment
		  );
#endif
}

#pragma mark - Reachability implementation

@implementation NetworkStatus
{
	SCNetworkReachabilityRef 	_reachabilityRef;
}

@synthesize currentFlags = _currentFlags;

+ (instancetype)networkStatusWithHostName:(NSString *)hostName
{
	SCNetworkReachabilityRef reachability = SCNetworkReachabilityCreateWithName( NULL, hostName.UTF8String );
	if ( reachability ) {
		NetworkStatus * object = [[self alloc] init];
		if ( object )	{
			object->_reachabilityRef = reachability;
			[object startNotifier];
			return object;
		}
		CFRelease( reachability );
	}
	return nil;
}

#pragma mark - Start and stop notifier

static void NetworkStatusCallback( SCNetworkReachabilityRef target, SCNetworkReachabilityFlags flags, void * info )
{
#pragma unused (target)
	NetworkStatus * myself = (__bridge NetworkStatus *)info;
	assert( [myself isKindOfClass:[NetworkStatus class]] );
	
	myself->_currentFlags = flags;
	[[NSNotificationCenter defaultCenter] postNotificationName:NetworkStatusChangedNotification object:myself];
}

- (BOOL)startNotifier
{
	SCNetworkReachabilityContext context = { 0, (__bridge void *)self, NULL, NULL, NULL };
	if ( SCNetworkReachabilitySetCallback( _reachabilityRef, NetworkStatusCallback, &context ) ) {
		if ( SCNetworkReachabilityScheduleWithRunLoop( _reachabilityRef, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode ) ) {
			return YES;
		}
	}
	return NO;
}

- (void)stopNotifier
{
	if ( _reachabilityRef ) {
		SCNetworkReachabilityUnscheduleFromRunLoop( _reachabilityRef, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode );
	}
}

- (void)dealloc
{
	[self stopNotifier];
	if ( _reachabilityRef )	{
		CFRelease( _reachabilityRef );
	}
}


#pragma mark - Network Flag Handling

+(NetworkConnectivity)networkStatusForFlags:(SCNetworkReachabilityFlags)flags
{
	PrintReachabilityFlags(flags, "networkStatusForFlags");
	if ((flags & kSCNetworkReachabilityFlagsReachable) == 0) {
		// The target host is not reachable.
		return NetworkNone;
	}
	
	NetworkConnectivity returnValue = NetworkNone;
	if ((flags & kSCNetworkReachabilityFlagsConnectionRequired) == 0) {
		// If the target host is reachable and no connection is required then we'll assume (for now) that you're on Wi-Fi...
		returnValue = NetworkWiFi;
	}
	
	if ((((flags & kSCNetworkReachabilityFlagsConnectionOnDemand) != 0) ||
		 (flags & kSCNetworkReachabilityFlagsConnectionOnTraffic) != 0))
	{
		// ... and the connection is on-demand (or on-traffic) if the calling application is using the CFSocketStream or higher APIs...
		if ((flags & kSCNetworkReachabilityFlagsInterventionRequired) == 0) {
			// ... and no [user] intervention is needed...
			returnValue = NetworkWiFi;
		}
	}

#if TARGET_OS_IPHONE
	if ((flags & kSCNetworkReachabilityFlagsIsWWAN) == kSCNetworkReachabilityFlagsIsWWAN) {
		// ... but WWAN connections are OK if the calling application is using the CFNetwork APIs.
		returnValue = NetworkCel;
	}
#endif
	
	return returnValue;
}


- (BOOL)connectionRequired
{
	return (_currentFlags & kSCNetworkReachabilityFlagsConnectionRequired) != 0;
}

- (NetworkConnectivity)currentConnectivity
{
	return [NetworkStatus networkStatusForFlags:_currentFlags];
}

@end

