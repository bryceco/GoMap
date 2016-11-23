//
//  SecondViewController.m
//  OSMiOS
//
//  Created by Bryce Cogswell on 12/6/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <sys/utsname.h>

#import "AppDelegate.h"
#import "AerialList.h"
#import "AerialListViewController.h"
#import "EditorMapLayer.h"
#import "MapView.h"
#import "MapViewController.h"
#import "MercatorTileLayer.h"
#import "SettingsViewController.h"
#import "UITableViewCell+FixConstraints.h"


@implementation SettingsViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];

	if ( [self isMovingToParentViewController] ) {
		// becoming visible the first time
		self.navigationController.navigationBarHidden = NO;
	}


	NSString * preferredLanguage = [[NSUserDefaults standardUserDefaults] objectForKey:@"preferredLanguage"];
	if ( preferredLanguage == nil ) {
		preferredLanguage = @"en";
	}
	NSLocale * locale =  [NSLocale localeWithLocaleIdentifier:preferredLanguage];
	preferredLanguage = [locale displayNameForKey:NSLocaleIdentifier value:preferredLanguage];
	_language.text = preferredLanguage;
}

-(void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
	[cell fixConstraints];
}

- (void)viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];
}

-(void)accessoryDidConnect:(id)sender
{
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	UITableViewCell * cell = [tableView cellForRowAtIndexPath:indexPath];

	if ( cell == _sendMailCell ) {

		if ( [MFMailComposeViewController canSendMail] ) {
			AppDelegate * appDelegate = [AppDelegate getAppDelegate];
			MFMailComposeViewController * mail = [[MFMailComposeViewController alloc] init];
			mail.mailComposeDelegate = self;
			[mail setSubject:[NSString stringWithFormat:@"%@ %@ feedback", appDelegate.appName, appDelegate.appVersion]];
			[mail setToRecipients:@[@"bryceco@yahoo.com"]];
			struct utsname systemInfo = { 0 };
			uname(&systemInfo);
			NSMutableString * body = [NSMutableString stringWithFormat:@"Device: '%s'\n",systemInfo.machine];
			if ( appDelegate.userName.length ) {
				[body appendString:[NSString stringWithFormat:@"OSM ID: '%@' (optional)\n\n",appDelegate.userName]];
			}
			[mail setMessageBody:body isHTML:NO];
			[self.navigationController presentViewController:mail animated:YES completion:nil];
		} else {
			UIAlertView * alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Cannot compose message",nil) message:NSLocalizedString(@"Mail delivery is not available on this device",nil) delegate:nil cancelButtonTitle:NSLocalizedString(@"OK",nil) otherButtonTitles:nil];
			[alert show];
		}
	}

	[self.tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (void)mailComposeController:(MFMailComposeViewController*)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError*)error
{
	[self dismissViewControllerAnimated:YES completion:nil];
}


- (void)tableView:(UITableView *)tableView didDeselectRowAtIndexPath:(NSIndexPath *)indexPath
{
}

@end
