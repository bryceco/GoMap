//
//  LoginViewController.m
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/19/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import "AppDelegate.h"
#import "EditorMapLayer.h"
#import "KeyChain.h"
#import "LoginViewController.h"
#import "MapView.h"
#import "OsmMapData.h"

@implementation LoginViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
}

- (IBAction)textFieldReturn:(id)sender
{
	[sender resignFirstResponder];
}

- (IBAction)textFieldDidChange:(id)sender
{
	_saveButton.enabled = _username.text.length && _password.text.length;
}

- (IBAction)registerAccount:(id)sender
{
	[[UIApplication sharedApplication] openURL:[NSURL URLWithString: @"https://www.openstreetmap.org/user/new"]];
}


- (IBAction)verifyAccount:(id)sender
{
	if ( _activityIndicator.isAnimating )
		return;
    
    NSString *username = [_username.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *password = [_password.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

	AppDelegate * appDelegate = (id)[[UIApplication sharedApplication] delegate];
    appDelegate.userName		= username;
    appDelegate.userPassword	= password;

	_activityIndicator.color = UIColor.darkGrayColor;
	[_activityIndicator startAnimating];

	[appDelegate.mapView.editorLayer.mapData verifyUserCredentialsWithCompletion:^(NSString * errorMessage){
		[_activityIndicator stopAnimating];
		if ( errorMessage ) {

			// warn that email addresses don't work
			if ( [appDelegate.userName containsString:@"@"] ) {
				errorMessage = NSLocalizedString(@"You must provide your OSM user name, not an email address.",nil);
			}
			UIAlertController * alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Bad login",nil) message:errorMessage preferredStyle:UIAlertControllerStyleAlert];
			[alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK",nil) style:UIAlertActionStyleCancel handler:nil]];
			[self presentViewController:alert animated:YES completion:nil];
		} else {
			// verifying credentials may update the appDelegate values when we subsitute name for correct case:
			_username.text	= username;
			_password.text	= password;
			[_username resignFirstResponder];
			[_password resignFirstResponder];
            
            [self saveVerifiedCredentialsWithUsername:username password:password];

			UIAlertController * alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Login successful",nil) message:nil preferredStyle:UIAlertControllerStyleAlert];
			[alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK",nil) style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
				[self.navigationController popToRootViewControllerAnimated:YES];
			}]];
			[self presentViewController:alert animated:YES completion:nil];
		}
	}];
}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];

	AppDelegate * appDelegate = (id)[[UIApplication sharedApplication] delegate];
	_username.text	= appDelegate.userName;
	_password.text	= appDelegate.userPassword;

	_saveButton.enabled = _username.text.length && _password.text.length;
}

#pragma mark - Table view delegate

@end
