//
//  ChangesWindowController.h
//  OpenStreetMap
//
//  Created by Bryce on 11/1/12.
//  Copyright (c) 2012 Bryce. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

@class OsmMapData;


@interface ChangesWindowController : NSWindowController
{
	IBOutlet WebView				*	_webView;
	IBOutlet NSTextField			*	_commentTextField;
	IBOutlet NSProgressIndicator	*	_progressIndicator;
	IBOutlet NSButton				*	_uploadButton;
	IBOutlet NSButton				*	_cancelButton;
	OsmMapData						*	_mapData;
}
-(BOOL)setMapdata:(OsmMapData *)mapData;

-(IBAction)upload:(id)sender;
-(IBAction)cancel:(id)sender;

@end
