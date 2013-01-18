//
//  TextInputWindowController.m
//  OpenStreetMap
//
//  Created by Bryce on 12/2/12.
//  Copyright (c) 2012 Bryce. All rights reserved.
//

#import "TextInputWindowController.h"


@implementation TextInputWindowController

-(id)init
{
	self = [super initWithWindowNibName:@"TextInputWindowController"];
	if ( self ) {
	}
	return self;
}

- (void)beginSheetModalForWindow:(NSWindow *)window completionHandler:(void (^)(BOOL accepted))handler
{
	_handler = handler;
	[NSApp beginSheet:self.window modalForWindow:window modalDelegate:self didEndSelector:@selector(sheetDidEnd:returnCode:contextInfo:) contextInfo:NULL];
}

- (void)sheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{
	_handler( (BOOL)returnCode );
	[self close];
}

-(IBAction)ok:(id)sender
{
	[NSApp endSheet:self.window returnCode:YES];
}

-(IBAction)cancel:(id)sender
{
	[NSApp endSheet:self.window returnCode:NO];
}

@end
