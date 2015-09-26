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
//static const NSInteger INTERACTION_SECTION	= 1;
static const NSInteger OVERLAY_SECTION			= 2;
static const NSInteger CACHE_SECTION			= 3;


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

		_notesSwitch.on		= (mapView.viewOverlayMask & VIEW_OVERLAY_NOTES) != 0;
		_gpsTraceSwitch.on	= !mapView.gpsTraceLayer.hidden;

		_birdsEyeSwitch.on	= mapView.enableBirdsEye;
		_rotationSwitch.on	= mapView.enableRotation;
		_unnamedRoadSwitch.on	= mapView.enableUnnamedRoadHalo;
		_breadCrumbSwitch.on	= mapView.enableBreadCrumb;

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
	ViewOverlayMask mask = 0;
	mask |= _notesSwitch.on		? VIEW_OVERLAY_NOTES    : 0;
	mask |= _gpsTraceSwitch.on	? VIEW_OVERLAY_GPSTRACE : 0;
	mapView.viewOverlayMask = mask;

	mapView.enableBirdsEye			= _birdsEyeSwitch.on;
	mapView.enableRotation			= _rotationSwitch.on;
	mapView.enableUnnamedRoadHalo	= _unnamedRoadSwitch.on;
	mapView.enableBreadCrumb		= _breadCrumbSwitch.on;
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

	} else if ( indexPath.section == CACHE_SECTION ) {

	}
	[self.tableView deselectRowAtIndexPath:indexPath animated:YES];

	// automatically dismiss settings when a new background is selected
	if ( indexPath.section == BACKGROUND_SECTION ) {
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
