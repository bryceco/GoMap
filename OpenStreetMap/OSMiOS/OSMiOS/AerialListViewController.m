//
//  CustomAerialViewController.m
//  Go Map!!
//
//  Created by Bryce on 8/20/14.
//  Copyright (c) 2014 Bryce. All rights reserved.
//

#import "AppDelegate.h"
#import "MercatorTileLayer.h"
#import "AerialList.h"
#import "AerialListViewController.h"
#import "AerialEditViewController.h"
#import "MapView.h"
#import "SettingsViewController.h"
#import "UITableViewCell+FixConstraints.h"


@implementation AerialListViewController

- (void)viewDidLoad
{
	AppDelegate * appDelegate = [[UIApplication sharedApplication] delegate];
	_aerials = appDelegate.mapView.customAerials;

	[super viewDidLoad];

	self.navigationItem.rightBarButtonItem = self.editButtonItem;
}

- (void)viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];

	if ( [self isMovingFromParentViewController] ) {
		AppDelegate * appDelegate = [[UIApplication sharedApplication] delegate];
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

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
	return @"You can define your own aerial background layers here";
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	if ( section != 0 )
		return 0;
	return _aerials.count + 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	if ( indexPath.section != 0 )
		return nil;

	if ( indexPath.row < _aerials.count ) {
		UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"backgroundCell" forIndexPath:indexPath];
		AerialService * aerial = [_aerials serviceAtIndex:indexPath.row];


		// set selection
		NSString * title = aerial.name;
		if ( indexPath.row == _aerials.currentIndex ) {
			title = [@"\u2714 " stringByAppendingString:title];	// add checkmark
		}
		cell.textLabel.text = title;
		cell.detailTextLabel.text = aerial.url;
		return cell;
	} else {
		UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"addNewCell" forIndexPath:indexPath];
		return cell;
	}
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
	if ( indexPath.section == 0 && indexPath.row < _aerials.count )
		return YES;
	return NO;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
	if (editingStyle == UITableViewCellEditingStyleDelete) {
		// Delete the row from the data source
		[_aerials removeServiceAtIndex:indexPath.row];
		[tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
		if ( indexPath.row == _aerials.currentIndex ) {
			_aerials.currentIndex = 0;
		} else if ( indexPath.row < _aerials.currentIndex ) {
			--_aerials.currentIndex;
		}
	} else if (editingStyle == UITableViewCellEditingStyleInsert) {
		// Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
	}
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)fromIndexPath toIndexPath:(NSIndexPath *)toIndexPath
{
	AerialService * service = [_aerials serviceAtIndex:fromIndexPath.row];
	[_aerials removeServiceAtIndex:fromIndexPath.row];
	[_aerials addService:service atIndex:toIndexPath.row];
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath
{
	if ( indexPath.section == 0 && indexPath.row < _aerials.count )
		return YES;
	return NO;
}


#pragma mark - Navigation


- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	AppDelegate * appDelegate = [[UIApplication sharedApplication] delegate];
	MapView * mapView = appDelegate.mapView;

	_aerials.currentIndex = indexPath.row;
	mapView.aerialLayer.aerialService = _aerials.currentAerial;

#if 0
	[self.navigationController popViewControllerAnimated:YES];
#else
	// if popping all the way up we need to tell Settings to save changes
	[self.settingsViewController applyChanges];
	[self.navigationController popToRootViewControllerAnimated:YES];
#endif
}


- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
	UITableViewController * controller = [segue destinationViewController];
	if ( [controller isKindOfClass:[AerialEditViewController class]] ) {
		AerialEditViewController * c = (id)controller;
		NSInteger row;
		if ( [sender isKindOfClass:[UIButton class]] ) {
			// add new
			row = _aerials.count;
		} else {
			// edit existing
			UITableViewCell * cell = sender;
			while ( cell && ![cell isKindOfClass:[UITableViewCell class]] )
				cell = (id)[cell superview];
			NSIndexPath * indexPath = [self.tableView indexPathForCell:cell];
			if ( indexPath == nil || indexPath.row >= _aerials.count )
				return;
			row = indexPath.row;
			AerialService * service = [_aerials serviceAtIndex:row];
			c.name = service.name;
			c.url = service.url;
			c.tileServers = [service.subdomains componentsJoinedByString:@","];
			c.zoom = @(service.maxZoom);
		}

		c.completion = ^(AerialService * service) {
			if ( row >= _aerials.count ) {
				[_aerials addService:service atIndex:_aerials.count];
			} else {
				[_aerials removeServiceAtIndex:row];
				[_aerials addService:service atIndex:row];
			}
			[self.tableView reloadData];
		};
	}
}

@end
