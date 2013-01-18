//
//  AppDelegate.h
//  OpenStreetMap
//
//  Created by Bryce on 8/31/12.
//  Copyright (c) 2012 Bryce. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class Downloader;
@class MainWindowController;

@interface AppDelegate : NSObject <NSApplicationDelegate>
{
}

@property (strong,nonatomic) MainWindowController	*	mainWindowController;

@property (strong,nonatomic) NSString *	userName;
@property (strong,nonatomic) NSString *	userPassword;

-(NSString *)appName;
-(NSString *)appVersion;

@end
