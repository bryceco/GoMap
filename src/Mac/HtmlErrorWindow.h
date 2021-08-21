//
//  HtmlErrorWindow.h
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 12/1/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@class WebView;

@interface HtmlErrorWindow : NSWindowController
{
	NSString			*	_html;
	IBOutlet WebView	*	_webView;
}
- (id)initWithHtml:(NSString *)html;

- (IBAction)done:(id)sender;

@end
