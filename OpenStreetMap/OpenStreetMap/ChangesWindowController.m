//
//  ChangesWindowController.m
//  OpenStreetMap
//
//  Created by Bryce on 11/1/12.
//  Copyright (c) 2012 Bryce. All rights reserved.
//

#import "AppDelegate.h"
#import "ChangesWindowController.h"
#import "OsmMapData.h"


@implementation ChangesWindowController

-(id)init
{
	self = [super initWithWindowNibName:@"ChangesWindowController"];
	if ( self ) {
	}
	return self;
}

- (void)windowDidLoad
{
    [super windowDidLoad];
}

-(BOOL)setMapdata:(OsmMapData *)mapData;
{
	_mapData = mapData;
	[_uploadButton setEnabled:YES];
	[_cancelButton setEnabled:YES];
	[_progressIndicator stopAnimation:self];
	NSString * html = [_mapData changesetAsHtml];
	[_webView.mainFrame loadHTMLString:html baseURL:nil];

	if ( html == nil ) {
		[NSApp stopModal];
		[self close];
		NSAlert * alert = [NSAlert alertWithMessageText:@"No changes to upload" defaultButton:@"OK" alternateButton:nil otherButton:nil informativeTextWithFormat:@""];
		[alert runModal];
		return NO;
	}
	return YES;
}

-(IBAction)upload:(id)sender
{
	AppDelegate * appDelegate = (id)[NSApp delegate];
	if ( appDelegate.userName.length == 0 || appDelegate.userPassword.length == 0 ) {
		NSAlert * alert = [NSAlert alertWithMessageText:@"Before uploading data you must enter a username and password in the Preferences window" defaultButton:@"OK" alternateButton:nil otherButton:nil
							  informativeTextWithFormat:@"You can register an OpenStreetMap user name and passowrd at www.openstreetmap.org"];
		[alert beginSheetModalForWindow:self.window modalDelegate:nil didEndSelector:nil contextInfo:NULL];
		return;
	}

	NSString * comment = _commentTextField.stringValue;
	[_progressIndicator startAnimation:self];
	[_uploadButton setEnabled:NO];
	[_cancelButton setEnabled:NO];
	[_mapData uploadChangeset:comment completion:^(NSString * error){
		[_progressIndicator stopAnimation:nil];
		[_uploadButton setEnabled:YES];
		[_cancelButton setEnabled:YES];
		if ( error ) {
			NSString * text = [NSString stringWithFormat:@"Unable to upload commit: %@", error];
			NSAlert * alert = [NSAlert alertWithMessageText:text defaultButton:@"OK" alternateButton:nil otherButton:nil informativeTextWithFormat:@""];
			[alert beginSheetModalForWindow:self.window modalDelegate:nil didEndSelector:nil contextInfo:NULL];
		} else {
			[NSApp stopModal];
			[self close];
		}
	}];
}

-(IBAction)cancel:(id)sender
{
	[NSApp stopModal];
	[self close];
}


@end
