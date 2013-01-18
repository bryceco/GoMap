//
//  LoginViewController.m
//  OSMiOS
//
//  Created by Bryce on 12/19/12.
//  Copyright (c) 2012 Bryce. All rights reserved.
//

#import "AppDelegate.h"
#import "LoginViewController.h"
#import "UITableViewCell+FixConstraints.h"

@implementation LoginViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
}

- (IBAction)textFieldReturn:(id)sender
{
	[sender resignFirstResponder];
}

- (IBAction)registerAccount:(id)sender
{
	[[UIApplication sharedApplication] openURL:[NSURL URLWithString: @"https://www.openstreetmap.org/user/new"]];
}


- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];

	AppDelegate * appDelegate = (id)[[UIApplication sharedApplication] delegate];
	_username.text	= appDelegate.userName;
	_password.text	= appDelegate.userPassword;
}

- (void)viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];

	if ( [self isMovingFromParentViewController] ) {
		AppDelegate * appDelegate = (id)[[UIApplication sharedApplication] delegate];
		appDelegate.userName		= _username.text;
		appDelegate.userPassword	= _password.text;

		[[NSUserDefaults standardUserDefaults] setObject:appDelegate.userName		forKey:@"userName"];
		[[NSUserDefaults standardUserDefaults] setObject:appDelegate.userPassword	forKey:@"userPassword"];
	}
}

-(void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
	[cell fixConstraints];
}

#pragma mark - Table view delegate

@end
