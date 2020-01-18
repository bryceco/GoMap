//
//  SettingsViewController.h
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/6/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <MessageUI/MessageUI.h>

#import <UIKit/UIKit.h>


@interface SettingsViewController : UITableViewController <MFMailComposeViewControllerDelegate>
{
	IBOutlet UITableViewCell	*	_sendMailCell;
	IBOutlet UILabel			*	_username;
	IBOutlet UILabel			*	_language;
}

@property (nonatomic, readonly) IBOutlet UISwitch *showFPSLabelSwitch;

@end
