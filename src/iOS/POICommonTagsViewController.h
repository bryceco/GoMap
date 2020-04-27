//
//  POIDetailsViewController.h
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/10/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "CommonPresetList.h"
#import "POITypeViewController.h"

@class OsmBaseObject;
@class CommonPresetList;

@interface POICommonTagsViewController : UITableViewController<UITextFieldDelegate,POITypeViewControllerDelegate>
{
	CommonPresetList				*	_tags;
	IBOutlet UIBarButtonItem	*	_saveButton;
	BOOL							_keyboardShowing;
	CommonPresetFeature			*	_selectedFeature;	// the feature selected by the user, not derived from tags (e.g. Address)
	BOOL							_childPushed;
}
@property (nonatomic) 	CommonPresetGroup	*	drillDownGroup;

- (IBAction)textFieldReturn:(id)sender;

-(IBAction)cancel:(id)sender;
-(IBAction)done:(id)sender;

@end
