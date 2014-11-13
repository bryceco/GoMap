//
//  SecondViewController.m
//  OSMiOS
//
//  Created by Bryce Cogswell on 12/6/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <sys/utsname.h>

#import "AppDelegate.h"
#import "AerialList.h"
#import "AerialListViewController.h"
#import "EditorMapLayer.h"
#import "MapView.h"
#import "MapViewController.h"
#import "MercatorTileLayer.h"
#import "DisplayViewController.h"
#import "UITableViewCell+FixConstraints.h"


static const NSInteger BACKGROUND_SECTION		= 0;
//static const NSInteger INTERACTION_SECTION		= 1;
static const NSInteger OVERLAY_SECTION			= 2;
static const NSInteger CACHE_SECTION			= 3;

static const NSInteger OVERLAY_NOTES_ROW		= 0;
static const NSInteger OVERLAY_LOCATOR_ROW		= 1;
static const NSInteger OVERLAY_GPSTRACE_ROW		= 2;


@interface CustomBackgroundCell : UITableViewCell
@property IBOutlet UILabel * title;
@end
@implementation CustomBackgroundCell
@end




@implementation DisplayViewController

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];

	MapView * mapView = [(AppDelegate *)[[UIApplication sharedApplication] delegate] mapView];

	if ( [self isMovingToParentViewController] ) {
		// becoming visible the first time
		self.navigationController.navigationBarHidden = NO;

		NSIndexPath * indexPath = [NSIndexPath indexPathForRow:mapView.viewState inSection:BACKGROUND_SECTION];
		UITableViewCell * cell = [self.tableView cellForRowAtIndexPath:indexPath];
		cell.accessoryType = UITableViewCellAccessoryCheckmark;

		[self setCustomAerialCellTitle];

		NSIndexPath * notesPath = [NSIndexPath indexPathForRow:OVERLAY_NOTES_ROW inSection:OVERLAY_SECTION];
		NSIndexPath * locatorPath = [NSIndexPath indexPathForRow:OVERLAY_LOCATOR_ROW inSection:OVERLAY_SECTION];
		NSIndexPath * gpsTracePath = [NSIndexPath indexPathForRow:OVERLAY_GPSTRACE_ROW inSection:OVERLAY_SECTION];
		UITableViewCell * notesCell = [self.tableView cellForRowAtIndexPath:notesPath];
		UITableViewCell * locatorCell = [self.tableView cellForRowAtIndexPath:locatorPath];
		UITableViewCell * gpsTraceCell = [self.tableView cellForRowAtIndexPath:gpsTracePath];
		notesCell.accessoryType  = (mapView.viewOverlayMask & VIEW_OVERLAY_NOTES)==0 ? UITableViewCellAccessoryNone : UITableViewCellAccessoryCheckmark;
		locatorCell.accessoryType  = mapView.locatorLayer.hidden  ? UITableViewCellAccessoryNone : UITableViewCellAccessoryCheckmark;
		gpsTraceCell.accessoryType = mapView.gpsTraceLayer.hidden ? UITableViewCellAccessoryNone : UITableViewCellAccessoryCheckmark;

		_birdsEyeSwitch.on = mapView.enableBirdsEye;
		_rotationSwitch.on = mapView.enableRotation;

	} else {

		// returning from child view
		if ( mapView.customAerials.count == 0 ) {
			[mapView.customAerials reset];
		}

		[self setCustomAerialCellTitle];
	}
}

-(void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
	[cell fixConstraints];
}

- (void)applyChanges
{
	MapView * mapView = [(AppDelegate *)[[UIApplication sharedApplication] delegate] mapView];

	NSInteger maxRow = [self.tableView numberOfRowsInSection:BACKGROUND_SECTION];
	for ( NSInteger row = 0; row < maxRow; ++row ) {
		NSIndexPath * indexPath = [NSIndexPath indexPathForRow:row inSection:BACKGROUND_SECTION];
		UITableViewCell * cell = [self.tableView cellForRowAtIndexPath:indexPath];
		if ( cell.accessoryType == UITableViewCellAccessoryCheckmark ) {
			mapView.viewState = (MapViewState)row;
			mapView.aerialLayer.aerialService = mapView.customAerials.currentAerial;
			break;
		}
	}
	NSIndexPath * notesPath		= [NSIndexPath indexPathForRow:OVERLAY_NOTES_ROW	inSection:OVERLAY_SECTION];
	NSIndexPath * locatorPath	= [NSIndexPath indexPathForRow:OVERLAY_LOCATOR_ROW	inSection:OVERLAY_SECTION];
	NSIndexPath * gpsTracePath	= [NSIndexPath indexPathForRow:OVERLAY_GPSTRACE_ROW inSection:OVERLAY_SECTION];
	UITableViewCell * notesCell = [self.tableView cellForRowAtIndexPath:notesPath];
	UITableViewCell * locatorCell = [self.tableView cellForRowAtIndexPath:locatorPath];
	UITableViewCell * gpsTraceCell = [self.tableView cellForRowAtIndexPath:gpsTracePath];
	ViewOverlayMask mask = 0;
	mask |= notesCell.accessoryType	   == UITableViewCellAccessoryCheckmark ? VIEW_OVERLAY_NOTES    : 0;
	mask |= locatorCell.accessoryType  == UITableViewCellAccessoryCheckmark ? VIEW_OVERLAY_LOCATOR  : 0;
	mask |= gpsTraceCell.accessoryType == UITableViewCellAccessoryCheckmark ? VIEW_OVERLAY_GPSTRACE : 0;
	mapView.viewOverlayMask = mask;

	mapView.enableBirdsEye = _birdsEyeSwitch.on;
	mapView.enableRotation = _rotationSwitch.on;
}

- (void)viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];

	if ( [self isMovingFromParentViewController] ) {
		[self applyChanges];
	}
}

-(void)setCustomAerialCellTitle
{
	AppDelegate * appDelegate = [[UIApplication sharedApplication] delegate];
	AerialList * aerials = appDelegate.mapView.customAerials;
	NSIndexPath * path = [NSIndexPath indexPathForRow:2 inSection:BACKGROUND_SECTION];
	CustomBackgroundCell * cell = (id)[self.tableView cellForRowAtIndexPath:path];
	if ( [cell isKindOfClass:[CustomBackgroundCell class]] ) {
		cell.title.text = aerials.currentAerial.name;
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

	} else if ( indexPath.section == OVERLAY_SECTION ) {

		// toggle checkmark
		if ( cell.accessoryType == UITableViewCellAccessoryCheckmark ) {
			cell.accessoryType = UITableViewCellAccessoryNone;
		} else {
			cell.accessoryType = UITableViewCellAccessoryCheckmark;
		}
	} else if ( indexPath.section == CACHE_SECTION ) {

	}
	[self.tableView deselectRowAtIndexPath:indexPath animated:YES];

	// automatically dismiss settings when a new background is selected
	if ( indexPath.section == BACKGROUND_SECTION || indexPath.section == OVERLAY_SECTION ) {
		[self.navigationController popToRootViewControllerAnimated:YES];
	}
}

- (void)tableView:(UITableView *)tableView didDeselectRowAtIndexPath:(NSIndexPath *)indexPath
{
	if ( indexPath.section == BACKGROUND_SECTION ) {
		UITableViewCell * cell = [tableView cellForRowAtIndexPath:indexPath];
		cell.accessoryType = UITableViewCellAccessoryNone;
	}
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
	if ( [segue.destinationViewController isKindOfClass:[AerialListViewController class]] ) {
		AerialListViewController * aerialList = segue.destinationViewController;
		aerialList.displayViewController = self;
	}
}

@end
