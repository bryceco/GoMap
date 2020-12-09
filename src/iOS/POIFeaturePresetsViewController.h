//
//  POIDetailsViewController.h
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/10/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "POIFeaturePickerViewController.h"
#import "PresetsDatabase.h"

@class OsmBaseObject;
@class PresetsDatabase;

@interface POIFeaturePresetsViewController : UITableViewController<UITextFieldDelegate,POITypeViewControllerDelegate>
{
	PresetsForFeature			*	_allPresets;
	IBOutlet UIBarButtonItem	*	_saveButton;
	PresetFeature				*	_selectedFeature;	// the feature selected by the user, not derived from tags (e.g. Address)
	BOOL							_childPushed;
	BOOL							_isEditing;
}
@property (nonatomic) 	PresetGroup	*	drillDownGroup;

- (IBAction)textFieldReturn:(id)sender;

-(IBAction)cancel:(id)sender;
-(IBAction)done:(id)sender;

@end
