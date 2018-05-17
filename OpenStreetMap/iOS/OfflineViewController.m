//
//  OfflineViewController.m
//  OSMiOS
//
//  Created by Bryce Cogswell on 12/27/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import "AppDelegate.h"
#import "MapView.h"
#import "MercatorTileLayer.h"
#import "OfflineViewController.h"
#import "UITableViewCell+FixConstraints.h"


@implementation OfflineTableViewCell
- (void)layoutSubviews
{
	[super layoutSubviews];
	[self.contentView layoutIfNeeded];
}

@end


@implementation OfflineViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	
	self.tableView.estimatedRowHeight = 100;
	self.tableView.rowHeight = UITableViewAutomaticDimension;
}

- (void)viewDidAppear:(BOOL)animated
{
	[super viewDidAppear:animated];
	[self.tableView reloadData];
}

- (void)viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];
	for ( OfflineTableViewCell * cell in @[ _aerialCell, _mapnikCell ] ) {
		[cell.activityView stopAnimating];
	}
}

-(NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
	return 1;
}
-(NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	return 2;
}
-(NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
	return @"Download zoomed tiles";
}
-(NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
	return @"If you are mapping somewhere with limited connectivity you can download the aerial and/or Mapnik tiles for the next two higher zoom levels that are in the current view area.";
}

-(OfflineTableViewCell *)newCellWithTitle:(NSString *)title tileLayer:(MercatorTileLayer *)tileLayer
{
	OfflineTableViewCell * cell = [self.tableView dequeueReusableCellWithIdentifier:@"OfflineTableViewCell"];
	cell.titleLabel.text	= title;
	cell.tileLayer 			= tileLayer;
	// common stuff
	cell.tileList			= [cell.tileLayer allTilesIntersectingVisibleRect];
	cell.detailLabel.text 	= [NSString stringWithFormat:NSLocalizedString(@"%lu tiles needed",nil), (unsigned long)cell.tileList.count];
	cell.button.enabled 	= cell.tileList.count > 0;
	return cell;
}

-(UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	if ( indexPath.row == 0 ) {
		if ( _aerialCell == nil ) {
			_aerialCell = [self newCellWithTitle:@"Aerial Tiles" tileLayer:AppDelegate.getAppDelegate.mapView.aerialLayer];
		}
		return _aerialCell;
	} else {
		if ( _mapnikCell == nil ) {
			_mapnikCell = [self newCellWithTitle:@"Mapnik Tiles" tileLayer:AppDelegate.getAppDelegate.mapView.mapnikLayer];
		}
		return _mapnikCell;
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
