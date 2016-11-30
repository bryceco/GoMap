//
//  CustomPresetController.h
//  Go Map!!
//
//  Created by Bryce Cogswell on 8/21/14.
//  Copyright (c) 2014 Bryce Cogswell. All rights reserved.
//

#import <UIKit/UIKit.h>

@class CustomPreset;

@interface CustomPresetController : UITableViewController
{
	IBOutlet UITextField *	_nameField;
	IBOutlet UITextField *	_appliesToTagField;
	IBOutlet UITextField *	_appliesToValueField;
	IBOutlet UITextField *	_keyField;
	IBOutlet UITextField *	_value1Field;
	IBOutlet UITextField *	_value2Field;
	IBOutlet UITextField *	_value3Field;
	IBOutlet UITextField *	_value4Field;
	IBOutlet UITextField *	_value5Field;
	IBOutlet UITextField *	_value6Field;
	IBOutlet UITextField *	_value7Field;
	IBOutlet UITextField *	_value8Field;
	IBOutlet UITextField *	_value9Field;
	IBOutlet UITextField *	_value10Field;
	IBOutlet UITextField *	_value11Field;
	IBOutlet UITextField *	_value12Field;

	NSArray * _valueFieldList;
}

@property CustomPreset * customPreset;

@property (copy) void (^completion)(CustomPreset * customPreset);

-(IBAction)contentChanged:(id)sender;
-(IBAction)done:(id)sender;
-(IBAction)cancel:(id)sender;

@end
