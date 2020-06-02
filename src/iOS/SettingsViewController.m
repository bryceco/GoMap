//
//  SettingsViewController.m
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/6/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import "AppDelegate.h"
#import "AerialList.h"
#import "AerialListViewController.h"
#import "CommonPresetList.h"
#import "EditorMapLayer.h"
#import "OsmMapData.h"
#import "MapView.h"
#import "MapViewController.h"
#import "MercatorTileLayer.h"
#import "SettingsViewController.h"


@implementation SettingsViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	
	self.tableView.estimatedRowHeight = 44.0;
	self.tableView.rowHeight = UITableViewAutomaticDimension;
}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];

	if ( [self isMovingToParentViewController] ) {
		// becoming visible the first time
		self.navigationController.navigationBarHidden = NO;
	}

	PresetLanguages * presetLanguages = [PresetLanguages new];
	NSString * preferredLanguageCode = presetLanguages.preferredLanguageCode;
	NSString * preferredLanguage = [presetLanguages localLanguageNameForCode:preferredLanguageCode];
	_language.text = preferredLanguage;

	// set username, but then validate it
	AppDelegate * appDelegate = [AppDelegate getAppDelegate];

	_username.text = @"";
	if ( appDelegate.userName.length > 0 ) {
		[appDelegate.mapView.editorLayer.mapData verifyUserCredentialsWithCompletion:^(NSString * errorMessage) {
			if ( errorMessage ) {
				_username.text = NSLocalizedString(@"<unknown>",nil);
			} else {
				_username.text = appDelegate.userName;
			}
			
			[self.tableView reloadData];
		}];
	}
}

- (void)viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];
}

-(void)accessoryDidConnect:(id)sender
{
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	[self.tableView deselectRowAtIndexPath:indexPath animated:YES];
}

@end
