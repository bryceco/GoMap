//
//  GpxViewController.m
//  Go Map!!
//
//  Created by Bryce on 2/26/13.
//  Copyright (c) 2013 Bryce. All rights reserved.
//

#import "AppDelegate.h"
#import "DLog.h"
#import "MapView.h"
#import "GpxLayer.h"
#import "GpxViewController.h"
#import "OsmMapData.h"


@interface GpxTrackTableCell : UITableViewCell
@property (assign,nonatomic)	IBOutlet	UILabel				*	startDate;
@property (assign,nonatomic)	IBOutlet	UILabel				*	duration;
@property (assign,nonatomic)	IBOutlet	UILabel				*	details;
@property (strong,nonatomic)				GpxTrack			*	gpxTrack;
@property (assign,nonatomic)				GpxViewController	*	tableView;
@end
@implementation GpxTrackTableCell
-(IBAction)doAction:(id)sender
{
	[self.tableView shareTrack:_gpxTrack];
}
@end



@implementation GpxViewController

- (void)viewDidLoad
{
	[super viewDidLoad];

	_navigationBar.topItem.rightBarButtonItem = self.editButtonItem;
	self.navigationItem.rightBarButtonItem = self.editButtonItem;
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

	if ( indexPath.section == 0 && appDelegate.mapView.gpxLayer.activeTrack == nil ) {
		// no active track
		GpxTrackTableCell *cell = [tableView dequeueReusableCellWithIdentifier:@"GpxTrackTableCell" forIndexPath:indexPath];
		cell.startDate.text = @"No active track";
		cell.duration.text = nil;
		cell.details.text = nil;
		cell.gpxTrack = nil;
		cell.tableView = self;
		return cell;
	}

	GpxTrack *	track = indexPath.section == 0 ? appDelegate.mapView.gpxLayer.activeTrack : appDelegate.mapView.gpxLayer.previousTracks[ indexPath.row ];
	NSInteger	dur = track.duration;
	NSString * startDate = [NSDateFormatter localizedStringFromDate:track.startDate dateStyle:kCFDateFormatterShortStyle timeStyle:kCFDateFormatterShortStyle];
	NSString * duration = [NSString stringWithFormat:@"%d:%02d:%02d", (int)(dur/3600), (int)(dur/60%60), (int)(dur%60)];
	NSString * meters = [NSString stringWithFormat:@"%ld meters, %ld points", (long)track.distance, (long)track.points.count];
	GpxTrackTableCell * cell = [tableView dequeueReusableCellWithIdentifier:@"GpxTrackTableCell" forIndexPath:indexPath];
	cell.startDate.text = startDate;
	cell.duration.text = duration;
	cell.details.text = meters;
	cell.gpxTrack = track;
	cell.tableView = self;
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
		GpxTrack * track = appDelegate.mapView.gpxLayer.previousTracks[ indexPath.row ];
		[appDelegate.mapView.gpxLayer deleteTrack:track];

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

-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	if ( indexPath.section == 0 ) {

	} else if ( indexPath.section == 1 ) {
		AppDelegate * appDelegate = [[UIApplication sharedApplication] delegate];
		GpxTrack * track = appDelegate.mapView.gpxLayer.previousTracks[ indexPath.row ];
		[appDelegate.mapView.gpxLayer centerOnTrack:track];
		[self.navigationController popToRootViewControllerAnimated:YES];
	}
}

-(void)shareTrack:(GpxTrack *)track
{
	AppDelegate * appDelegate = [[UIApplication sharedApplication] delegate];

	NSString * url = [OSM_API_URL stringByAppendingFormat:@"api/0.6/gpx/create"];

	NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:url]];
	NSString * boundary = @"----------------------------d10f7aa230e8";
	[request setHTTPMethod:@"POST"];
	[request setCachePolicy:NSURLRequestReloadIgnoringLocalCacheData];
	NSString * contentType = [NSString stringWithFormat:@"multipart/form-data;boundary=%@",boundary];
	[request setValue:contentType forHTTPHeaderField:@"Content-Type"];

	NSMutableData * body = [NSMutableData new];
	[body appendData:[[NSString stringWithFormat:@"\n--%@\n",boundary]   dataUsingEncoding:NSUTF8StringEncoding]];
	[body appendData:[[NSString stringWithString:[NSString stringWithFormat: @"Content-Disposition: form-data; name=\"file\"; filename=\"file.gpx\"\n"]] dataUsingEncoding:NSUTF8StringEncoding]];
	[body appendData:[@"Content-Type: application/octet-stream\n\n" dataUsingEncoding:NSUTF8StringEncoding]];
	[body appendData:track.gpxXmlData];

	[body appendData:[[NSString stringWithFormat:@"\n--%@\n",boundary]   dataUsingEncoding:NSUTF8StringEncoding]];
	[body appendData:[[NSString stringWithString:[NSString stringWithFormat: @"Content-Disposition: form-data; name=\"description\"\n\n"]] dataUsingEncoding:NSUTF8StringEncoding]];
	[body appendData:[@"GoMap!! GPX upload" dataUsingEncoding:NSUTF8StringEncoding]];

	[body appendData:[[NSString stringWithFormat:@"\n--%@\n",boundary]   dataUsingEncoding:NSUTF8StringEncoding]];
	[body appendData:[[NSString stringWithString:[NSString stringWithFormat: @"Content-Disposition: form-data; name=\"tags\"\n\n"]] dataUsingEncoding:NSUTF8StringEncoding]];
	[body appendData:[@"GoMap!!" dataUsingEncoding:NSUTF8StringEncoding]];

	[body appendData:[[NSString stringWithFormat:@"\n--%@\n",boundary]   dataUsingEncoding:NSUTF8StringEncoding]];
	[body appendData:[[NSString stringWithString:[NSString stringWithFormat: @"Content-Disposition: form-data; name=\"public\"\n\n"]] dataUsingEncoding:NSUTF8StringEncoding]];
	[body appendData:[@"1" dataUsingEncoding:NSUTF8StringEncoding]];

	[body appendData:[[NSString stringWithFormat:@"\n--%@\n",boundary]   dataUsingEncoding:NSUTF8StringEncoding]];
	[body appendData:[[NSString stringWithString:[NSString stringWithFormat: @"Content-Disposition: form-data; name=\"visibility\"\n\n"]] dataUsingEncoding:NSUTF8StringEncoding]];
	[body appendData:[@"public" dataUsingEncoding:NSUTF8StringEncoding]];

	[body appendData:[[NSString stringWithFormat:@"\n--%@--\n",boundary] dataUsingEncoding:NSUTF8StringEncoding]];
	[request setHTTPBody:body];

	[request setValue:[NSString stringWithFormat:@"%ld", (long)body.length] forHTTPHeaderField:@"Content-Length"];

	NSString * auth = [NSString stringWithFormat:@"%@:%@", appDelegate.userName, appDelegate.userPassword];
	auth = [OsmMapData encodeBase64:auth];
	auth = [NSString stringWithFormat:@"Basic %@", auth];
	[request setValue:auth forHTTPHeaderField:@"Authorization"];

	DLog(@"body = %@",[NSString stringWithUTF8String:body.bytes] );

	[NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue mainQueue] completionHandler:^(NSURLResponse * response, NSData * data, NSError * error) {
		if ( data && error == nil ) {
			// ok
		} else {
			NSString * errorMessage;
			if ( data.length > 0 ) {
				errorMessage = [[NSString alloc] initWithBytes:data.bytes length:data.length encoding:NSUTF8StringEncoding];
			} else {
				errorMessage = error.localizedDescription;
			}
			// failure
		}
	}];
}

@end
