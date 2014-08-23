//
//  SecondViewController.m
//  OSMiOS
//
//  Created by Bryce Cogswell on 12/6/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <MessageUI/MessageUI.h>

#import "AppDelegate.h"
#import "AerialList.h"
#import "AerialListViewController.h"
#import "EditorMapLayer.h"
#import "MapView.h"
#import "MapViewController.h"
#import "MercatorTileLayer.h"
#import "SettingsViewController.h"
#import "UITableViewCell+FixConstraints.h"


static const NSInteger BACKGROUND_SECTION	= 0;
//static const NSInteger SENDMAIL_SECTION		= 3;

@interface CustomBackgroundCell : UITableViewCell
@property IBOutlet UILabel * title;
@end
@implementation CustomBackgroundCell
@end




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
	HIDE_MAPNIK,					// editor + custom
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
		if ( mapView.customAerials.enabled ? row == 4 : value == RowMap[row] ) {
			NSIndexPath * indexPath = [NSIndexPath indexPathForRow:row inSection:BACKGROUND_SECTION];
			UITableViewCell * cell = [self.tableView cellForRowAtIndexPath:indexPath];
			cell.accessoryType = UITableViewCellAccessoryCheckmark;
			break;
		}
	}

	[self setCustomAerialCellTitle];
}

-(void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
	[cell fixConstraints];
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

				// enable/disable editing buttons based on visibility
				AppDelegate * appDelegate = [[UIApplication sharedApplication] delegate];
				[appDelegate.mapView.viewController updateDeleteButtonState];
				[appDelegate.mapView.viewController updateUndoRedoButtonState];

				mapView.editorLayer.textColor = mapView.aerialLayer.hidden ? NSColor.blackColor : NSColor.whiteColor;

				if ( row == 4 ) {
					appDelegate.mapView.customAerials.enabled = YES;
					[appDelegate.mapView setAerialService:mapView.customAerials.currentAerial];
				} else {
					appDelegate.mapView.customAerials.enabled = NO;
					[appDelegate.mapView setAerialService:mapView.customAerials.bingAerial];
				}
				break;
			}
		}
	}
}

-(void)setCustomAerialCellTitle
{
	AppDelegate * appDelegate = [[UIApplication sharedApplication] delegate];
	AerialList * aerials = appDelegate.mapView.customAerials;
	NSIndexPath * path = [NSIndexPath indexPathForRow:4 inSection:BACKGROUND_SECTION];
	CustomBackgroundCell * cell = (id)[self.tableView cellForRowAtIndexPath:path];
	if ( [cell isKindOfClass:[CustomBackgroundCell class]] ) {
		if ( aerials.currentIndex < aerials.count ) {
			cell.title.text = aerials.currentAerial.name;
		} else {
			cell.title.text = @"Custom Aerial...";
		}
	}
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	UITableViewCell * cell = [tableView cellForRowAtIndexPath:indexPath];

	if ( indexPath.section == BACKGROUND_SECTION ) {

		// change checkmark to follow selection
		NSInteger maxRow = [self.tableView numberOfRowsInSection:indexPath.section];
		for ( NSInteger row = 0; row < maxRow; ++row ) {
			NSIndexPath * tmpPath = [NSIndexPath indexPathForRow:row inSection:indexPath.section];
			UITableViewCell * tmpCell = [tableView cellForRowAtIndexPath:tmpPath];
			tmpCell.accessoryType = UITableViewCellAccessoryNone;
		}
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
			if ( appDelegate.userName.length ) {
				NSString * body = [NSString stringWithFormat:@"OSM ID: %@ (optional)\n\n",appDelegate.userName];
				[mail setMessageBody:body isHTML:NO];
			}
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
