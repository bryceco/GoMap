//
//  UploadViewController.m
//  OSMiOS
//
//  Created by Bryce Cogswell on 12/19/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <MessageUI/MessageUI.h>
#import <QuartzCore/QuartzCore.h>

#if TARGET_OS_IPHONE
#import "DDXML.h"
#endif

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

	NSString * comment = [[NSUserDefaults standardUserDefaults] objectForKey:@"uploadComment"];
	_commentTextView.text = comment;

	NSAttributedString * text = [_mapData changesetAsAttributedString];
	if ( text == nil ) {
		_commitButton.enabled = NO;
		UIFont * font = [UIFont fontWithName:@"Helvetica" size:16];
		_xmlTextView.attributedText = [[NSAttributedString alloc] initWithString:NSLocalizedString(@"Nothing to upload, no changes have been made.",nil) attributes:@{ NSFontAttributeName : font }];
	} else {
		_commitButton.enabled = YES;
		_xmlTextView.attributedText = text;
	}

	_sendMailButton.enabled = (text != nil);
	_editXmlButton.enabled = (text != nil);
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

-(void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
	if ( alertView == _alertViewConfirm ) {
		if ( buttonIndex != alertView.cancelButtonIndex ) {
			[[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"userDidPreviousUpload"];
			[self commit:nil];
		}
	}
}

- (IBAction)commit:(id)sender
{
	AppDelegate * appDelegate = (id)[[UIApplication sharedApplication] delegate];
	if ( appDelegate.userName.length == 0 || appDelegate.userPassword.length == 0 ) {
		if ( appDelegate.userName.length == 0 || appDelegate.userPassword.length == 0 ) {
			[self performSegueWithIdentifier:@"loginSegue" sender:self];
			return;
		}
	}

	if ( ![[NSUserDefaults standardUserDefaults] boolForKey:@"userDidPreviousUpload"] ) {
		_alertViewConfirm = [[UIAlertView alloc] initWithTitle:@"Warning"
													 message:@"You are about to make changes to the live OpenStreetMap database. Your changes will be visible to everyone in the world.\n\nTo continue press Commit once again, otherwise press Cancel."
													delegate:self
										   cancelButtonTitle:@"Cancel"
										   otherButtonTitles:@"Commit",nil];
		[_alertViewConfirm show];
		return;
	}

	_mapData.credentialsUserName = appDelegate.userName;
	_mapData.credentialsPassword = appDelegate.userPassword;

	[_progressView startAnimating];
	[_commitButton setEnabled:NO];
	[_cancelButton setEnabled:NO];
	[_sendMailButton setEnabled:NO];
	[_editXmlButton setEnabled:NO];

	NSString * comment = _commentTextView.text;
	comment = [comment stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

	void (^completion)(NSString *) = ^void(NSString * error) {
		[_progressView stopAnimating];
		[_commitButton setEnabled:YES];
		[_cancelButton setEnabled:YES];
		if ( error ) {
			UIAlertView * alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Unable to upload changes",nil) message:error delegate:nil cancelButtonTitle:NSLocalizedString(@"OK",nil) otherButtonTitles:nil];
			[alert show];
			if ( !_xmlTextView.editable ) {
				[_sendMailButton setEnabled:YES];
				[_editXmlButton setEnabled:YES];
			}
		} else {

			[self dismissViewControllerAnimated:YES completion:nil];

			// flash success message
			dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC));
			dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
				[appDelegate.mapView flashMessage:NSLocalizedString(@"Upload complete!",nil) duration:1.5];

				// record number of uploads
				NSString * uploadKey = [NSString stringWithFormat:@"uploadCount-%@", appDelegate.appVersion];
				NSInteger editCount = [[NSUserDefaults standardUserDefaults] integerForKey:uploadKey];
				++editCount;
				[[NSUserDefaults standardUserDefaults] setInteger:editCount forKey:uploadKey];
				[appDelegate.mapView askToRate:editCount];
			});
		}
	};

	if ( _xmlTextView.editable ) {
		
		// upload user-edited text
		NSString * xmlText = _xmlTextView.text;
		NSError * error = nil;
		NSXMLDocument * xmlDoc = [[NSXMLDocument alloc] initWithXMLString:xmlText options:0 error:&error];
		if ( error ) {
			completion( NSLocalizedString( @"The XML is improperly formed", nil ) );
			return;
		}
		[_mapData uploadChangeset:xmlDoc comment:comment retry:NO completion:completion];

	} else {
		// normal upload
		[_mapData uploadChangesetWithComment:comment completion:completion];
	}
}

-(IBAction)editXml:(id)sender
{
	AppDelegate * appDelegate = (id)[[UIApplication sharedApplication] delegate];

	MFMailComposeViewController * mail = [[MFMailComposeViewController alloc] init];
	mail.mailComposeDelegate = self;
	[mail setSubject:[NSString stringWithFormat:@"%@ changeset", appDelegate.appName]];
	NSString * xml = [_mapData changesetAsXml];
	xml = [xml stringByAppendingString:@"\n\n\n\n\n\n\n\n\n\n\n\n"];
	_xmlTextView.attributedText = nil;
	_xmlTextView.text = xml;
	_xmlTextView.editable = YES;
	_sendMailButton.enabled = NO;
	_editXmlButton.enabled = NO;

	UIAlertView * alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Edit XML",nil) message:NSLocalizedString(@"Modifying the raw XML data allows you to correct errors that prevent uploading.\n\nIt is an advanced operation that should only be undertaken if you have a thorough understanding of the OSM changeset format.",nil) delegate:nil cancelButtonTitle:NSLocalizedString(@"OK",nil) otherButtonTitles:nil];
	[alert show];
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
		UIAlertView * alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Cannot compose message",nil) message:NSLocalizedString(@"Mail delivery is not available on this device",nil) delegate:nil cancelButtonTitle:NSLocalizedString(@"OK",nil) otherButtonTitles:nil];
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
