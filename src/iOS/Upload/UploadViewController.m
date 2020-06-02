//
//  UploadViewController.m
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/19/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <MessageUI/MessageUI.h>
#import <QuartzCore/QuartzCore.h>

#if TARGET_OS_IPHONE
#import "DDXML.h"
#endif

#import "AerialList.h"
#import "AppDelegate.h"
#import "MapView.h"
#import "EditorMapLayer.h"
#import "MercatorTileLayer.h"
#import "OsmMapData.h"
#import "UploadViewController.h"


@implementation UploadViewController


- (void)viewDidLoad
{
    [super viewDidLoad];

	UIColor * color = [UIColor.grayColor colorWithAlphaComponent:0.5];
	_commentContainerView.layer.borderColor = color.CGColor;
	_commentContainerView.layer.borderWidth = 2.0;
	_commentContainerView.layer.cornerRadius = 10.0;

	_sourceTextField.layer.borderColor = color.CGColor;
	_sourceTextField.layer.borderWidth = 2.0;
	_sourceTextField.layer.cornerRadius = 10.0;

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

	NSString * source = [[NSUserDefaults standardUserDefaults] objectForKey:@"uploadSource"];
	_sourceTextField.text = source;

	NSAttributedString * text = [_mapData changesetAsAttributedString];
	if ( text == nil ) {
		_commitButton.enabled = NO;
		UIFont * font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
		_xmlTextView.attributedText = [[NSAttributedString alloc] initWithString:NSLocalizedString(@"Nothing to upload, no changes have been made.",nil) attributes:@{ NSFontAttributeName : font }];
	} else {
		_commitButton.enabled = YES;
		_xmlTextView.attributedText = text;
	}

	_sendMailButton.enabled = (text != nil);
	_editXmlButton.enabled = (text != nil);

	_clearCommentButton.hidden = YES;
}

- (void)viewDidDisappear:(BOOL)animated
{
	[super viewDidDisappear:animated];
	[[NSUserDefaults standardUserDefaults] setObject:_commentTextView.text forKey:@"uploadComment"];
	[[NSUserDefaults standardUserDefaults] setObject:_sourceTextField.text forKey:@"uploadSource"];
}

- (BOOL)textView:(UITextView *)textView shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text
{
    if ( [text isEqualToString:@"\n"] ) {
		[textView resignFirstResponder];
		return NO;
	}
	return YES;
}


- (IBAction)clearCommentText:(id)sender
{
	_commentTextView.text = @"";
	_clearCommentButton.hidden = YES;
}


- (IBAction)commit:(id)sender
{
	AppDelegate * appDelegate = (id)[[UIApplication sharedApplication] delegate];
	if ( appDelegate.userName.length == 0 || appDelegate.userPassword.length == 0 ) {
		[self performSegueWithIdentifier:@"loginSegue" sender:self];
		return;
	}

	if ( ![[NSUserDefaults standardUserDefaults] boolForKey:@"userDidPreviousUpload"] ) {
		UIAlertController * alert = [UIAlertController alertControllerWithTitle:@"Attention"
																		message:@"You are about to make changes to the live OpenStreetMap database. Your changes will be visible to everyone in the world.\n\nTo continue press Commit once again, otherwise press Cancel."
																 preferredStyle:UIAlertControllerStyleAlert];
		[alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel",nil) style:UIAlertActionStyleCancel handler:nil]];
		[alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Commit",nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
			[[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"userDidPreviousUpload"];
			[self commit:nil];
		}]];
		[self presentViewController:alert animated:YES completion:nil];
		return;
	}

	_mapData.credentialsUserName = appDelegate.userName;
	_mapData.credentialsPassword = appDelegate.userPassword;

	[_progressView startAnimating];
	[_commitButton setEnabled:NO];
	[_cancelButton setEnabled:NO];
	[_sendMailButton setEnabled:NO];
	[_editXmlButton setEnabled:NO];

	[_commentTextView resignFirstResponder];
	[_xmlTextView resignFirstResponder];

	NSString * comment = _commentTextView.text;
	comment = [comment stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

	NSString * source = _sourceTextField.text;
	source = [source stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

	void (^completion)(NSString *) = ^void(NSString * error) {
		[_progressView stopAnimating];
		[_commitButton setEnabled:YES];
		[_cancelButton setEnabled:YES];
		if ( error ) {
			UIAlertController * alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Unable to upload changes",nil)
																			message:error
																	 preferredStyle:UIAlertControllerStyleAlert];
			[alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK",nil) style:UIAlertActionStyleCancel handler:nil]];
			[self presentViewController:alert animated:YES completion:nil];

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

	NSString * imagery = nil;
	if ( appDelegate.mapView.viewState == MAPVIEW_EDITORAERIAL || appDelegate.mapView.viewState == MAPVIEW_AERIAL )
		imagery = appDelegate.mapView.aerialLayer.aerialService.name;

	if ( _xmlTextView.editable ) {
		
		// upload user-edited text
		NSString * xmlText = _xmlTextView.text;
		NSError * error = nil;
		NSXMLDocument * xmlDoc = [[NSXMLDocument alloc] initWithXMLString:xmlText options:0 error:&error];
		if ( error ) {
			completion( NSLocalizedString( @"The XML is improperly formed", nil ) );
			return;
		}
		[_mapData uploadChangesetXml:xmlDoc comment:comment source:source imagery:imagery completion:completion];

	} else {
		// normal upload
		[_mapData uploadChangesetWithComment:comment source:source imagery:imagery completion:completion];
	}
}

-(IBAction)editXml:(id)sender
{
	AppDelegate * appDelegate = AppDelegate.getAppDelegate;

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

	UIAlertController * alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Edit XML",nil)
																	message:NSLocalizedString(@"Modifying the raw XML data allows you to correct errors that prevent uploading.\n\nIt is an advanced operation that should only be undertaken if you have a thorough understanding of the OSM changeset format.",nil)
															 preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK",nil) style:UIAlertActionStyleCancel handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
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
		UIAlertController * error = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Cannot compose message",nil)
																		message:NSLocalizedString(@"Mail delivery is not available on this device",nil)
																 preferredStyle:UIAlertControllerStyleAlert];
		[error addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK",nil) style:UIAlertActionStyleCancel handler:nil]];
		[self presentViewController:error animated:YES completion:nil];
	}
}

- (void)mailComposeController:(MFMailComposeViewController*)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError*)error
{
	[self dismissViewControllerAnimated:YES completion:nil];
}

-(void)textViewDidChange:(UITextView *)textView
{
	if ( textView == _commentTextView ) {
		_clearCommentButton.hidden  = _commentTextView.text.length == 0;
	}
}
-(void)textViewDidBeginEditing:(UITextView *)textView
{
	if ( textView == _commentTextView ) {
		_clearCommentButton.hidden  = _commentTextView.text.length == 0;
	}
}
-(void)textViewDidEndEditing:(UITextView *)textView
{
	if ( textView == _commentTextView ) {
		_clearCommentButton.hidden  = YES;
	}
}

// this is for navigating from the changeset back to the location of the modified object
- (BOOL)textView:(UITextView *)textView shouldInteractWithURL:(NSURL *)url inRange:(NSRange)characterRange
{
	AppDelegate	*	appDelegate = AppDelegate.getAppDelegate;
	NSString 	*	name = url.absoluteString;
	if ( name.length == 0 )
		return NO;
	OsmIdentifier 	ident = [[name substringFromIndex:1] longLongValue];
	switch ( [name characterAtIndex:0] ) {
		case 'n':
			ident = [OsmBaseObject extendedIdentifierForType:OSM_TYPE_NODE identifier:ident];
			break;
		case 'w':
			ident = [OsmBaseObject extendedIdentifierForType:OSM_TYPE_WAY identifier:ident];
			break;
		case 'r':
			ident = [OsmBaseObject extendedIdentifierForType:OSM_TYPE_RELATION identifier:ident];
			break;
		default:
			return NO;
	}
	OsmBaseObject *	object = [appDelegate.mapView.editorLayer.mapData objectWithExtendedIdentifier:@(ident)];
	if ( object == nil )
		return NO;
	
	appDelegate.mapView.editorLayer.selectedRelation = object.isRelation;
	appDelegate.mapView.editorLayer.selectedWay		 = object.isWay;
	appDelegate.mapView.editorLayer.selectedNode	 = object.isNode;
	[appDelegate.mapView placePushpinForSelection];
	
	[self cancel:nil];
	return NO;
}

- (IBAction)cancel:(id)sender
{
	[self dismissViewControllerAnimated:YES completion:nil];
}

@end
