//
//  SecondViewController.h
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/6/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <MessageUI/MessageUI.h>

#import <UIKit/UIKit.h>


@interface DisplayViewController : UITableViewController
{
	IBOutlet UISwitch *	_birdsEyeSwitch;
	IBOutlet UISwitch *	_rotationSwitch;
	IBOutlet UISwitch *	_notesSwitch;
	IBOutlet UISwitch *	_gpsTraceSwitch;
	IBOutlet UISwitch *	_unnamedRoadSwitch;
	IBOutlet UISwitch *	_gpxLoggingSwitch;
	IBOutlet UISwitch * _turnRestrictionSwitch;
	IBOutlet UISwitch * _objectFiltersSwitch;
	IBOutlet UIButton *	_addButtonPosition;
}

-(IBAction)chooseAddButtonPosition:(id)sender;

-(void)applyChanges;

@end
