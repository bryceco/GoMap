//
//  ClearCacheViewController.m
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/15/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import "AppDelegate.h"
#import "ClearCacheViewController.h"
#import "EditorMapLayer.h"
#import "GpxLayer.h"
#import "MapView.h"
#import "MercatorTileLayer.h"
#import "OsmMapData.h"


@interface ClearCacheCell : UITableViewCell
@property (assign) IBOutlet UILabel * titleLabel;
@property (assign) IBOutlet UILabel * detailLabel;
@end
@implementation ClearCacheCell
@end



@implementation ClearCacheViewController

enum {
	ROW_OSM_DATA	= 0,
	ROW_MAPNIK		= 1,
	ROW_AERIAL		= 2,
	ROW_BREADCRUMB	= 3,
	ROW_LOCATOR		= 4,
	ROW_GPS			= 5
};


#pragma mark - Table view data source


- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];

	self.tableView.rowHeight = UITableViewAutomaticDimension;
	self.tableView.estimatedRowHeight = 44;

	AppDelegate * appDelegate = [AppDelegate getAppDelegate];
	OsmMapData * mapData = appDelegate.mapView.editorLayer.mapData;

	_automaticCacheManagement.on = appDelegate.mapView.enableAutomaticCacheManagement;

	NSArray * layers = @[
						 @[ NSLocalizedString(@"Clear OSM Data",nil),					@(ROW_OSM_DATA),	[NSNull null] ],
						 @[ NSLocalizedString(@"Clear Mapnik Tiles",nil),				@(ROW_MAPNIK), 		appDelegate.mapView.mapnikLayer ],
						 @[ NSLocalizedString(@"Clear GPX Tracks",nil),					@(ROW_BREADCRUMB), 	appDelegate.mapView.gpxLayer ],
						 @[ NSLocalizedString(@"Clear Aerial Tiles",nil),				@(ROW_AERIAL), 		appDelegate.mapView.aerialLayer ],
						 @[ NSLocalizedString(@"Clear Locator Overlay Tiles",nil),		@(ROW_LOCATOR),		appDelegate.mapView.locatorLayer ],
						 @[ NSLocalizedString(@"Clear GPS Overlay Tiles",nil),			@(ROW_GPS),			appDelegate.mapView.gpsTraceLayer ]
					];

	for ( NSArray * layerInfo in layers ) {
		NSString	* title = layerInfo[0];
		NSNumber	* row   = layerInfo[1];
		NSObject	* object = layerInfo[2];

		ClearCacheCell 	* cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:row.integerValue inSection:1]];

		cell.titleLabel.text = title;
		cell.detailLabel.text = @"";

		if ( row.integerValue == ROW_OSM_DATA ) {
			NSInteger objectCount = mapData.nodeCount + mapData.wayCount + mapData.relationCount;
			cell.detailLabel.text = [NSString stringWithFormat:NSLocalizedString(@"%ld objects",nil), (long)objectCount];
		} else {
			cell.detailLabel.text = NSLocalizedString(@"computing size...",nil);
			dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
				NSInteger size, count;
				[(id)object diskCacheSize:&size count:&count];
				dispatch_async(dispatch_get_main_queue(), ^{
					cell.detailLabel.text = [NSString stringWithFormat:NSLocalizedString(@"%.2f MB, %d files",nil), (double)size/(1024*1024), count];
				});
			});
		}
	}
}

-(void)viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];

	AppDelegate * appDelegate = [AppDelegate getAppDelegate];
	appDelegate.mapView.enableAutomaticCacheManagement = _automaticCacheManagement.on;
}

#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	AppDelegate * appDelegate = [AppDelegate getAppDelegate];

	if ( indexPath.section == 0 ) {
		return;
	}

	switch ( indexPath.row ) {
		case ROW_OSM_DATA:	// OSM
			if ( [appDelegate.mapView.editorLayer.mapData changesetAsXml] ) {
				UIAlertController * alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Warning",nil)
																				message:NSLocalizedString(@"You have made changes that have not yet been uploaded to the server. Clearing the cache will cause those changes to be lost.",nil)
																		 preferredStyle:UIAlertControllerStyleAlert];
				[alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel",nil) style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
					[self.navigationController popViewControllerAnimated:YES];
				}]];
				[alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Purge",nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
					[appDelegate.mapView.editorLayer purgeCachedDataHard:YES];
					[self.navigationController popViewControllerAnimated:YES];
				}]];
				[self presentViewController:alert animated:YES completion:nil];
				return;
			}
			[appDelegate.mapView.editorLayer purgeCachedDataHard:YES];
			[appDelegate.mapView removePin];
			break;
		case ROW_MAPNIK:	// Mapnik
			[appDelegate.mapView.mapnikLayer purgeTileCache];
			break;
		case ROW_BREADCRUMB:	// Breadcrumb
			[appDelegate.mapView.gpxLayer purgeTileCache];
			break;
		case ROW_AERIAL:	// Bing
			[appDelegate.mapView.aerialLayer purgeTileCache];
			break;
		case ROW_LOCATOR:	// Locator Overlay
			[appDelegate.mapView.locatorLayer purgeTileCache];
			break;
		case ROW_GPS:	// GPS Overlay
			[appDelegate.mapView.gpsTraceLayer purgeTileCache];
			break;
	}
	[self dismissViewControllerAnimated:YES completion:nil];
}

@end
