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
@end


@implementation OfflineViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	
	self.tableView.estimatedRowHeight = UITableViewAutomaticDimension;
	self.tableView.rowHeight = UITableViewAutomaticDimension;

	AppDelegate * appDelegate = [AppDelegate getAppDelegate];

	_aerialCell.tileLayer 	= appDelegate.mapView.aerialLayer;
	_mapnikCell.tileLayer	= appDelegate.mapView.mapnikLayer;

	for ( OfflineTableViewCell * cell in @[ _aerialCell, _mapnikCell ] ) {
		cell.tileList = [cell.tileLayer allTilesIntersectingVisibleRect];
		cell.detailLabel.text = [NSString stringWithFormat:NSLocalizedString(@"%lu tiles needed",nil), (unsigned long)cell.tileList.count];
		cell.button.enabled = cell.tileList.count > 0;
	}
	
#if 0
	[self.tableView reloadData];
	dispatch_async(dispatch_get_main_queue(), ^{
		[self.tableView reloadData];
	});
#endif
}

- (void)viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];
	for ( OfflineTableViewCell * cell in @[ _aerialCell, _mapnikCell ] ) {
		[cell.activityView stopAnimating];
	}
}

-(CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
	return UITableViewAutomaticDimension;
//	UITableViewCell * cell = [tableView cellForRowAtIndexPath:indexPath];
//	CGSize size = [cell.contentView systemLayoutSizeFittingSize:UILayoutFittingCompressedSize];
//	return size.height;
}
-(CGFloat)tableView:(UITableView *)tableView estimatedHeightForRowAtIndexPath:(NSIndexPath *)indexPath
{
	return UITableViewAutomaticDimension;
}

#if 0
-(void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
	[cell fixConstraints];
}
#endif

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
