//
//  CustomPresetController.h
//  Go Map!!
//
//  Created by Bryce on 8/21/14.
//  Copyright (c) 2014 Bryce. All rights reserved.
//

#import <UIKit/UIKit.h>

@class CommonTag;

@interface CustomPresetController : UITableViewController
{
	IBOutlet UITextField *	nameField;
	IBOutlet UITextField *	tagField;
	IBOutlet UITextField *	placeholderField;
}

@property CommonTag * commonTag;

@property (copy) void (^completion)(CommonTag * commonTag);

-(IBAction)contentChanged:(id)sender;
-(IBAction)done:(id)sender;
-(IBAction)cancel:(id)sender;

@end
