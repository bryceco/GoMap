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

- (NSString *)appName
{
	return [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleDisplayName"];
}

- (NSString *)appVersion
{
	return [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"];
}


- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	self.userName		= [[NSUserDefaults standardUserDefaults] objectForKey:@"userName"];
	self.userPassword	= [[NSUserDefaults standardUserDefaults] objectForKey:@"userPassword"];

	self.mainWindowController = [[MainWindowController alloc] init];
    [self.mainWindowController showWindow:self];

	BOOL enableMapCss	= [[NSUserDefaults standardUserDefaults] boolForKey:@"enableMapCss"];
	self.mainWindowController.mapView.editorLayer.enableMapCss = enableMapCss;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
	return YES;
}

- (void)applicationWillTerminate:(NSNotification *)notification
{	
	BOOL enableMapCss	= self.mainWindowController.mapView.editorLayer.enableMapCss;
	[[NSUserDefaults standardUserDefaults] setBool:enableMapCss forKey:@"enableMapCss"];
}

@end
