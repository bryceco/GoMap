//
//  AppDelegate.m
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/6/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <UserNotifications/UserNotifications.h>

#import "AppDelegate.h"
#import "BingMapsGeometry.h"
#import "EditorMapLayer.h"
#import "LocationURLParser.h"
#import "GpxLayer.h"
#import "KeyChain.h"
#import "OsmMapData.h"
#import "MapView.h"
#import "MainViewController.h"

@implementation AppDelegate

+ (AppDelegate *)shared
{
	return (AppDelegate *)[[UIApplication sharedApplication] delegate];
}

- (BOOL)application:(UIApplication *)application willFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
	NSURL * url = [launchOptions objectForKey:UIApplicationLaunchOptionsURLKey];
	if ( url ) {
		if ( ![url isFileURL] )
			return NO;
		if ( ![[url pathExtension] isEqualToString:@"gpx"] )
			return NO;
	}
	return YES;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
#if 0	// This code sets the screen size as mandated for Mac App Store screen shots
	CGSize size = { 640 * (1440.0/752) * (1440.0/1337) * (1440.0/1431), 640 * (900.0/752) * (900.0/877) * (900.0/898) + 1 };
	for ( UIWindowScene * scene in UIApplication.sharedApplication.connectedScenes ) {
		scene.sizeRestrictions.minimumSize = size;
		scene.sizeRestrictions.maximumSize = size;
	}
#endif

	NSUserDefaults * defaults = [NSUserDefaults standardUserDefaults];

	// save the app version so we can detect upgrades
	NSString * prevVersion = [defaults objectForKey:@"appVersion"];
	if ( ![prevVersion isEqualToString:self.appVersion] ) {
		NSLog(@"Upgrade!");
		_isAppUpgrade = YES;
	}
	[defaults setObject:self.appVersion forKey:@"appVersion"];

	// read name/password from keychain
	self.userName		= [KeyChain getStringForIdentifier:@"username"];
	self.userPassword	= [KeyChain getStringForIdentifier:@"password"];

	[self removePlaintextCredentialsFromUserDefaults];

	// self.externalGPS = [[ExternalGPS alloc] init];

	NSURL * url = [launchOptions objectForKey:UIApplicationLaunchOptionsURLKey];
	if ( url ) {
		// somebody handed us a URL to open
		return [self application:application openURL:url options:@{}];
	}

	return YES;
}

- (BOOL)application:(UIApplication *)application continueUserActivity:(nonnull NSUserActivity *)userActivity restorationHandler:(nonnull void (^)(NSArray<id<UIUserActivityRestoring>> * _Nullable))restorationHandler
{
	if ( [userActivity.activityType isEqualToString:NSUserActivityTypeBrowsingWeb] ) {
		NSURL * url = userActivity.webpageURL;
		return [self application:application openURL:url options:@{}];
	}
	return NO;
}

/**
 Makes sure that the user defaults do not contain plaintext credentials from previous app versions.
 */
- (void)removePlaintextCredentialsFromUserDefaults {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"username"];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"password"];
}

-(void)setMapLocation:(MapLocation *)location
{
	double delayInSeconds = 0.1;
	dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
	dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
		[self.mapView setMapLocation:location];
	});
}

-(BOOL)application:(UIApplication *)application openURL:(NSURL *)url options:(nonnull NSDictionary<NSString *,id> *)options
{
	if ( url.isFileURL && [url.pathExtension isEqualToString:@"gpx"] ) {
		// Load GPX
		NSError * error = nil;
		[url startAccessingSecurityScopedResource];
		NSData * data = [NSData dataWithContentsOfURL:url options:0 error:&error];
		[url stopAccessingSecurityScopedResource];
		double delayInSeconds = 1.0;
		dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
		dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
			BOOL ok = [self.mapView.gpxLayer loadGPXData:data center:YES];
			if ( !ok ) {
				UIAlertController * alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Open URL",nil)
																				message:NSLocalizedString(@"Sorry, an error occurred while loading the GPX file",nil)
																		 preferredStyle:UIAlertControllerStyleAlert];
				[alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK",nil) style:UIAlertActionStyleCancel handler:nil]];
				[self.mapView.mainViewController presentViewController:alert animated:YES completion:nil];
			}
		});
		return YES;
	} else if ( url.absoluteString.length > 0 ) {
		// geo: and gomaposm: support
		LocationURLParser * urlParser = [LocationURLParser new];
		MapLocation * parserResult = [urlParser parseURL:url];
		if ( parserResult ) {
			double delayInSeconds = 1.0;
			dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
			dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
				[self setMapLocation:parserResult];
			});
			return YES;
		} else {
			UIAlertController * alertView = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Invalid URL",nil) message:url.absoluteString preferredStyle:UIAlertControllerStyleAlert];
			[alertView addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK",nil) style:UIAlertActionStyleCancel handler:nil]];
			[self.mapView.mainViewController presentViewController:alertView animated:YES completion:nil];
			return NO;
		}
	}
	return NO;
}

- (NSString *)appName
{
	return [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleDisplayName"];
}

- (NSString *)appVersion
{
	return [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
}

- (NSString *)appBuildNumber {
    return NSBundle.mainBundle.infoDictionary[@"CFBundleVersion"];
}
							
- (void)applicationWillResignActive:(UIApplication *)application
{
	// Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
	// Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
	// set app badge if edits are pending
	NSInteger pendingEdits = [self.mapView.editorLayer.mapData modificationCount];
	if ( pendingEdits ) {
		[UNUserNotificationCenter.currentNotificationCenter requestAuthorizationWithOptions:UNAuthorizationOptionBadge completionHandler:^(BOOL granted, NSError * _Nullable error) {
		}];
	}
	[[UIApplication sharedApplication] setApplicationIconBadgeNumber:pendingEdits];
	
	// while in background don't update our location so we don't download tiles/OSM data when moving
	self.mapView.userOverrodeLocationPosition = YES;
	[self.mapView.locationManager stopUpdatingHeading];
}

// Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
- (void)applicationWillEnterForeground:(UIApplication *)application
{
	// allow gps to update our location
	self.mapView.userOverrodeLocationPosition = NO;
	if ( self.mapView.gpsState != GPS_STATE_NONE ) {
		[self.mapView.locationManager startUpdatingHeading];
	}

	// remove badge now, so it disappears promptly on exit
	[[UIApplication sharedApplication] setApplicationIconBadgeNumber:0];
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
	// Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
}

- (void)applicationWillTerminate:(UIApplication *)application
{
	// Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}

+ (void)askUserToAllowLocationAccess:(UIViewController *)parentVC
{
	NSString * appName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"];
	NSString * title = [NSString stringWithFormat:NSLocalizedString(@"Turn On Location Services to Allow %@ to Determine Your Location",nil),appName];

	[AppDelegate askUserToOpenSettingsWithAlertTitle:title message:nil parentVC:parentVC];
}

+ (void)askUserToOpenSettingsWithAlertTitle:(NSString *)title message:(NSString *)message parentVC:(UIViewController *)parentVC
{
	UIAlertController *alertController = [UIAlertController alertControllerWithTitle:title
																			 message:message
																	  preferredStyle:UIAlertControllerStyleAlert];
	UIAlertAction *okayAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK",nil)
														 style:UIAlertActionStyleCancel
													   handler:nil];
	UIAlertAction *openSettings = [UIAlertAction actionWithTitle:NSLocalizedString(@"Open Settings",@"Open the iOS Settings app")
														   style:UIAlertActionStyleDefault
														 handler:^(UIAlertAction * _Nonnull action) {
															 [AppDelegate openAppSettings];
														 }];

	[alertController addAction:openSettings];
	[alertController addAction:okayAction];

	[parentVC presentViewController:alertController animated:YES completion:nil];
}

+ (void)openAppSettings
{
	NSURL *openSettingsURL = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
	if (openSettingsURL) {
		[[UIApplication sharedApplication] openURL:openSettingsURL options:@{} completionHandler:nil];
	}
}

@end
