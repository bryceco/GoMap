//
//  UploadViewController.m
//  OSMiOS
//
//  Created by Bryce Cogswell on 12/19/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <MessageUI/MessageUI.h>
#import <QuartzCore/QuartzCore.h>

#import "AppDelegate.h"
#import "MapView.h"
#import "EditorMapLayer.h"
#import "OsmMapData.h"
#import "UploadViewController.h"


@implementation UploadViewController


- (void)viewDidLoad
{
    [super viewDidLoad];

	UIColor * color = [UIColor.grayColor colorWithAlphaComponent:0.5];
	_commentTextView.layer.borderColor = color.CGColor;
	_commentTextView.layer.borderWidth = 2.0;
	_commentTextView.layer.cornerRadius = 10.0;

	_xmlTextView.layer.borderColor = color.CGColor;
	_xmlTextView.layer.borderWidth = 2.0;
	_xmlTextView.layer.cornerRadius = 10.0;
}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];

	MapView * mapView = [(AppDelegate *)[[UIApplication sharedApplication] delegate] mapView];
	_mapData = mapView.editorLayer.mapData;

	NSAttributedString * text = [_mapData changesetAsAttributedString];
	if ( text == nil ) {
		_commitButton.enabled = NO;
		UIFont * font = [UIFont fontWithName:@"Helvetica" size:16];
		_xmlTextView.attributedText = [[NSAttributedString alloc] initWithString:@"Nothing to upload, no changes have been made." attributes:@{ NSFontAttributeName : font }];
	} else {
		_commitButton.enabled = YES;
		_xmlTextView.attributedText = text;
	}

	_commentTextView.text = [[NSUserDefaults standardUserDefaults] objectForKey:@"uploadComment"];

	_sendMailButton.enabled = (text != nil);
}

- (void)viewDidDisappear:(BOOL)animated
{
	[super viewDidDisappear:animated];
	[[NSUserDefaults standardUserDefaults] setObject:_commentTextView.text forKey:@"uploadComment"];
}

- (BOOL)textView:(UITextView *)textView shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text
{
    if ( [text isEqualToString:@"\n"] ) {
		[textView resignFirstResponder];
		return NO;
	}
	return YES;
}

- (IBAction)commit:(id)sender
{
	AppDelegate * appDelegate = (id)[[UIApplication sharedApplication] delegate];
	if ( appDelegate.userName.length == 0 || appDelegate.userPassword.length == 0 ) {
#if 0
		UIAlertView * alertView = [[UIAlertView alloc] initWithTitle:@"Missing login information" message:@"Before uploading changes you must provide your OpenStreetMap username and password in the Credentials option under Settings" delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
		// alertView.alertViewStyle = UIAlertViewStyleLoginAndPasswordInput;
		[alertView show];
		return;
#else
		if ( appDelegate.userName.length == 0 || appDelegate.userPassword.length == 0 ) {
			[self performSegueWithIdentifier:@"loginSegue" sender:self];
			return;
		}
#endif
	}

	_mapData.credentialsUserName = appDelegate.userName;
	_mapData.credentialsPassword = appDelegate.userPassword;

	[_progressView startAnimating];
	[_commitButton setEnabled:NO];
	[_cancelButton setEnabled:NO];


	NSString * comment = _commentTextView.text;
	comment = [comment stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	
	[_mapData uploadChangeset:comment completion:^(NSString * error){
		[_progressView stopAnimating];
		[_commitButton setEnabled:YES];
		[_cancelButton setEnabled:YES];
		if ( error ) {
			UIAlertView * alert = [[UIAlertView alloc] initWithTitle:@"Unable to upload changes" message:error delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
			[alert show];
		} else {
			[self dismissViewControllerAnimated:YES completion:nil];

			// flash success message
			dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC));
			dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
				[appDelegate.mapView flashMessage:@"Upload complete!" duration:1.5];
			});
		}
	}];
}

-(IBAction)sendMail:(id)sender
{
	if ( [MFMailComposeViewController canSendMail] ) {
		AppDelegate * appDelegate = (id)[[UIApplication sharedApplication] delegate];

		MFMailComposeViewController * mail = [[MFMailComposeViewController alloc] init];
		mail.mailComposeDelegate = self;
		[mail setSubject:[NSString stringWithFormat:@"%@ changeset", appDelegate.appName]];
		NSString * xml = [_mapData changesetAsXml];
		[mail addAttachmentData:[xml dataUsingEncoding:NSUTF8StringEncoding] mimeType:@"application/xml" fileName:@"osmChange.osc"];
		[self presentViewController:mail animated:YES completion:nil];
	} else {
		UIAlertView * alert = [[UIAlertView alloc] initWithTitle:@"Cannot compose message" message:@"Mail delivery is not available on this device" delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
		[alert show];
	}
}

- (void)mailComposeController:(MFMailComposeViewController*)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError*)error
{
	[self dismissViewControllerAnimated:YES completion:nil];
}


- (IBAction)cancel:(id)sender
{
	[self dismissViewControllerAnimated:YES completion:nil];
}

@end
