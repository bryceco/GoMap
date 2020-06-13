//
//  AppDelegate.m
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/6/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//


#import "AppDelegate.h"
#import "BingMapsGeometry.h"
#import "EditorMapLayer.h"
#import "GpxLayer.h"
#import "KeyChain.h"
#import "OsmMapData.h"
#import "MapView.h"
#import "MapViewController.h"
#import "URLParserResult.h"
#import "GeoURLParser.h"

@implementation AppDelegate

+ (AppDelegate *)getAppDelegate
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

/**
 Makes sure that the user defaults do not contain plaintext credentials from previous app versions.
 */
- (void)removePlaintextCredentialsFromUserDefaults {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"username"];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"password"];
}

-(void)setMapLatitude:(double)lat longitude:(double)lon zoom:(double)zoom view:(MapViewState)view
{
	double delayInSeconds = 0.1;
	dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
	dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
		double metersPerDegree = MetersPerDegree( lat );
		double minMeters = 50;
		double widthDegrees = minMeters / metersPerDegree;
		if ( zoom != 0 ) {
			widthDegrees = 360.0 / pow(2,zoom);
		}
		[self.mapView setTransformForLatitude:lat longitude:lon width:widthDegrees];
		if ( view != MAPVIEW_NONE ) {
			self.mapView.viewState = view;
		}
	});
}


-(BOOL)application:(UIApplication *)application openURL:(NSURL *)url options:(nonnull NSDictionary<NSString *,id> *)options
{
    GeoURLParser *geoURLParser = [GeoURLParser new];
    URLParserResult *parserResult = [geoURLParser parseURL:url];
    
    if (parserResult) {
        [self setMapLatitude:parserResult.latitude
                   longitude:parserResult.longitude
                        zoom:parserResult.zoom
                        view:parserResult.viewState];
    }

	// open to longitude/latitude
	if ( [url.absoluteString hasPrefix:@"gomaposm://?"] ) {

		NSArray * params = [url.query componentsSeparatedByString:@"&"];
		BOOL hasCenter = NO, hasZoom = NO;
		double lat = 0, lon = 0, zoom = 0;
		MapViewState view = MAPVIEW_NONE;

		for ( NSString * param in params ) {
			NSScanner * scanner = [NSScanner scannerWithString:param];

			if ( [scanner scanString:@"center=" intoString:NULL] ) {

				// scan center
				BOOL ok = YES;
				if ( ![scanner scanDouble:&lat] )
					ok = NO;
				if ( ![scanner scanString:@"," intoString:NULL] )
					ok = NO;
				if ( ![scanner scanDouble:&lon] )
					ok = NO;
				hasCenter = ok;

			} else if ( [scanner scanString:@"zoom=" intoString:NULL] ) {

				// scan zoom
				BOOL ok = YES;
				if ( ![scanner scanDouble:&zoom] )
					ok = NO;
				hasZoom = ok;

			} else if ( [scanner scanString:@"view=" intoString:NULL] ) {

				// scan view
				if ( [scanner scanString:@"aerial+editor" intoString:NULL] ) {
					view = MAPVIEW_EDITORAERIAL;
				} else if ( [scanner scanString:@"aerial" intoString:NULL] ) {
					view = MAPVIEW_AERIAL;
				} else if ( [scanner scanString:@"mapnik" intoString:NULL] ) {
					view = MAPVIEW_MAPNIK;
				} else if ( [scanner scanString:@"editor" intoString:NULL] ) {
					view = MAPVIEW_EDITOR;
				}

			} else {
				// unrecognized parameter
			}
		}
		if ( hasCenter ) {
			[self setMapLatitude:lat longitude:lon zoom:(hasZoom?zoom:0) view:view];
		} else {
			UIAlertController * alertView = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Invalid URL",nil) message:url.absoluteString preferredStyle:UIAlertControllerStyleAlert];
			[alertView addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK",nil) style:UIAlertActionStyleCancel handler:nil]];
			[self.mapView.viewController presentViewController:alertView animated:YES completion:nil];
		}
	}

	// GPX support
	if ( url.isFileURL && [url.pathExtension isEqualToString:@"gpx"] ) {

		// Process the URL

		double delayInSeconds = 1.0;
		dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
		dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
			NSData * data = [NSData dataWithContentsOfURL:url];
			BOOL ok = [self.mapView.gpxLayer loadGPXData:data center:YES];
			if ( !ok ) {
				UIAlertController * alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Open URL",nil)
																				message:NSLocalizedString(@"Sorry, an error occurred while loading the GPX file",nil)
																		 preferredStyle:UIAlertControllerStyleAlert];
				[alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK",nil) style:UIAlertActionStyleCancel handler:nil]];
				[self.mapView.viewController presentViewController:alert animated:YES completion:nil];
			}
		});

		// Indicate that we have successfully opened the URL
		return YES;
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
		UIUserNotificationSettings * settings = [UIUserNotificationSettings settingsForTypes:UIUserNotificationTypeBadge categories:nil];
		[[UIApplication sharedApplication] registerUserNotificationSettings:settings];
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

@end
