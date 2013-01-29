//
//  SecondViewController.m
//  OSMiOS
//
//  Created by Bryce Cogswell on 12/6/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <MessageUI/MessageUI.h>

#import "AppDelegate.h"
#import "EditorMapLayer.h"
#import "MapView.h"
#import "MercatorTileLayer.h"
#import "SettingsViewController.h"


static const NSInteger BACKGROUND_SECTION	= 0;
static const NSInteger SENDMAIL_SECTION		= 3;


@implementation SettingsViewController

enum {
	HIDE_EDITOR = 1,
	HIDE_AERIAL = 2,
	HIDE_MAPNIK = 4
};

static const NSInteger RowMap[] = {
	HIDE_AERIAL | HIDE_MAPNIK,		// editor only
	HIDE_MAPNIK,					// editor + bing
	HIDE_EDITOR | HIDE_MAPNIK,		// bing only
	HIDE_EDITOR | HIDE_AERIAL,		// mapnik only
};

- (void)viewDidLoad
{
    [super viewDidLoad];
}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];

	self.navigationController.navigationBarHidden = NO;

	MapView * mapView = [(AppDelegate *)[[UIApplication sharedApplication] delegate] mapView];

	NSInteger value = 0;
	value |= mapView.editorLayer.hidden ? HIDE_EDITOR : 0;
	value |= mapView.aerialLayer.hidden ? HIDE_AERIAL : 0;
	value |= mapView.mapnikLayer.hidden ? HIDE_MAPNIK : 0;
	for ( NSInteger row = 0; row < sizeof RowMap/sizeof RowMap[0]; ++row ) {
		if ( value == RowMap[row] ) {
			NSIndexPath * indexPath = [NSIndexPath indexPathForRow:row inSection:BACKGROUND_SECTION];
			UITableViewCell * cell = [self.tableView cellForRowAtIndexPath:indexPath];
			cell.accessoryType = UITableViewCellAccessoryCheckmark;
			break;
		}
	}
}

- (void)viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];

	if ( [self isMovingFromParentViewController] ) {
		NSInteger maxRow = [self.tableView numberOfRowsInSection:BACKGROUND_SECTION];
		for ( NSInteger row = 0; row < maxRow; ++row ) {
			NSIndexPath * indexPath = [NSIndexPath indexPathForRow:row inSection:BACKGROUND_SECTION];
			UITableViewCell * cell = [self.tableView cellForRowAtIndexPath:indexPath];
			if ( cell.accessoryType == UITableViewCellAccessoryCheckmark ) {
				MapView * mapView = [(AppDelegate *)[[UIApplication sharedApplication] delegate] mapView];
				NSInteger map = RowMap[ row ];
				mapView.editorLayer.hidden = (map & HIDE_EDITOR) ? YES : NO;
				mapView.aerialLayer.hidden = (map & HIDE_AERIAL) ? YES : NO;
				mapView.mapnikLayer.hidden = (map & HIDE_MAPNIK) ? YES : NO;

				mapView.editorLayer.textColor = mapView.aerialLayer.hidden ? NSColor.blackColor : NSColor.whiteColor;
				break;
			}
		}
	}
}

#if 0
-(IBAction)done:(id)sender
{
	NSInteger maxRow = [self.tableView numberOfRowsInSection:BACKGROUND_SECTION];
	for ( NSInteger row = 0; row < maxRow; ++row ) {
		NSIndexPath * indexPath = [NSIndexPath indexPathForRow:row inSection:BACKGROUND_SECTION];
		UITableViewCell * cell = [self.tableView cellForRowAtIndexPath:indexPath];
		if ( cell.accessoryType == UITableViewCellAccessoryCheckmark ) {
			MapView * mapView = [(AppDelegate *)[[UIApplication sharedApplication] delegate] mapView];
			NSInteger map = RowMap[ row ];
			mapView.editorLayer.hidden = (map & HIDE_EDITOR) ? YES : NO;
			mapView.aerialLayer.hidden = (map & HIDE_AERIAL) ? YES : NO;
			mapView.mapnikLayer.hidden = (map & HIDE_MAPNIK) ? YES : NO;
			break;
		}
	}
	[self dismissViewControllerAnimated:YES completion:nil];
}
#endif


- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	UITableViewCell * cell = [tableView cellForRowAtIndexPath:indexPath];

	if ( indexPath.section == BACKGROUND_SECTION ) {

		NSInteger maxRow = [self.tableView numberOfRowsInSection:indexPath.section];
		for ( NSInteger row = 0; row < maxRow; ++row ) {
			NSIndexPath * tmpPath = [NSIndexPath indexPathForRow:row inSection:indexPath.section];
			UITableViewCell * cell = [tableView cellForRowAtIndexPath:tmpPath];
			cell.accessoryType = UITableViewCellAccessoryNone;
		}
		UITableViewCell * cell = [tableView cellForRowAtIndexPath:indexPath];
		cell.accessoryType = UITableViewCellAccessoryCheckmark;
		// automatically dismiss settings when a new background is selected
		[self.navigationController popToRootViewControllerAnimated:YES];
	}
	if ( cell == _sendMailCell ) {
		if ( [MFMailComposeViewController canSendMail] ) {
			AppDelegate * appDelegate = [[UIApplication sharedApplication] delegate];
			MFMailComposeViewController * mail = [[MFMailComposeViewController alloc] init];
			mail.mailComposeDelegate = self;
			[mail setSubject:[NSString stringWithFormat:@"%@ %@ feedback", appDelegate.appName, appDelegate.appVersion]];
			[mail setToRecipients:@[@"bryceco@yahoo.com"]];
			[self.navigationController presentViewController:mail animated:YES completion:nil];
		} else {
			UIAlertView * alert = [[UIAlertView alloc] initWithTitle:@"Cannot compose message" message:@"Mail delivery is not available on this device" delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
			[alert show];
		}
	}

	[self.tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (void)mailComposeController:(MFMailComposeViewController*)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError*)error
{
	[self dismissViewControllerAnimated:YES completion:nil];
}


- (void)tableView:(UITableView *)tableView didDeselectRowAtIndexPath:(NSIndexPath *)indexPath
{
	if ( indexPath.section == BACKGROUND_SECTION ) {
		UITableViewCell * cell = [tableView cellForRowAtIndexPath:indexPath];
		cell.accessoryType = UITableViewCellAccessoryNone;
	}
}



@end
