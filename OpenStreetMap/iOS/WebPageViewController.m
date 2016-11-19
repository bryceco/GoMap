//
//  WebPageViewController.m
//  OSMiOS
//
//  Created by Bryce Cogswell on 12/26/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import "WebPageViewController.h"


@implementation WebPageViewController


- (void)viewDidLoad
{
    [super viewDidLoad];

	_webView.delegate = self;
	_activityIndicator.color = UIColor.blackColor;
}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];

	if ( self.title.length ) {
		self.navigationItem.title = self.title;
	}

	UIBarButtonItem * leftButton = [[UIBarButtonItem alloc] initWithTitle:@"Back" style:UIBarButtonItemStylePlain target:self action:@selector(backButton:)];
	self.navigationItem.leftBarButtonItems = @[ leftButton ];

	if ( self.url ) {
		NSString * escape = [self.url stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
		NSURL * url = [NSURL URLWithString:escape];
		NSURLRequest * request = [NSURLRequest requestWithURL:url];
		[_webView loadRequest:request];
	}
}

- (void)viewDidDisappear:(BOOL)animated
{
	[super viewDidDisappear:animated];
	[_webView stopLoading];
}

- (void)webViewDidStartLoad:(UIWebView *)webView
{
	[_activityIndicator startAnimating];
}

- (void)webViewDidFinishLoad:(UIWebView *)webView
{
	[_activityIndicator stopAnimating];
}

- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error
{
	[_activityIndicator stopAnimating];
	UIAlertView * alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Error loading web page",nil) message:error.localizedDescription delegate:self cancelButtonTitle:NSLocalizedString(@"OK",nil) otherButtonTitles:nil];
	[alert show];
}

- (void)backButton:(id)sender
{
	if ( _webView.canGoBack ) {
		[_webView goBack];
	} else {
		[self cancel:sender];
	}
}

// Called when a button is clicked. The view will be automatically dismissed after this call returns
- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
	switch ( buttonIndex ) {
		case 0:
			if ( [MFMailComposeViewController canSendMail] ) {
				MFMailComposeViewController * mail = [[MFMailComposeViewController alloc] init];
				mail.mailComposeDelegate = self;
				[mail setSubject:self.title];
				[mail setMessageBody:self.url isHTML:NO];
				[self.navigationController presentViewController:mail animated:YES completion:nil];
			} else {
				UIAlertView * alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Cannot compose message",nil) message:NSLocalizedString(@"Mail delivery is not available on this device",nil) delegate:nil cancelButtonTitle:NSLocalizedString(@"OK",nil) otherButtonTitles:nil];
				[alert show];
			}
			break;
		case 1:
			{
				NSString * escape = [self.url stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
				NSURL * url = [NSURL URLWithString:escape];
				[[UIApplication sharedApplication] openURL:url];
			}
			break;
		default:
			break;
	}
}

- (void)mailComposeController:(MFMailComposeViewController*)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError*)error
{
	[self dismissViewControllerAnimated:YES completion:nil];
}


- (IBAction)doAction:(id)sender
{
	UIActionSheet * sheet = [[UIActionSheet alloc] initWithTitle:NSLocalizedString(@"Action",nil) delegate:self cancelButtonTitle:NSLocalizedString(@"Cancel",nil) destructiveButtonTitle:nil otherButtonTitles:NSLocalizedString(@"Mail",nil), NSLocalizedString(@"Open in Safari",nil), nil];
	[sheet showFromBarButtonItem:_actionButton animated:YES];
}

#pragma mark Generic page controls

- (IBAction)cancel:(id)sender
{
	[self.navigationController popViewControllerAnimated:YES];
// 	[self dismissViewControllerAnimated:YES completion:nil];
}

@end
