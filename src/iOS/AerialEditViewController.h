//
//  AerialEditViewController.h
//  Go Map!!
//
//  Created by Bryce Cogswell on 8/21/14.
//  Copyright (c) 2014 Bryce Cogswell. All rights reserved.
//

#import <UIKit/UIKit.h>

@class AerialService;

@interface AerialEditViewController : UITableViewController<UIPickerViewDelegate, UIPickerViewDataSource>
{
	IBOutlet UITextField *	nameField;
	IBOutlet UITextField *	urlField;
	IBOutlet UITextField *	zoomField;
	IBOutlet UITextField *	projectionField;

	UIPickerView		*	_picker;
	NSArray<NSString *>	*	_projectionList;
}

@property NSString * name;
@property NSString * url;
@property NSNumber * zoom;
@property NSString * projection;

@property (copy) void (^completion)(AerialService * service);

-(IBAction)contentChanged:(id)sender;
-(IBAction)done:(id)sender;
-(IBAction)cancel:(id)sender;

@end
