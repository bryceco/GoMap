//
//  OsmServerViewController.m
//  Go Map!!
//
//  Created by Bryce Cogswell on 11/29/16.
//  Copyright © 2016 Bryce Cogswell. All rights reserved.
//

#import "OsmServerViewController.h"
#import "AppDelegate.h"
#import "EditorMapLayer.h"
#import "OsmMapData.h"
#import "MapView.h"

@implementation OsmServerViewController

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

@end
