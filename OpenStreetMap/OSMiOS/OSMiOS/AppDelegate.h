//
//  AppDelegate.h
//  OSMiOS
//
//  Created by Bryce Cogswell on 12/6/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <UIKit/UIKit.h>

@class MapView;
@class MapViewController;


@interface AppDelegate : UIResponder <UIApplicationDelegate>

@property (strong, nonatomic)	UIWindow *	window;
@property (weak,nonatomic)		MapView *	mapView;

@property (strong,nonatomic) NSString *	userName;
@property (strong,nonatomic) NSString *	userPassword;

-(NSString *)appName;
-(NSString *)appVersion;

@end
