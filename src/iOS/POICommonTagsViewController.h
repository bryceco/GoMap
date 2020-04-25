//
//  POIDetailsViewController.h
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/10/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "CommonTagList.h"
#import "POITypeViewController.h"

@class OsmBaseObject;
@class CommonTagList;

@interface POICommonTagsViewController : UITableViewController<UITextFieldDelegate,POITypeViewControllerDelegate>
{
	CommonTagList				*	_tags;
	IBOutlet UIBarButtonItem	*	_saveButton;
	BOOL							_keyboardShowing;
	CommonTagFeature			*	_selectedFeature;	// the feature selected by the user, not derived from tags (e.g. Address)
	BOOL							_childPushed;
}
@property (nonatomic) 	CommonTagGroup	*	drillDownGroup;

- (IBAction)textFieldReturn:(id)sender;

-(IBAction)cancel:(id)sender;
-(IBAction)done:(id)sender;

@end
