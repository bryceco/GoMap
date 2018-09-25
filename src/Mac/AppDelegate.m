//
//  AppDelegate.m
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 8/31/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import "AppDelegate.h"
#import "EditorMapLayer.h"
#import "MainWindowController.h"


@implementation AppDelegate

+(AppDelegate *)getAppDelegate
{
	return (AppDelegate *)[[NSApplication sharedApplication] delegate];
}

- (NSString *)appName
{
	return [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleDisplayName"];
}

- (NSString *)appVersion
{
	return [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"];
}

#if 0
- (NSArray *)tagCompletionsForKey:(NSString *)key
{
	NSSet * set = [[TagInfoDatabase sharedTagInfoDatabase] allTagValuesForKey:key];
	NSMutableSet * values = [self.mapView.editorLayer.mapData tagValuesForKey:key];
	[values addObjectsFromArray:[set allObjects]];
	if ( [key isEqualToString:@"wifi"] ) {
		values addObjectsFromArray:
	}
	NSArray * list = [values allObjects];
	return list;
}
#endif

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	self.userName		= [[NSUserDefaults standardUserDefaults] objectForKey:@"userName"];
	self.userPassword	= [[NSUserDefaults standardUserDefaults] objectForKey:@"userPassword"];

	self.mainWindowController = [[MainWindowController alloc] init];
    [self.mainWindowController showWindow:self];

#if 0
	BOOL enableMapCss	= [[NSUserDefaults standardUserDefaults] boolForKey:@"enableMapCss"];
	self.mainWindowController.mapView.editorLayer.enableMapCss = enableMapCss;
#endif
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
	return YES;
}

- (void)applicationWillTerminate:(NSNotification *)notification
{	
#if 0
	BOOL enableMapCss	= self.mainWindowController.mapView.editorLayer.enableMapCss;
	[[NSUserDefaults standardUserDefaults] setBool:enableMapCss forKey:@"enableMapCss"];
#endif
}

@end
