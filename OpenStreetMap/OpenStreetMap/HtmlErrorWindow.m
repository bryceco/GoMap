//
//  HtmlErrorWindow.m
//  OpenStreetMap
//
//  Created by Bryce on 12/1/12.
//  Copyright (c) 2012 Bryce. All rights reserved.
//

#import <WebKit/WebKit.h>

#import "HtmlErrorWindow.h"



@implementation HtmlErrorWindow

- (id)initWithHtml:(NSString *)html
{
	self = [super initWithWindowNibName:@"HtmlErrorWindow"];
	if ( self ) {
		_html = [html copy];
	}
	return self;
}

-(void)windowDidLoad
{
	[_webView.mainFrame loadHTMLString:_html baseURL:nil];
}

- (IBAction)done:(id)sender
{
	[NSApp stopModal];
}


@end
