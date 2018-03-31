//
//  CustomAerialViewController.m
//  Go Map!!
//
//  Created by Bryce Cogswell on 8/20/14.
//  Copyright (c) 2014 Bryce Cogswell. All rights reserved.
//

#import "AerialList.h"
#import "AerialListViewController.h"
#import "AerialEditViewController.h"
#import "AppDelegate.h"
#import "DisplayViewController.h"
#import "MapView.h"
#import "MercatorTileLayer.h"
#import "UITableViewCell+FixConstraints.h"


#define SECTION_BUILTIN 	0
#define SECTION_USER		1
#define SECTION_EXTERNAL	2


@implementation AerialListViewController

- (void)viewDidLoad
{
	AppDelegate * appDelegate = [AppDelegate getAppDelegate];
	_aerials = appDelegate.mapView.customAerials;

	OSMRect viewport = [appDelegate.mapView screenLongitudeLatitude];
	_imageryForRegion = [_aerials servicesForRegion:viewport];

	[super viewDidLoad];

	self.navigationItem.rightBarButtonItem = self.editButtonItem;
}

- (void)viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];

	if ( [self isMovingFromParentViewController] ) {
		AppDelegate * appDelegate = [AppDelegate getAppDelegate];
		MapView * mapView = appDelegate.mapView;
		mapView.aerialLayer.aerialService = _aerials.currentAerial;
	}
}

-(void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
	[cell fixConstraints];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
	// Fix bug on iPad where cell heights come back as -1:
	// CGFloat h = [super tableView:tableView heightForRowAtIndexPath:indexPath];
	return 44.0;
}

#pragma mark - Table view data source

-(NSArray *)aerialListForSection:(NSInteger)section
{
	if ( section == SECTION_BUILTIN )
		return _aerials.builtinServices;
	if ( section == SECTION_USER )
		return _aerials.userDefinedServices;
	if ( section == SECTION_EXTERNAL )
		return _imageryForRegion;
	return nil;
}


- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
	if ( section == SECTION_BUILTIN )
		return NSLocalizedString(@"Standard imagery",nil);
	if ( section == SECTION_USER )
		return NSLocalizedString(@"User-defined imagery",nil);
	if ( section == SECTION_EXTERNAL )
		return NSLocalizedString(@"Additional imagery sources",nil);
	return nil;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
	return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	NSArray * a = [self aerialListForSection:section];
	return a.count + (section == SECTION_USER);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	if ( indexPath.section == SECTION_USER && indexPath.row == _aerials.userDefinedServices.count ) {
		UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"addNewCell" forIndexPath:indexPath];
		return cell;
	}

	NSArray * list = [self aerialListForSection:indexPath.section];
	if ( list == nil )
		return nil;
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"backgroundCell" forIndexPath:indexPath];
	AerialService * aerial = list[ indexPath.row ];

	// set selection
	NSString * title = aerial.name;
	if ( aerial == _aerials.currentAerial ) {
		title = [@"\u2714 " stringByAppendingString:title];	// add checkmark
	}
	cell.textLabel.text = title;
	cell.detailTextLabel.text = aerial.url;
	return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
	if ( indexPath.section == SECTION_USER && indexPath.row < _aerials.userDefinedServices.count )
		return YES;
	return NO;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
	if (editingStyle == UITableViewCellEditingStyleDelete) {
		// Delete the row from the data source
		[_aerials removeUserDefinedServiceAtIndex:indexPath.row];
		[tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
	} else if (editingStyle == UITableViewCellEditingStyleInsert) {
		// Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
	}
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)fromIndexPath toIndexPath:(NSIndexPath *)toIndexPath
{
	AerialService * service = _aerials.userDefinedServices[ fromIndexPath.row];
	[_aerials removeUserDefinedServiceAtIndex:fromIndexPath.row];
	[_aerials addUserDefinedService:service atIndex:toIndexPath.row];
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath
{
	if ( indexPath.section == SECTION_USER && indexPath.row < _aerials.userDefinedServices.count )
		return YES;
	return NO;
}


#pragma mark - Navigation


- (NSIndexPath *) tableView:(UITableView *)tableView willSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	// don't allow selection the Add button
	if ( indexPath.section == SECTION_USER && indexPath.row == _aerials.userDefinedServices.count )
		return nil;
	return indexPath;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	AppDelegate * appDelegate = [AppDelegate getAppDelegate];
	MapView * mapView = appDelegate.mapView;

	NSArray * list = [self aerialListForSection:indexPath.section];
	AerialService * service = indexPath.row < list.count ? list[ indexPath.row ] : nil;
	if ( service == nil )
		return;
	_aerials.currentAerial = service;

	mapView.aerialLayer.aerialService = _aerials.currentAerial;

	// if popping all the way up we need to tell Settings to save changes
	[self.displayViewController applyChanges];
	[self.navigationController popToRootViewControllerAnimated:YES];
}


- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
	UITableViewController * controller = [segue destinationViewController];
	NSIndexPath * editRow = nil;
	if ( [controller isKindOfClass:[AerialEditViewController class]] ) {
		AerialEditViewController * c = (id)controller;
		if ( [sender isKindOfClass:[UIButton class]] ) {
			// add new
			editRow = [NSIndexPath indexPathForRow:_aerials.userDefinedServices.count inSection:SECTION_USER];
		} else {
			// edit existing service
			UITableViewCell * cell = sender;
			while ( cell && ![cell isKindOfClass:[UITableViewCell class]] )
				cell = (id)[cell superview];
			NSIndexPath * indexPath = [self.tableView indexPathForCell:cell];
			if ( indexPath == nil )
				return;
			NSArray * a = [self aerialListForSection:indexPath.section];
			AerialService * service = indexPath.row < a.count ? a[indexPath.row] : nil;
			if ( service == nil )
				return;
			if ( indexPath.section == SECTION_USER ) {
				editRow = indexPath;
			}
			c.name = service.name;
			c.url = service.url;
			c.zoom = @(service.maxZoom);
		}

		c.completion = ^(AerialService * service) {
			if ( editRow == nil )
				return;
			if ( editRow.row == _aerials.userDefinedServices.count ) {
				[_aerials addUserDefinedService:service atIndex:_aerials.userDefinedServices.count];
			} else if ( editRow >= 0 ) {
				[_aerials removeUserDefinedServiceAtIndex:editRow.row];
				[_aerials addUserDefinedService:service atIndex:editRow.row];
			}
			[self.tableView reloadData];
		};
	}
}

@end
