//
//  AppDelegate.m
//  OSMiOS
//
//  Created by Bryce Cogswell on 12/6/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//


#import "AppDelegate.h"
#import "DownloadThreadPool.h"



@implementation AppDelegate

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
	self.userName		= [defaults objectForKey:@"username"];
	self.userPassword	= [defaults objectForKey:@"password"];

	[DownloadThreadPool setUserAgent:[NSString stringWithFormat:@"%@/%@", self.appName, self.appVersion]];

#if 0 && DEBUG
	int size = 200 * 1000 * 1000;
	static void * big;
	big = malloc( size );
	memset( (void *)big, 'x', size );
#endif

	NSURL * url = [launchOptions objectForKey:UIApplicationLaunchOptionsURLKey];
	if ( url ) {
		// somebody handed us a URL to open
		return [self application:application openURL:url sourceApplication:@"" annotation:nil];
	}

	return YES;
}



-(BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation
{
	if ( ![url isFileURL] )
		return NO;
	if ( ![[url pathExtension] isEqualToString:@"gpx"] )
		return NO;

	// Tell our OfflineReaderViewController to process the URL
	NSData * data = [NSData dataWithContentsOfURL:url];

	double delayInSeconds = 0.1;
	dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
	dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
		UIAlertView * alertView = [[UIAlertView alloc] initWithTitle:@"Open URL" message:@"Sorry, this feature isn't implemented yet" delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
		[alertView show];
	});

	// Indicate that we have successfully opened the URL
	return YES;
}

- (NSString *)appName
{
	return [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleDisplayName"];
}

- (NSString *)appVersion
{
	return [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"];
}
							
- (void)applicationWillResignActive:(UIApplication *)application
{
	// Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
	// Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
	NSUserDefaults * defaults = [NSUserDefaults standardUserDefaults];
	[defaults setObject:self.userName		forKey:@"username"];
	[defaults setObject:self.userPassword	forKey:@"password"];
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
	// Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
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
