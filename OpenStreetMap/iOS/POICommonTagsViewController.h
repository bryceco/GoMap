//
//  POIDetailsViewController.h
//  OSMiOS
//
//  Created by Bryce Cogswell on 12/10/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <UIKit/UIKit.h>

@class OsmBaseObject;
@class CommonTagList;

@interface POICommonTagsViewController : UITableViewController<UITextFieldDelegate>
{
	CommonTagList				*	_tags;
	IBOutlet UIBarButtonItem	*	_saveButton;
	BOOL							_keyboardShowing;
}

- (IBAction)textFieldReturn:(id)sender;

- (void)loadState;

-(IBAction)cancel:(id)sender;
-(IBAction)done:(id)sender;

@end
