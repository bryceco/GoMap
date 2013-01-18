//
//  POIDetailsViewController.h
//  OSMiOS
//
//  Created by Bryce on 12/10/12.
//  Copyright (c) 2012 Bryce. All rights reserved.
//

#import <UIKit/UIKit.h>

@class OsmBaseObject;


@interface POICommonTagsViewController : UITableViewController
{
	NSArray						*	_tagMap;

	// basic
	IBOutlet UILabel			*	_typeTextField;
	IBOutlet UITextField		*	_nameTextField;
	IBOutlet UITextField		*	_altNameTextField;
	IBOutlet UITextField		*	_cuisineTextField;
	IBOutlet UITextField		*	_wifiTextField;
	IBOutlet UITextField		*	_operatorTextField;
	IBOutlet UITextField		*	_refTextField;
	// address
	IBOutlet UITextField		*	_buildingTextField;
	IBOutlet UITextField		*	_houseNumberTextField;
	IBOutlet UITextField		*	_unitTextField;
	IBOutlet UITextField		*	_streetTextField;
	IBOutlet UITextField		*	_cityTextField;
	IBOutlet UITextField		*	_postalCodeTextField;
	IBOutlet UITextField		*	_websiteTextField;
	IBOutlet UITextField		*	_phoneTextField;
	// source
	IBOutlet UITextField		*	_designationTextField;
	IBOutlet UITextField		*	_sourceTextField;
	// notes
	IBOutlet UITextField		*	_fixmeTextField;
	IBOutlet UITextField		*	_noteTextField;

	IBOutlet UIBarButtonItem	*	_saveButton;
}

- (IBAction)textFieldReturn:(id)sender;

- (void)loadState;

-(IBAction)cancel:(id)sender;
-(IBAction)done:(id)sender;

@end
