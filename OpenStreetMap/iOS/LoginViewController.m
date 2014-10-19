//
//  LoginViewController.m
//  OSMiOS
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

- (IBAction)textFieldDidChange:(id)sender
{
	_verifyButton.enabled = _username.text.length && _password.text.length;
}

- (IBAction)registerAccount:(id)sender
{
	[[UIApplication sharedApplication] openURL:[NSURL URLWithString: @"https://www.openstreetmap.org/user/new"]];
}


- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex
{
	[self.navigationController popToRootViewControllerAnimated:YES];
}


- (IBAction)verifyAccount:(id)sender
{
	if ( _activityIndicator.isAnimating )
		return;

	AppDelegate * appDelegate = (id)[[UIApplication sharedApplication] delegate];
	appDelegate.userName		= [_username.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	appDelegate.userPassword	= [_password.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

	_activityIndicator.color = UIColor.darkGrayColor;
	[_activityIndicator startAnimating];

	[appDelegate.mapView.editorLayer.mapData verifyUserCredentialsWithCompletion:^(NSString * errorMessage){
		[_activityIndicator stopAnimating];
		if ( errorMessage ) {
			UIAlertView * alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Bad login",nil) message:errorMessage delegate:nil cancelButtonTitle:NSLocalizedString(@"OK",nil) otherButtonTitles:nil];
			[alertView show];
		} else {
			// verifying credentials may update the appDelegate values when we subsitute name for correct case:
			_username.text	= appDelegate.userName;
			_password.text	= appDelegate.userPassword;
			[_username resignFirstResponder];
			[_password resignFirstResponder];
			UIAlertView * alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Login successful",nil) message:nil delegate:nil cancelButtonTitle:NSLocalizedString(@"OK",nil) otherButtonTitles:nil];
			alertView.delegate = self;
			[alertView show];
		}
	}];
}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];

	AppDelegate * appDelegate = (id)[[UIApplication sharedApplication] delegate];
	_username.text	= appDelegate.userName;
	_password.text	= appDelegate.userPassword;

	_verifyButton.enabled = _username.text.length && _password.text.length;
}

- (void)viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];

	if ( [self isMovingFromParentViewController] ) {
		AppDelegate * appDelegate = (id)[[UIApplication sharedApplication] delegate];
		appDelegate.userName		= [_username.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		appDelegate.userPassword	= [_password.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

		[KeyChain setString:appDelegate.userName forIdentifier:@"username"];
		[KeyChain setString:appDelegate.userPassword forIdentifier:@"password"];
	}
}

-(void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
	[cell fixConstraints];
}

#pragma mark - Table view delegate

@end
