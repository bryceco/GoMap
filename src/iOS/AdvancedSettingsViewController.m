//
//  OsmServerViewController.m
//  Go Map!!
//
//  Created by Bryce Cogswell on 11/29/16.
//  Copyright © 2016 Bryce Cogswell. All rights reserved.
//

#import "AdvancedSettingsViewController.h"
#import "AppDelegate.h"
#import "EditorMapLayer.h"
#import "FpsLabel.h"
#import "MyApplication.h"
#import "OsmMapData.h"
#import "MapView.h"

@implementation AdvancedSettingsViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

	self.tableView.estimatedRowHeight = 44;
	self.tableView.rowHeight = UITableViewAutomaticDimension;
}

- (IBAction)textFieldReturn:(id)sender
{
	[sender resignFirstResponder];
}


- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];

	AppDelegate * appDelegate = [AppDelegate getAppDelegate];
	OsmMapData * mapData = appDelegate.mapView.editorLayer.mapData;
	self.hostname.text = [mapData getServer];
	self.originalHostname = self.hostname.text;

	MyApplication * app = (id)[UIApplication sharedApplication];
	self.switchFPS.on		= appDelegate.mapView.fpsLabel.showFPS;
	self.switchTouches.on 	= app.showTouchCircles;
}

- (void)viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];

	AppDelegate * appDelegate = [AppDelegate getAppDelegate];
	OsmMapData * mapData = appDelegate.mapView.editorLayer.mapData;
	if (![self.hostname.text isEqualToString:self.originalHostname]) {
		[mapData setServer:self.hostname.text];
    }
}

- (IBAction)switchFPS:(id)sender
{
	UISwitch * toggle = sender;
	AppDelegate * appDelegate = [AppDelegate getAppDelegate];
	appDelegate.mapView.fpsLabel.showFPS = toggle.on;
}

- (IBAction)switchTouch:(id)sender
{
	UISwitch * toggle = sender;
	MyApplication * app = (id)[UIApplication sharedApplication];
	app.showTouchCircles = toggle.on;
}

@end
