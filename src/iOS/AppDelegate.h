//
//  AppDelegate.h
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/6/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <UIKit/UIKit.h>

@class ExternalGPS;
@class MapView;


@interface AppDelegate : UIResponder <UIApplicationDelegate>

@property (class,readonly)		AppDelegate 		*	shared;


@property (strong, nonatomic)	UIWindow			*	window;
@property (weak,nonatomic)		MapView				*	mapView;

@property (strong,nonatomic)	NSString			*	userName;
@property (strong,nonatomic)	NSString			*	userPassword;

@property (readonly,nonatomic)	BOOL					isAppUpgrade;

@property (strong,nonatomic)	ExternalGPS			*	externalGPS;

-(NSString *)appName;
-(NSString *)appVersion;
- (NSString *)appBuildNumber;

@end
