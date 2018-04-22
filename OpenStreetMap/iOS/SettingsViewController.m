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
#import "CommonTagList.h"
#import "EditorMapLayer.h"
#import "OsmMapData.h"
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

	PresetLanguages * presetLanguages = [PresetLanguages new];
	NSString * preferredLanguageCode = presetLanguages.preferredLanguageCode;
	NSString * preferredLanguage = [presetLanguages localLanguageNameForCode:preferredLanguageCode];
	_language.text = preferredLanguage;

	// set username, but then validate it
	AppDelegate * appDelegate = [AppDelegate getAppDelegate];

	_username.text = @"";
	if ( appDelegate.userName.length > 0 ) {
		[appDelegate.mapView.editorLayer.mapData verifyUserCredentialsWithCompletion:^(NSString * errorMessage) {
			if ( errorMessage ) {
				_username.text = @"<invalid>";
			} else {
				_username.text = appDelegate.userName;
			}
			[self.tableView reloadData];
		}];
	}
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

-(NSString *)deviceModel
{
	struct utsname systemInfo = { 0 };
	uname(&systemInfo);
	NSString * model = [NSString stringWithUTF8String:systemInfo.machine];

	// https://everymac.com/ultimate-mac-lookup
	NSDictionary * dict = @{
		// iPhone
		@"iPhone1,1" : @"iPhone 2G",

		@"iPhone1,2" : @"iPhone 3G",
		@"iPhone2,1" : @"iPhone 3GS",

		@"iPhone3,1" : @"iPhone 4 (GSM)",
		@"iPhone3,2" : @"iPhone 4 (GSM, Revision A)",
		@"iPhone3,3" : @"iPhone 4 (CDMA/Verizon/Sprint)",

		@"iPhone4,1" : @"iPhone 4S",

		@"iPhone5,1" : @"iPhone 5 (GSM/LTE 4, 17/North America)",
		@"iPhone5,2" : @"iPhone 5 (CDMA/LTE)",

		@"iPhone5,3" : @"iPhone 5c (GSM)",
		@"iPhone5,4" : @"iPhone 5c (GSM+CDMA)",
		
		@"iPhone6,1" : @"iPhone 5s (GSM)",
		@"iPhone6,2" : @"iPhone 5s (GSM+CDMA)",
		
		@"iPhone7,1" : @"iPhone 6 Plus",
		@"iPhone7,2" : @"iPhone 6",
		
		@"iPhone8,2" : @"iPhone 6s Plus",
		@"iPhone8,1" : @"iPhone 6s",
		
		@"iPhone8,4" : @"iPhone SE",
		
		@"iPhone9,1" : @"iPhone 7 (Verizon/Sprint/China)",
		@"iPhone9,3" : @"iPhone 7 (Global)",
		@"iPhone9,2" : @"iPhone 7 Plus (Verizon/Sprint/China)",
		@"iPhone9,4" : @"iPhone 7 Plus (Global)",
		
		@"iPhone10,1" : @"iPhone 8 (Verizon/Sprint/China)",
		@"iPhone10,4" : @"iPhone 8 (Global)",
		@"iPhone10,2" : @"iPhone 8 Plus (Verizon/Sprint/China)",
		@"iPhone10,5" : @"iPhone 8 Plus (Global)",
		
		@"iPhone10,3" : @"iPhone X (Verizon/Sprint/China)",
		@"iPhone10,6" : @"iPhone X",
		
		// iPod
		@"iPod1,1" : @"iPod Touch (1 Gen)",
		@"iPod2,1" : @"iPod Touch (2 Gen)",
		@"iPod3,1" : @"iPod Touch (3 Gen)",
		@"iPod4,1" : @"iPod Touch (4 Gen)",
		@"iPod5,1" : @"iPod Touch (5 Gen)",
		@"iPod7,1" : @"iPod Touch (6 Gen)",
		
		// iPad
		@"iPad1,1" : @"iPad",
		@"iPad1,2" : @"iPad 3G",
		@"iPad2,1" : @"iPad 2 (WiFi)",
		@"iPad2,2" : @"iPad 2 (GSM)",
		@"iPad2,3" : @"iPad 2 (CDMA)",
		@"iPad2,4" : @"iPad 2 (WiFi)",
		
		@"iPad2,5" : @"iPad Mini (WiFi)",
		@"iPad2,6" : @"iPad Mini (GSM)",
		@"iPad2,7" : @"iPad Mini (GSM+CDMA)",

		@"iPad3,1" : @"iPad 3 (WiFi)",
		@"iPad3,2" : @"iPad 3 (GSM+CDMA)",
		@"iPad3,3" : @"iPad 3 (GSM)",
		
		@"iPad3,4" : @"iPad 4 (WiFi)",
		@"iPad3,5" : @"iPad 4 (GSM)",
		@"iPad3,6" : @"iPad 4 (GSM+CDMA)",
		
		@"iPad4,1" : @"iPad Air (WiFi)",
		@"iPad4,2" : @"iPad Air (Cellular)",

		@"iPad4,4" : @"iPad Mini 2 (WiFi)",
		@"iPad4,5" : @"iPad Mini 2 (Cellular)",
		@"iPad4,6" : @"iPad Mini 2 (China)",

		@"iPad4,7" : @"iPad Mini 3 (WiFi)",
		@"iPad4,8" : @"iPad Mini 3 (Cellular)",
		@"iPad4,9" : @"iPad Mini 3 (China)",

		@"iPad5,1" : @"iPad Mini 4 (WiFi)",
		@"iPad5,2" : @"iPad Mini 4 (LTE)",

		@"iPad5,3" : @"iPad Air 2 (WiFi)",
		@"iPad5,4" : @"iPad Air 2 (Cellular)",

		@"iPad6,3" : @"iPad Pro 9.7 (WiFi)",
		@"iPad6,4" : @"iPad Pro 9.7 (Cellular)",

		@"iPad6,7" : @"iPad Pro 12.9 (WiFi)",
		@"iPad6,8" : @"iPad Pro 12.9 (Cellular)",
		
		@"iPad6,11" : @"iPad (5th Gen, WiFi)",
		@"iPad6,12" : @"iPad (5th Gen, Cellular)",

		@"iPad7,1" : @"iPad Pro 12.9 (2nd Gen, WiFi)",
		@"iPad7,2" : @"iPad Pro 12.9 (2nd Gen, Cellular)",

		@"iPad7,3" : @"iPad Pro 10.5 (WiFi)",
		@"iPad7,4" : @"iPad Pro 10.5 (Cellular)",
		
		// other
		@"AppleTV2,1" : @"Apple TV 2G",
		@"AppleTV3,1" : @"Apple TV 3",
		@"AppleTV3,2" : @"Apple TV 3 (2013)",
		
		@"i386" : @"Simulator",
		@"x86_64" : @"Simulator",
	};

	NSString * friendlyModel = dict[ model ];
	return friendlyModel ?: model;
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
			NSMutableString * body = [NSMutableString stringWithFormat:@"Device: %@\n", [self deviceModel]];
			[body appendString:[NSString stringWithFormat:@"iOS version: %@\n", [[UIDevice currentDevice] systemVersion]]];
			if ( appDelegate.userName.length ) {
				[body appendString:[NSString stringWithFormat:@"OSM ID: %@\n\n",appDelegate.userName]];
			}
			[mail setMessageBody:body isHTML:NO];
			[self.navigationController presentViewController:mail animated:YES completion:nil];
		} else {
			UIAlertController * alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Cannot compose message",nil)
																			message:NSLocalizedString(@"Mail delivery is not available on this device",nil)
																	 preferredStyle:UIAlertControllerStyleAlert];
			[alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK",nil) style:UIAlertActionStyleCancel handler:nil]];
			[self presentViewController:alert animated:YES completion:nil];
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
