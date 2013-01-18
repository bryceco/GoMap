//
//  SecondViewController.h
//  OSMiOS
//
//  Created by Bryce on 12/6/12.
//  Copyright (c) 2012 Bryce. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface SettingsViewController : UITableViewController <MFMailComposeViewControllerDelegate>
{
	IBOutlet UITableViewCell	*	_sendMailCell;
}
@end
