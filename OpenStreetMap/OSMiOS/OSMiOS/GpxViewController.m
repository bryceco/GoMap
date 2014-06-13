//
//  GpxViewController.m
//  Go Map!!
//
//  Created by Bryce on 2/26/13.
//  Copyright (c) 2013 Bryce. All rights reserved.
//

#import "AppDelegate.h"
#import "MapView.h"
#import "GpxLayer.h"
#import "GpxViewController.h"


@interface GpxEndTableViewCell : UITableViewCell
@property (assign,nonatomic)	IBOutlet UILabel * label;
@end
@implementation GpxEndTableViewCell
@end



@implementation GpxViewController

- (void)viewDidLoad
{
	[super viewDidLoad];

	_navigationBar.topItem.rightBarButtonItem = self.editButtonItem;

	AppDelegate * appDelegate = [[UIApplication sharedApplication] delegate];
	NSDate * startDate = appDelegate.mapView.gpxLayer.activeTrack.startDate;
	if ( startDate ) {
		[self startTimerForStartDate:startDate];
	}
}

-(void)startTimerForStartDate:(NSDate *)date
{
	NSDate * now = [NSDate date];
	NSTimeInterval delta = [now timeIntervalSinceDate:date];
	delta = 1 - fmod(delta,1.0);
	date = [now dateByAddingTimeInterval:delta];
	_timer = [[NSTimer alloc] initWithFireDate:date interval:1.0 target:self selector:@selector(timerFired:) userInfo:nil repeats:YES];

	NSRunLoop *runloop = [NSRunLoop currentRunLoop];
	[runloop addTimer:_timer forMode:NSDefaultRunLoopMode];
}

-(void)timerFired:(NSTimer *)timer
{
	AppDelegate * appDelegate = [[UIApplication sharedApplication] delegate];
	GpxTrack * track = appDelegate.mapView.gpxLayer.activeTrack;
	if ( track ) {
		NSIndexPath * index = [NSIndexPath indexPathForRow:0 inSection:0];
		[self.tableView reloadRowsAtIndexPaths:@[index] withRowAnimation:UITableViewRowAnimationNone];
	} else {
		[_timer invalidate];
		_timer = nil;
	}
}

-(IBAction)cancel:(id)sender
{
	[self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Start/End Track

-(IBAction)startTrack:(id)sender
{
	AppDelegate * appDelegate = [[UIApplication sharedApplication] delegate];
	[appDelegate.mapView.gpxLayer startNewTrack];
	[self startTimerForStartDate:[NSDate date]];

#if 1
	[self.tableView reloadData];
#else
	[self dismissViewControllerAnimated:YES completion:nil];
#endif
}

-(IBAction)endTrack:(id)sender
{
	AppDelegate * appDelegate = [[UIApplication sharedApplication] delegate];
	[appDelegate.mapView.gpxLayer endActiveTrack];

	self.editButtonItem.enabled = appDelegate.mapView.gpxLayer.previousTracks.count > 0;
	[self.tableView reloadData];
}


#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
	return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	if ( section == 0 ) {
		return 1;
	} else {
		AppDelegate * appDelegate = [[UIApplication sharedApplication] delegate];
		return appDelegate.mapView.gpxLayer.previousTracks.count;
	}
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
	return section == 0 ? @"Current Track" : @"Previous Tracks";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
	if ( section == 0 ) {
		return @"A GPX Track records your path as you travel along a road or trail";
	}
	return nil;
}


- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	AppDelegate * appDelegate = [[UIApplication sharedApplication] delegate];

	if ( indexPath.section == 0 ) {
		if ( appDelegate.mapView.gpxLayer.activeTrack ) {
			// recording
			GpxEndTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"StopCell" forIndexPath:indexPath];
			GpxTrack * track = appDelegate.mapView.gpxLayer.activeTrack;
			NSInteger	duration = track.duration;
			NSString * text = [NSString stringWithFormat:@"%d:%02d:%02d, %ld meters",
							   (int)(duration/3600), (int)(duration/60%60), (int)(duration%60), (long)track.distance];
			cell.label.text = text;
			return cell;
		} else {
			// not recording
			UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"StartCell" forIndexPath:indexPath];
			return cell;
		}
	}

	GpxTrack *	track = appDelegate.mapView.gpxLayer.previousTracks[ indexPath.row ];
	NSInteger	duration = track.duration;
	NSString * start = [NSDateFormatter localizedStringFromDate:track.startDate dateStyle:kCFDateFormatterShortStyle timeStyle:kCFDateFormatterShortStyle];
	NSString * text = [NSString stringWithFormat:@"%@, %d:%02d:%02d, %ld meters",
					   start, (int)(duration/3600), (int)(duration/60%60), (int)(duration%60), (long)track.distance];

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell" forIndexPath:indexPath];
    cell.textLabel.text = [NSString stringWithFormat:@"Track %ld", (long)indexPath.row];
	cell.detailTextLabel.text = text;
	return cell;
}

// Override to support conditional editing of the table view.
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    return indexPath.section > 0;
}

// Override to support editing the table view.
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        // Delete the row from the data source
		AppDelegate * appDelegate = [[UIApplication sharedApplication] delegate];
		[appDelegate.mapView.gpxLayer.previousTracks removeObjectAtIndex:indexPath.row];

        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
    } else if (editingStyle == UITableViewCellEditingStyleInsert) {
        // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
    }   
}


/*
// Override to support rearranging the table view.
- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)fromIndexPath toIndexPath:(NSIndexPath *)toIndexPath
{
}
*/

/*
// Override to support conditional rearranging of the table view.
- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath
{
    // Return NO if you do not want the item to be re-orderable.
    return YES;
}
*/

#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    // Navigation logic may go here. Create and push another view controller.
    /*
     <#DetailViewController#> *detailViewController = [[<#DetailViewController#> alloc] initWithNibName:@"<#Nib name#>" bundle:nil];
     // ...
     // Pass the selected object to the new view controller.
     [self.navigationController pushViewController:detailViewController animated:YES];
     */
}

@end
