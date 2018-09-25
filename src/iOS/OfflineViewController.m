//
//  OfflineViewController.m
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/27/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import "AppDelegate.h"
#import "MapView.h"
#import "MercatorTileLayer.h"
#import "OfflineViewController.h"


@implementation OfflineTableViewCell
@end


@implementation OfflineViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	
	self.tableView.estimatedRowHeight = 100;
	self.tableView.rowHeight = UITableViewAutomaticDimension;

	_aerialCell.tileLayer = AppDelegate.getAppDelegate.mapView.aerialLayer;
	_mapnikCell.tileLayer = AppDelegate.getAppDelegate.mapView.mapnikLayer;
	for ( OfflineTableViewCell * cell in @[ _aerialCell, _mapnikCell ] ) {
		cell.tileList			= [cell.tileLayer allTilesIntersectingVisibleRect];
		cell.detailLabel.text 	= [NSString stringWithFormat:NSLocalizedString(@"%lu tiles needed",nil), (unsigned long)cell.tileList.count];
		cell.button.enabled 	= cell.tileList.count > 0;
	}
}

- (void)viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];
	for ( OfflineTableViewCell * cell in @[ _aerialCell, _mapnikCell ] ) {
		[cell.activityView stopAnimating];
	}
}

#pragma mark - Table view delegate

-(void)downloadFileForCell:(OfflineTableViewCell *)cell
{
	if ( cell.tileList.count == 0 ) {
		[cell.button setTitle:NSLocalizedString(@"Start",nil) forState:UIControlStateNormal];
		[cell.activityView stopAnimating];
		if ( --_activityCount == 0 ) {
			[self.navigationItem setHidesBackButton:NO animated:YES];
		}
		return;
	}
	NSString * cacheKey = cell.tileList.lastObject;
	[cell.tileList removeLastObject];
	[cell.tileLayer downloadTileForKey:cacheKey completion:^{
		cell.detailLabel.text = [NSString stringWithFormat:NSLocalizedString(@"%lu tiles needed",nil), (unsigned long)cell.tileList.count];
		if ( cell.activityView.isAnimating ) {
			[self downloadFileForCell:cell];
		}
	}];
}

-(IBAction)toggleDownload:(id)sender
{
	OfflineTableViewCell * cell = sender == _aerialCell.button ? _aerialCell : _mapnikCell;

	if ( cell.activityView.isAnimating ) {
		// stop download
		[cell.button setTitle:NSLocalizedString(@"Start",nil) forState:UIControlStateNormal];
		[cell.activityView stopAnimating];
		if ( --_activityCount == 0 ) {
			[self.navigationItem setHidesBackButton:NO animated:YES];
		}
	} else {
		// start download
		[cell.button setTitle:NSLocalizedString(@"Stop",nil) forState:UIControlStateNormal];
		[cell.activityView startAnimating];
		[self.navigationItem setHidesBackButton:YES animated:YES];
		++_activityCount;
		[self downloadFileForCell:cell];
	}
}

@end
