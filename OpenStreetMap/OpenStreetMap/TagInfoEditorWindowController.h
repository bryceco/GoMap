//
//  TagInfoEditorWindowController.h
//  OpenStreetMap
//
//  Created by Bryce on 11/3/12.
//  Copyright (c) 2012 Bryce. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface TagInfoEditorWindowController : NSWindowController
{
	IBOutlet NSTableView	*	_tableView;
	NSMutableArray			*	_tagArray;
}
@property (assign,nonatomic) IBOutlet NSArrayController	*	arrayController;
@property (strong,nonatomic) NSString					*	searchText;

-(IBAction)saveXml:(id)sender;
@end
