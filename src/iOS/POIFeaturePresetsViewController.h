//
//  POIDetailsViewController.h
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/10/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "CommonPresetList.h"
#import "POIFeaturePickerViewController.h"

@class OsmBaseObject;
@class CommonPresetList;

@interface POIFeaturePresetsViewController : UITableViewController<UITextFieldDelegate,POITypeViewControllerDelegate>
{
	CommonPresetList			*	_tags;
	IBOutlet UIBarButtonItem	*	_saveButton;
	CommonPresetFeature			*	_selectedFeature;	// the feature selected by the user, not derived from tags (e.g. Address)
	BOOL							_childPushed;
	BOOL							_isEditing;
}
@property (nonatomic) 	CommonPresetGroup	*	drillDownGroup;

- (IBAction)textFieldReturn:(id)sender;

-(IBAction)cancel:(id)sender;
-(IBAction)done:(id)sender;

@end
