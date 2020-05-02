//
//  SecondViewController.m
//  Go Map!!
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


static const NSInteger BACKGROUND_SECTION		= 0;
//static const NSInteger INTERACTION_SECTION	= 1;
static const NSInteger OVERLAY_SECTION			= 2;
static const NSInteger CACHE_SECTION			= 3;


@interface CustomBackgroundCell : UITableViewCell
@property IBOutlet UIButton * button;
@end
@implementation CustomBackgroundCell
@end




@implementation DisplayViewController

-(IBAction)gpsSwitchChanged:(id)sender
{
	// need this to take effect immediately in case they exit the app without dismissing this controller, and they want GPS enabled in background
	MapView * mapView = AppDelegate.getAppDelegate.mapView;
	mapView.enableGpxLogging = _gpxLoggingSwitch.on;
}

-(IBAction)toggleObjectFilters:(UISwitch *)sender
{
	EditorMapLayer * editor = AppDelegate.getAppDelegate.mapView.editorLayer;
	editor.enableObjectFilters = sender.on;
}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];

	MapView * mapView = [(AppDelegate *)[[UIApplication sharedApplication] delegate] mapView];

	if ( [self isMovingToParentViewController] ) {
		// becoming visible the first time
		self.navigationController.navigationBarHidden = NO;

		_notesSwitch.on				= (mapView.viewOverlayMask & VIEW_OVERLAY_NOTES) != 0;
		_gpsTraceSwitch.on			= !mapView.gpsTraceLayer.hidden;

		_birdsEyeSwitch.on			= mapView.enableBirdsEye;
		_rotationSwitch.on			= mapView.enableRotation;
		_unnamedRoadSwitch.on		= mapView.enableUnnamedRoadHalo;
		_gpxLoggingSwitch.on		= mapView.enableGpxLogging;
		_turnRestrictionSwitch.on	= mapView.enableTurnRestriction;
		_objectFiltersSwitch.on		= mapView.editorLayer.enableObjectFilters;

	}
}

-(void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
	// place a checkmark next to currently selected display
	if ( indexPath.section == BACKGROUND_SECTION ) {
		MapView * mapView = [AppDelegate getAppDelegate].mapView;
		if ( indexPath.row == mapView.viewState ) {
			cell.accessoryType = UITableViewCellAccessoryCheckmark;
		}
	}

	// set the name of the aerial provider
	if ( indexPath.section == BACKGROUND_SECTION && indexPath.row == 2 ) {
		if ( [cell isKindOfClass:[CustomBackgroundCell class]] ) {
			AppDelegate * appDelegate = [AppDelegate getAppDelegate];
			AerialList * aerials = appDelegate.mapView.customAerials;
			CustomBackgroundCell * custom = (id)cell;
			[custom.button setTitle:aerials.currentAerial.name forState:UIControlStateNormal];
			[custom.button sizeToFit];
		}
	}
}

- (void)applyChanges
{
	MapView * mapView = [AppDelegate getAppDelegate].mapView;

	NSInteger maxRow = [self.tableView numberOfRowsInSection:BACKGROUND_SECTION];
	for ( NSInteger row = 0; row < maxRow; ++row ) {
		NSIndexPath * indexPath = [NSIndexPath indexPathForRow:row inSection:BACKGROUND_SECTION];
		UITableViewCell * cell = [self.tableView cellForRowAtIndexPath:indexPath];
		if ( cell.accessoryType == UITableViewCellAccessoryCheckmark ) {
			mapView.viewState = (MapViewState)row;
			[mapView setAerialTileService:mapView.customAerials.currentAerial];
			break;
		}
	}
	ViewOverlayMask mask = 0;
	mask |= _notesSwitch.on			? VIEW_OVERLAY_NOTES    : 0;
	mask |= _gpsTraceSwitch.on		? VIEW_OVERLAY_GPSTRACE : 0;
    mask |= _unnamedRoadSwitch.on 	? VIEW_OVERLAY_NONAME 	: 0;
	mapView.viewOverlayMask = mask;

	mapView.enableBirdsEye			= _birdsEyeSwitch.on;
	mapView.enableRotation			= _rotationSwitch.on;
	mapView.enableUnnamedRoadHalo	= _unnamedRoadSwitch.on;
	mapView.enableGpxLogging		= _gpxLoggingSwitch.on;
	mapView.enableTurnRestriction	= _turnRestrictionSwitch.on;
}

- (void)viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];
	[self applyChanges];
}

- (IBAction)onDone:(id)sender
{
	[self dismissViewControllerAnimated:YES completion:nil];
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

	} else if ( indexPath.section == CACHE_SECTION ) {

	}
	[self.tableView deselectRowAtIndexPath:indexPath animated:YES];

	// automatically dismiss settings when a new background is selected
	if ( indexPath.section == BACKGROUND_SECTION ) {
		[self onDone:nil];
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
