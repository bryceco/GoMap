//
//  AppDelegate.h
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 8/31/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class Downloader;
@class MainWindowController;
@class MapView;

@interface AppDelegate : NSObject <NSApplicationDelegate>
{
}

@property (strong,nonatomic) 	MainWindowController	*	mainWindowController;
@property (assign,nonatomic)	MapView					*	mapView;

@property (strong,nonatomic) NSString *	userName;
@property (strong,nonatomic) NSString *	userPassword;

+(AppDelegate *)getAppDelegate;

-(NSString *)appName;
-(NSString *)appVersion;

@end
