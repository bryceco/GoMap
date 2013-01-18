//
//  LoginViewController.h
//  OSMiOS
//
//  Created by Bryce Cogswell on 12/19/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface LoginViewController : UITableViewController
{
	IBOutlet UITextField *	_username;
	IBOutlet UITextField *	_password;
}

- (IBAction)textFieldReturn:(id)sender;
- (IBAction)registerAccount:(id)sender;

@end
