//
//  GpxViewController.m
//  Go Map!!
//
//  Created by Bryce Cogswell on 2/26/13.
//  Copyright (c) 2013 Bryce Cogswell. All rights reserved.
//

#import "AppDelegate.h"
#import "DLog.h"
#import "MapView.h"
#import "GpxConfigureViewController.h"
#import "GpxLayer.h"
#import "GpxViewController.h"
#import "OsmMapData.h"


#define SECTION_CONFIGURE			0
#define SECTION_ACTIVE_TRACK 		1
#define SECTION_PREVIOUS_TRACKS		2



@interface GpxTrackTableCell : UITableViewCell <UIActionSheetDelegate, MFMailComposeViewControllerDelegate>
@property (assign,nonatomic)	IBOutlet	UILabel				*	startDate;
@property (assign,nonatomic)	IBOutlet	UILabel				*	duration;
@property (assign,nonatomic)	IBOutlet	UILabel				*	details;
@property (assign,nonatomic)	IBOutlet	UIButton			*	uploadButton;
@property (strong,nonatomic)				GpxTrack			*	gpxTrack;
@property (assign,nonatomic)				GpxViewController	*	tableView;
@end
@implementation GpxTrackTableCell
-(IBAction)doAction:(id)sender
{
	UIAlertController * alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Share",@"Title for sharing options") message:nil preferredStyle:UIAlertControllerStyleActionSheet];
	[alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel",nil) style:UIAlertActionStyleCancel handler:nil]];
	[alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Upload to OSM",nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
		[self.tableView shareTrack:_gpxTrack];
	}]];
	[alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Share",@"Open iOS sharing sheet") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
		NSString * fileName = [NSString stringWithFormat:@"%@ %@.gpx", AppDelegate.shared.appName, self.gpxTrack.creationDate];
		NSURL * url = [NSFileManager.defaultManager.temporaryDirectory URLByAppendingPathComponent:fileName];
		NSString * gpx = self.gpxTrack.gpxXmlString;
		[NSFileManager.defaultManager removeItemAtURL:url error:NULL];
		if ( [gpx writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:NULL] ) {
			UIActivityViewController * controller = [[UIActivityViewController alloc] initWithActivityItems:@[fileName,url] applicationActivities:nil];
			controller.completionWithItemsHandler = ^(UIActivityType activityType, BOOL completed, NSArray *returnedItems, NSError *activityError){
				if ( completed ) {
					GpxLayer * gpxLayer = AppDelegate.shared.mapView.gpxLayer;
					[gpxLayer markTrackUploaded:self.gpxTrack];
					[self.tableView.tableView reloadData];
				}
			};
			[self.tableView presentViewController:controller animated:YES completion:nil];
		}
	}]];

	[self.tableView presentViewController:alert animated:YES completion:nil];
	// set location of popup
	UIButton * button = sender;
	alert.popoverPresentationController.sourceView = button;
	alert.popoverPresentationController.sourceRect = button.bounds;
}
@end

@interface GpxTrackBackgroundCollection : UITableViewCell
@property (assign,nonatomic)	IBOutlet	UISwitch	*	enableBackground;
@end
@implementation GpxTrackBackgroundCollection
-(IBAction)enableBackground:(id)sender
{
	UISwitch * toggle = sender;
	AppDelegate * appDelegate = AppDelegate.shared;
	appDelegate.mapView.gpsInBackground = [toggle isOn];
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

	self.tableView.estimatedRowHeight = 44;
	self.tableView.rowHeight = UITableViewAutomaticDimension;

	_navigationBar.topItem.rightBarButtonItem = self.editButtonItem;
	self.navigationItem.rightBarButtonItem = self.editButtonItem;

	AppDelegate * appDelegate = AppDelegate.shared;
	[appDelegate.mapView.gpxLayer loadTracksInBackgroundWithProgress:^{
		[self.tableView reloadData];
	}];
}


-(void)viewDidAppear:(BOOL)animated
{
	[super viewDidAppear:animated];

	AppDelegate * appDelegate = AppDelegate.shared;
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
	AppDelegate * appDelegate = AppDelegate.shared;
	GpxTrack * track = appDelegate.mapView.gpxLayer.activeTrack;
	if ( track ) {
		NSIndexPath * index = [NSIndexPath indexPathForRow:0 inSection:SECTION_ACTIVE_TRACK];
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
	if ( section == SECTION_ACTIVE_TRACK ) {
		// active track
		return 1;
	} else if ( section == SECTION_PREVIOUS_TRACKS ) {
		// previous tracks
		AppDelegate * appDelegate = AppDelegate.shared;
		return appDelegate.mapView.gpxLayer.previousTracks.count;
	} else if ( section == SECTION_CONFIGURE ) {
		// configuration
		return 2;
	} else {
		return 0;
	}
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
	switch (section) {
		case SECTION_ACTIVE_TRACK:
			return NSLocalizedString(@"Current Track",@"current GPX track");
		case SECTION_PREVIOUS_TRACKS:
			return NSLocalizedString(@"Previous Tracks","previous GPX track");
		case SECTION_CONFIGURE:
			return NSLocalizedString(@"Configure",nil);
		default:
			return nil;
	}
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
	if ( section == SECTION_ACTIVE_TRACK ) {
		return NSLocalizedString(@"A GPX Track records your path as you travel along a road or trail",nil);
	}
	return nil;
}


- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	MapView * mapView = AppDelegate.shared.mapView;
	GpxLayer * gpxLayer = mapView.gpxLayer;

	if ( indexPath.section == SECTION_ACTIVE_TRACK && gpxLayer.activeTrack == nil ) {
		// no active track
		UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
		cell.textLabel.text = NSLocalizedString(@"No active track",@"GPX track");
		return cell;
	}
	if ( indexPath.section == SECTION_CONFIGURE ) {
		// configuration section
		if ( indexPath.row == 0 ) {
			// days before deleting
			GpxTrackExpirationCell * cell = [tableView dequeueReusableCellWithIdentifier:@"GpxTrackExpirationCell" forIndexPath:indexPath];
			NSNumber * expirationDays = [[NSUserDefaults standardUserDefaults] objectForKey:USER_DEFAULTS_GPX_EXPIRATIION_KEY];
			NSInteger expiration = [expirationDays integerValue];
			NSString * title = expiration <= 0 ? NSLocalizedString(@"Never",@"Never delete old tracks") : [NSString stringWithFormat:NSLocalizedString(@"%ld Days",@"One or more days"),(long)expiration];
			[cell.expirationButton setTitle:title forState:UIControlStateNormal];
			[cell.expirationButton sizeToFit];
			return cell;
		} else {
			// enable background use
			GpxTrackBackgroundCollection * cell = [tableView dequeueReusableCellWithIdentifier:@"GpxTrackBackgroundCollection" forIndexPath:indexPath];
			[cell.enableBackground setOn:mapView.gpsInBackground];
			return cell;
		}
	}

	// active track or previous tracks
	GpxTrack *	track = indexPath.section == SECTION_ACTIVE_TRACK ? gpxLayer.activeTrack : gpxLayer.previousTracks[ indexPath.row ];
	NSInteger	dur = (NSInteger)round(track.duration);
	NSString * startDate = [NSDateFormatter localizedStringFromDate:track.creationDate dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle];
	NSString * duration = [NSString stringWithFormat:@"%d:%02d:%02d", (int)(dur/3600), (int)(dur/60%60), (int)(dur%60)];
	NSString * meters = [NSString stringWithFormat:NSLocalizedString(@"%ld meters, %ld points",@"length of a gpx track"), (long)track.distance, (long)track.points.count];
	GpxTrackTableCell * cell = [tableView dequeueReusableCellWithIdentifier:@"GpxTrackTableCell" forIndexPath:indexPath];
	cell.startDate.text = startDate;
	cell.duration.text = duration;
	cell.details.text = meters;
	cell.gpxTrack = track;
	cell.tableView = self;
	if ( gpxLayer.uploadedTracks[track.name] ) {
		[cell.uploadButton setImage:nil forState:UIControlStateNormal];
		[cell.uploadButton setTitle:@"\u2714" forState:UIControlStateNormal];
	} else {
		UIImage * image = [UIImage imageNamed:@"702-share"];
		[cell.uploadButton setImage:image forState:UIControlStateNormal];
		[cell.uploadButton setTitle:nil forState:UIControlStateNormal];
	}
	return cell;
}

// Override to support conditional editing of the table view.
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    return indexPath.section == SECTION_PREVIOUS_TRACKS;
}

// Override to support editing the table view.
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        // Delete the row from the data source
		GpxLayer * gpxLayer = AppDelegate.shared.mapView.gpxLayer;
		GpxTrack * track = gpxLayer.previousTracks[ indexPath.row ];
		[gpxLayer deleteTrack:track];

		[tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
    } else if (editingStyle == UITableViewCellEditingStyleInsert) {
        // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
    }   
}


#pragma mark - Table view delegate

- (nullable NSIndexPath *)tableView:(UITableView *)tableView willSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	if ( indexPath.section == SECTION_CONFIGURE )
		return nil;
	if ( indexPath.section == SECTION_ACTIVE_TRACK &&
		AppDelegate.shared.mapView.gpxLayer.activeTrack == nil )
	{
		// don't allow selecting the active track if there is none
		return nil;
	}
	return indexPath;
}

-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	if ( indexPath.section == SECTION_ACTIVE_TRACK ) {
		// active track
		GpxLayer * gpxLayer = AppDelegate.shared.mapView.gpxLayer;
		gpxLayer.selectedTrack = gpxLayer.activeTrack;
		[gpxLayer centerOnTrack:gpxLayer.selectedTrack];
		[self.navigationController dismissViewControllerAnimated:YES completion:nil];
	} else if ( indexPath.section == SECTION_CONFIGURE ) {
		// configuration
	} else if ( indexPath.section == SECTION_PREVIOUS_TRACKS ) {
		GpxLayer * gpxLayer = AppDelegate.shared.mapView.gpxLayer;
		GpxTrack *	track = gpxLayer.previousTracks[ indexPath.row ];
		gpxLayer.selectedTrack = track;
		[gpxLayer centerOnTrack:track];
		[self.navigationController dismissViewControllerAnimated:YES completion:nil];
	}
}

-(void)shareTrack:(GpxTrack *)track
{
	UIAlertController * progress = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Uploading GPX...",nil)
																	message:NSLocalizedString(@"Please wait",nil)
															 preferredStyle:UIAlertControllerStyleAlert];
	[self presentViewController:progress animated:YES completion:nil];

	// let progress window display before we submit work
	dispatch_async(dispatch_get_main_queue(), ^{
		AppDelegate * appDelegate = AppDelegate.shared;

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

		NSURLSessionDataTask * task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
			dispatch_async(dispatch_get_main_queue(), ^{
				[progress dismissViewControllerAnimated:YES completion:nil];

				NSHTTPURLResponse * httpResponse = [response isKindOfClass:[NSHTTPURLResponse class]] ? (id)response : nil;
				if ( httpResponse.statusCode == 200 ) {
					// ok
					UIAlertController * success = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"GPX Upload Complete",nil) message:nil preferredStyle:UIAlertControllerStyleAlert];
					[success addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK",nil) style:UIAlertActionStyleCancel handler:nil]];
					[self presentViewController:success animated:YES completion:nil];

					// mark track as uploaded in UI
					GpxLayer * gpxLayer = AppDelegate.shared.mapView.gpxLayer;
					[gpxLayer markTrackUploaded:track];
					[self.tableView reloadData];

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
					UIAlertController * failure = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"GPX Upload Failed",nil) message:errorMessage preferredStyle:UIAlertControllerStyleAlert];
					[failure addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK",nil) style:UIAlertActionStyleCancel handler:nil]];
					[self presentViewController:failure animated:YES completion:nil];
				}
			});
		}];
		[task resume];
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
				AppDelegate * appDelegate = AppDelegate.shared;
				NSDate * cutoff = [NSDate dateWithTimeIntervalSinceNow:-pick.doubleValue*24*60*60];
				[appDelegate.mapView.gpxLayer trimTracksOlderThan:cutoff];
			}
			[self.tableView reloadData];
		};
	}
}

@end
