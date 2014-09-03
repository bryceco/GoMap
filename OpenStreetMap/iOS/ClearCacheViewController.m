//
//  ClearCacheViewController.m
//  OSMiOS
//
//  Created by Bryce Cogswell on 12/15/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import "AppDelegate.h"
#import "ClearCacheViewController.h"
#import "EditorMapLayer.h"
#import "MapView.h"
#import "MercatorTileLayer.h"
#import "OsmMapData.h"




@implementation ClearCacheViewController

- (id)initWithStyle:(UITableViewStyle)style
{
    self = [super initWithStyle:style];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
}

#pragma mark - Table view data source

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];

	AppDelegate * appDelegate = [[UIApplication sharedApplication] delegate];
	OsmMapData * mapData = appDelegate.mapView.editorLayer.mapData;

	NSInteger objectCount = mapData.nodeCount + mapData.wayCount + mapData.relationCount;
	_osmDetail.text = [NSString stringWithFormat:NSLocalizedString(@"%ld objects",nil), (long)objectCount];
	_aerialDetail.text = NSLocalizedString(@"computing size...",nil);
	_mapnikDetail.text = NSLocalizedString(@"computing size...",nil);

	// aerial
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		NSInteger size = [appDelegate.mapView.aerialLayer diskCacheSize];
		dispatch_async(dispatch_get_main_queue(), ^{
			_aerialDetail.text = [NSString stringWithFormat:NSLocalizedString(@"%.2f MB",nil), (double)size/(1024*1024)];
		});
	});

	// mapnik
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		NSInteger size = [appDelegate.mapView.mapnikLayer diskCacheSize];
		dispatch_async(dispatch_get_main_queue(), ^{
			_mapnikDetail.text = [NSString stringWithFormat:NSLocalizedString(@"%.2f MB",nil), (double)size/(1024*1024)];
		});
	});

	// locator overlay
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		NSInteger size = [appDelegate.mapView.locatorLayer diskCacheSize];
		dispatch_async(dispatch_get_main_queue(), ^{
			_locatorDetail.text = [NSString stringWithFormat:NSLocalizedString(@"%.2f MB",nil), (double)size/(1024*1024)];
		});
	});

	// gps overlay
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		NSInteger size = [appDelegate.mapView.gpsTraceLayer diskCacheSize];
		dispatch_async(dispatch_get_main_queue(), ^{
			_gpsTraceDetail.text = [NSString stringWithFormat:NSLocalizedString(@"%.2f MB",nil), (double)size/(1024*1024)];
		});
	});
}

#pragma mark - Table view delegate

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
	if ( buttonIndex == 1 ) {
		AppDelegate * appDelegate = [[UIApplication sharedApplication] delegate];
		[appDelegate.mapView.editorLayer purgeCachedDataHard:YES];
	}
	[self.navigationController popViewControllerAnimated:YES];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	AppDelegate * appDelegate = [[UIApplication sharedApplication] delegate];

	switch ( indexPath.row ) {
		case 0:	// OSM
			if ( [appDelegate.mapView.editorLayer.mapData changesetAsXml] ) {
				UIAlertView * alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Warning",nil) message:NSLocalizedString(@"You have made changes that have not yet been uploaded to the server. Clearing the cache will cause those changes to be lost.",nil) delegate:self cancelButtonTitle:NSLocalizedString(@"Cancel",nil) otherButtonTitles:NSLocalizedString(@"Purge",nil), nil];
				[alertView show];
				return;
			}
			[appDelegate.mapView.editorLayer purgeCachedDataHard:YES];
			[appDelegate.mapView removePin];
			break;
		case 1:	// Bing
			[appDelegate.mapView.aerialLayer purgeTileCache];
			break;
		case 2:	// Mapnik
			[appDelegate.mapView.mapnikLayer purgeTileCache];
			break;
		case 3:	// Locator Overlay
			[appDelegate.mapView.locatorLayer purgeTileCache];
			break;
		case 4:	// GPS Overlay
			[appDelegate.mapView.gpsTraceLayer purgeTileCache];
			break;
	}
	[self.navigationController popViewControllerAnimated:YES];
}

@end
