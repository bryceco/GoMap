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
	IBOutlet UIBarButtonItem			*	_verifyButton;
	IBOutlet UITextField				*	_username;
	IBOutlet UITextField				*	_password;
	IBOutlet UIActivityIndicatorView	*	_activityIndicator;
}

- (IBAction)textFieldReturn:(id)sender;
- (IBAction)textFieldDidChange:(id)sender;

- (IBAction)registerAccount:(id)sender;
- (IBAction)verifyAccount:(id)sender;

@end
