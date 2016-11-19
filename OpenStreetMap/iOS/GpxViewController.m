//
//  GpxViewController.m
//  Go Map!!
//
//  Created by Bryce on 2/26/13.
//  Copyright (c) 2013 Bryce. All rights reserved.
//

#import <MessageUI/MessageUI.h>

#import "AppDelegate.h"
#import "DLog.h"
#import "MapView.h"
#import "GpxConfigureViewController.h"
#import "GpxLayer.h"
#import "GpxViewController.h"
#import "OsmMapData.h"



@interface GpxTrackTableCell : UITableViewCell <UIActionSheetDelegate, MFMailComposeViewControllerDelegate>
@property (assign,nonatomic)	IBOutlet	UILabel				*	startDate;
@property (assign,nonatomic)	IBOutlet	UILabel				*	duration;
@property (assign,nonatomic)	IBOutlet	UILabel				*	details;
@property (strong,nonatomic)				GpxTrack			*	gpxTrack;
@property (assign,nonatomic)				GpxViewController	*	tableView;
@end
@implementation GpxTrackTableCell
-(IBAction)doAction:(id)sender
{
	UIActionSheet * sheet = [[UIActionSheet alloc] initWithTitle:NSLocalizedString(@"Share",nil) delegate:self cancelButtonTitle:NSLocalizedString(@"Cancel",nil) destructiveButtonTitle:nil otherButtonTitles:NSLocalizedString(@"Upload to OSM",nil), NSLocalizedString(@"Mail",nil), nil];
	[sheet showInView:self];
}
- (void)actionSheet:(UIActionSheet *)actionSheet didDismissWithButtonIndex:(NSInteger)buttonIndex
{
	if ( buttonIndex == actionSheet.cancelButtonIndex ) {
		return;
	}
	if ( buttonIndex == 0 ) {
		// upload
		[self.tableView shareTrack:_gpxTrack];
	} else if ( buttonIndex == 1 ) {
		// mail
		if ( [MFMailComposeViewController canSendMail] ) {
			AppDelegate * appDelegate = [AppDelegate getAppDelegate];
			MFMailComposeViewController * mail = [[MFMailComposeViewController alloc] init];
			mail.mailComposeDelegate = self;
			[mail setSubject:[NSString stringWithFormat:@"%@ GPX file: %@", appDelegate.appName, self.gpxTrack.creationDate]];
			[mail addAttachmentData:self.gpxTrack.gpxXmlData mimeType:@"application/gpx+xml" fileName:[NSString stringWithFormat:@"%@.gpx", self.gpxTrack.creationDate]];
			[self.tableView presentViewController:mail animated:YES completion:nil];
		} else {
			UIAlertView * alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Cannot compose message",nil) message:NSLocalizedString(@"Mail delivery is not available on this device",nil) delegate:nil cancelButtonTitle:NSLocalizedString(@"OK",nil) otherButtonTitles:nil];
			[alert show];
		}
	}
}
-(void)mailComposeController:(MFMailComposeViewController*)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError*)error
{
	[controller dismissViewControllerAnimated:YES completion:nil];
}
@end


@interface GpxTrackExpirationCell : UITableViewCell
@property (assign,nonatomic)	IBOutlet	UIButton *	expirationButton;
@end
@implementation GpxTrackExpirationCell
@end


@implementation GpxViewController

- (void)viewDidLoad
{
	[super viewDidLoad];

	_navigationBar.topItem.rightBarButtonItem = self.editButtonItem;
	self.navigationItem.rightBarButtonItem = self.editButtonItem;

	AppDelegate * appDelegate = [AppDelegate getAppDelegate];
	[appDelegate.mapView.gpxLayer loadTracksInBackgroundWithProgress:^{
		[self.tableView reloadData];
	}];
}


-(void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];

	AppDelegate * appDelegate = [AppDelegate getAppDelegate];
	if ( appDelegate.mapView.gpxLayer.activeTrack ) {
		[self startTimerForStartDate:appDelegate.mapView.gpxLayer.activeTrack.creationDate];
	}
}

-(void)viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];
	
	[_timer invalidate];
	_timer = nil;
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
	AppDelegate * appDelegate = [AppDelegate getAppDelegate];
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
	return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	if ( section == 0 ) {
		return 1;
	} else if ( section == 1 ) {
		AppDelegate * appDelegate = [AppDelegate getAppDelegate];
		return appDelegate.mapView.gpxLayer.previousTracks.count;
	} else if ( section == 2 ) {
		return 1;
	} else {
		return 0;
	}
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
	switch (section) {
		case 0:
			return @"Current Track";
		case 1:
			return @"Previous Tracks";
		case 2:
			return @"Configure";
		default:
			return nil;
	}
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
	AppDelegate * appDelegate = [AppDelegate getAppDelegate];

	if ( indexPath.section == 0 && appDelegate.mapView.gpxLayer.activeTrack == nil ) {
		// no active track
		UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
		cell.textLabel.text = @"No active track";
		return cell;
	}
	if ( indexPath.section == 2 ) {
		GpxTrackExpirationCell * cell = [tableView dequeueReusableCellWithIdentifier:@"GpxTrackExpirationCell" forIndexPath:indexPath];
		NSNumber * expirationDays = [[NSUserDefaults standardUserDefaults] objectForKey:USER_DEFAULTS_GPX_EXPIRATIION_KEY];
		NSInteger expiration = [expirationDays integerValue];
		NSString * title = expiration <= 0 ? @"Never" : [NSString stringWithFormat:@"%ld Days",(long)expiration];
		[cell.expirationButton setTitle:title forState:UIControlStateNormal];
		[cell.expirationButton sizeToFit];
		return cell;
	}

	NSArray * prevTracks = appDelegate.mapView.gpxLayer.previousTracks;
	GpxTrack *	track = indexPath.section == 0 ? appDelegate.mapView.gpxLayer.activeTrack : prevTracks[ prevTracks.count - indexPath.row - 1 ];
	NSInteger	dur = (NSInteger)round(track.duration);
	NSString * startDate = [NSDateFormatter localizedStringFromDate:track.creationDate dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle];
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
    return indexPath.section == 1;
}

// Override to support editing the table view.
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        // Delete the row from the data source
		AppDelegate * appDelegate = [AppDelegate getAppDelegate];
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
		// active track
	} else if ( indexPath.section == 2 ) {
		// configuration
	} else if ( indexPath.section == 1 ) {
		AppDelegate * appDelegate = [AppDelegate getAppDelegate];
		GpxTrack * track = appDelegate.mapView.gpxLayer.previousTracks[ indexPath.row ];
		[appDelegate.mapView.gpxLayer centerOnTrack:track];
		[self.navigationController popToRootViewControllerAnimated:YES];
	}
}

-(void)shareTrack:(GpxTrack *)track
{
	UIAlertView * progress = [[UIAlertView alloc] initWithTitle:@"Uploading GPX..." message:@"Please wait" delegate:self cancelButtonTitle:nil otherButtonTitles:nil];
	[progress show];

	// let progress window display before we submit work
	dispatch_async(dispatch_get_main_queue(), ^{
		AppDelegate * appDelegate = [AppDelegate getAppDelegate];

		NSString * url = [OSM_API_URL stringByAppendingFormat:@"api/0.6/gpx/create"];

		NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:url]];
		NSString * boundary = @"----------------------------d10f7aa230e8";
		[request setHTTPMethod:@"POST"];
		NSString * contentType = [NSString stringWithFormat:@"multipart/form-data; boundary=%@",boundary];
		[request setValue:contentType	forHTTPHeaderField:@"Content-Type"];
		[request setValue:@"close"		forHTTPHeaderField:@"Connection"];

		NSDateFormatter * dateFormatter = [NSDateFormatter new];
		[dateFormatter setDateFormat:@"yyyy_MM_dd__HH_mm_ss"];
		NSString * startDateFile = [dateFormatter stringFromDate:track.creationDate];
		NSString * startDateFriendly = [NSDateFormatter localizedStringFromDate:track.creationDate dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle];

		NSMutableData * body = [NSMutableData new];
		[body appendData:[[NSString stringWithFormat:@"--%@\r\n",boundary]   dataUsingEncoding:NSUTF8StringEncoding]];
		[body appendData:[[NSString stringWithString:[NSString stringWithFormat: @"Content-Disposition: form-data; name=\"file\"; filename=\"GoMap__%@.gpx\"\r\n",startDateFile]] dataUsingEncoding:NSUTF8StringEncoding]];
		[body appendData:[@"Content-Type: application/octet-stream\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
		[body appendData:track.gpxXmlData];

		[body appendData:[[NSString stringWithFormat:@"\r\n--%@\r\n",boundary]   dataUsingEncoding:NSUTF8StringEncoding]];
		[body appendData:[[NSString stringWithString:[NSString stringWithFormat: @"Content-Disposition: form-data; name=\"description\"\r\n\r\n"]] dataUsingEncoding:NSUTF8StringEncoding]];
		[body appendData:[[NSString stringWithFormat:@"Go Map!! %@",startDateFriendly] dataUsingEncoding:NSUTF8StringEncoding]];

		[body appendData:[[NSString stringWithFormat:@"\r\n--%@\r\n",boundary]   dataUsingEncoding:NSUTF8StringEncoding]];
		[body appendData:[[NSString stringWithString:[NSString stringWithFormat: @"Content-Disposition: form-data; name=\"tags\"\r\n\r\n"]] dataUsingEncoding:NSUTF8StringEncoding]];
		[body appendData:[@"GoMap" dataUsingEncoding:NSUTF8StringEncoding]];

		[body appendData:[[NSString stringWithFormat:@"\r\n--%@\r\n",boundary]   dataUsingEncoding:NSUTF8StringEncoding]];
		[body appendData:[[NSString stringWithString:[NSString stringWithFormat: @"Content-Disposition: form-data; name=\"public\"\r\n\r\n"]] dataUsingEncoding:NSUTF8StringEncoding]];
		[body appendData:[@"1" dataUsingEncoding:NSUTF8StringEncoding]];

		[body appendData:[[NSString stringWithFormat:@"\r\n--%@\r\n",boundary]   dataUsingEncoding:NSUTF8StringEncoding]];
		[body appendData:[[NSString stringWithString:[NSString stringWithFormat: @"Content-Disposition: form-data; name=\"visibility\"\r\n\r\n"]] dataUsingEncoding:NSUTF8StringEncoding]];
		[body appendData:[@"public" dataUsingEncoding:NSUTF8StringEncoding]];

		[body appendData:[[NSString stringWithFormat:@"\r\n--%@--\r\n",boundary] dataUsingEncoding:NSUTF8StringEncoding]];
		[request setHTTPBody:body];

		[request setValue:[NSString stringWithFormat:@"%ld", (long)body.length] forHTTPHeaderField:@"Content-Length"];

		NSString * auth = [NSString stringWithFormat:@"%@:%@", appDelegate.userName, appDelegate.userPassword];
		auth = [OsmMapData encodeBase64:auth];
		auth = [NSString stringWithFormat:@"Basic %@", auth];
		[request setValue:auth forHTTPHeaderField:@"Authorization"];

//		DLog(@"body = %@",[NSString stringWithUTF8String:body.bytes] );

		[NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue mainQueue] completionHandler:^(NSURLResponse * response, NSData * data, NSError * error) {
			[progress dismissWithClickedButtonIndex:0 animated:YES];

			NSHTTPURLResponse * httpResponse = [response isKindOfClass:[NSHTTPURLResponse class]] ? (id)response : nil;
			if ( httpResponse.statusCode == 200 ) {
				// ok
				UIAlertView * success = [[UIAlertView alloc] initWithTitle:@"GPX Upload Complete" message:nil delegate:self cancelButtonTitle:@"OK" otherButtonTitles:nil];
				[success show];
			} else {
				DLog(@"response = %@\n",response);
				DLog(@"data = %s", (char *)data.bytes);
				NSString * errorMessage = nil;
				if ( data.length > 0 ) {
					errorMessage = [[NSString alloc] initWithBytes:data.bytes length:data.length encoding:NSUTF8StringEncoding];
				} else {
					errorMessage = error.localizedDescription;
				}
				// failure
				UIAlertView * failure = [[UIAlertView alloc] initWithTitle:@"GPX Upload Failed" message:errorMessage delegate:self cancelButtonTitle:@"OK" otherButtonTitles:nil];
				[failure show];
			}
		}];
	});
}


#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
	if ( [segue.destinationViewController isKindOfClass:[GpxConfigureViewController class]] ) {
		GpxConfigureViewController * dest = segue.destinationViewController;
		dest.expirationValue = [[NSUserDefaults standardUserDefaults] objectForKey:USER_DEFAULTS_GPX_EXPIRATIION_KEY];
		dest.completion = ^(NSNumber * pick){
			[[NSUserDefaults standardUserDefaults] setObject:pick forKey:USER_DEFAULTS_GPX_EXPIRATIION_KEY];

			if ( pick.doubleValue > 0 ) {
				AppDelegate * appDelegate = [AppDelegate getAppDelegate];
				NSDate * cutoff = [NSDate dateWithTimeIntervalSinceNow:-pick.doubleValue*24*60*60];
				[appDelegate.mapView.gpxLayer trimTracksOlderThan:cutoff];
			}
			[self.tableView reloadData];
		};
	}
}

@end
