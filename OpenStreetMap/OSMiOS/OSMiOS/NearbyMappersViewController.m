//
//  NearbyMappersViewController.m
//  OSMiOS
//
//  Created by Bryce Cogswell on 12/26/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import "AppDelegate.h"
#import "EditorMapLayer.h"
#import "OsmMapData.h"
#import "MapView.h"
#import "NearbyMappersViewController.h"
#import "WebPageViewController.h"


@implementation NearbyMappersViewController


- (void)viewDidLoad
{
    [super viewDidLoad];

	AppDelegate * appDelegate = [[UIApplication sharedApplication] delegate];

	OSMRect rect = [appDelegate.mapView viewportLongitudeLatitude];
	_mappers = [appDelegate.mapView.editorLayer.mapData userStatisticsForRegion:rect];

	_mappers = [_mappers sortedArrayUsingComparator:^NSComparisonResult(OsmUserStatistics * s1, OsmUserStatistics * s2) {
		return -[s1.lastEdit compare:s2.lastEdit];
	}];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return 	_mappers.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *CellIdentifier = @"Cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier forIndexPath:indexPath];

	OsmUserStatistics * stats = _mappers[ indexPath.row ];
	cell.textLabel.text = stats.user;
	NSString * date = [NSDateFormatter localizedStringFromDate:stats.lastEdit dateStyle:NSDateFormatterMediumStyle timeStyle:kCFDateFormatterNoStyle];
	cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld edits, last active %@", (long)stats.editCount, date];

    return cell;
}

#pragma mark - Table view delegate

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
	UITableViewCell * cell = sender;
	NSIndexPath * indexPath = [self.tableView indexPathForCell:cell];
	OsmUserStatistics * stats = [_mappers objectAtIndex:indexPath.row];
	NSString * user = stats.user;

	WebPageViewController * web = segue.destinationViewController;
	web.title = @"User";
	web.url = [NSString stringWithFormat:@"http://www.openstreetmap.org/user/%@", user];

	[super prepareForSegue:segue sender:sender];
}


@end
