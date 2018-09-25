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

	// since we can't place WKWebView in the storyboard we have a UIView in its place
	// we put the WKWebView inside it
	WKWebViewConfiguration * webConfiguration = [WKWebViewConfiguration new];
	_webView = [[WKWebView alloc] initWithFrame:_webViewContainer.bounds configuration:webConfiguration];
	_webView.translatesAutoresizingMaskIntoConstraints = NO;
	[_webViewContainer insertSubview:_webView belowSubview:_activityIndicator];

	[_webView.topAnchor 	 constraintEqualToAnchor:_webViewContainer.topAnchor 		constant:0].active = YES;
	[_webView.bottomAnchor 	 constraintEqualToAnchor:_webViewContainer.bottomAnchor 	constant:0].active = YES;
	[_webView.leadingAnchor  constraintEqualToAnchor:_webViewContainer.leadingAnchor 	constant:0].active = YES;
	[_webView.trailingAnchor constraintEqualToAnchor:_webViewContainer.trailingAnchor 	constant:0].active = YES;

	_webView.navigationDelegate = self;

	_activityIndicator.color = UIColor.blackColor;

	if ( self.title.length ) {
		self.navigationItem.title = self.title;

		if ( _navBar.items.count > 0 ) {
			UINavigationItem * nav = self.navBar.items[0];
			nav.title = self.title;
		}
	}

	UIBarButtonItem * leftButton = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Back",nil) style:UIBarButtonItemStylePlain target:self action:@selector(backButton:)];
	self.navigationItem.leftBarButtonItem = leftButton;

	if ( self.url ) {
		NSString * escape = [self.url stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
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

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation
{
	[_activityIndicator startAnimating];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation
{
	[_activityIndicator stopAnimating];
}


- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(null_unspecified WKNavigation *)navigation withError:(NSError *)error
{
	// forward error to other handler
	[self webView:webView didFailNavigation:navigation withError:error];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error
{
	[_activityIndicator stopAnimating];
	
	UIAlertController * alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Error loading web page",nil)
																	message:error.localizedDescription
															 preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK",nil) style:UIAlertActionStyleCancel handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)backButton:(id)sender
{
	if ( _webView.canGoBack ) {
		[_webView goBack];
	} else {
		[self cancel:sender];
	}
}

- (void)mailComposeController:(MFMailComposeViewController*)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError*)error
{
	[self dismissViewControllerAnimated:YES completion:nil];
}


- (IBAction)doAction:(id)sender
{
	UIAlertController * sheet = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Action",nil) message:nil preferredStyle:UIAlertControllerStyleActionSheet];
	[sheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel",nil) style:UIAlertActionStyleCancel handler:nil]];
	[sheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Mail",nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
		if ( [MFMailComposeViewController canSendMail] ) {
			MFMailComposeViewController * mail = [[MFMailComposeViewController alloc] init];
			mail.mailComposeDelegate = self;
			[mail setSubject:self.title];
			[mail setMessageBody:self.url isHTML:NO];
			[self.navigationController presentViewController:mail animated:YES completion:nil];
		} else {
			UIAlertController * alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Cannot compose message",nil)
																			message:NSLocalizedString(@"Mail delivery is not available on this device",nil)
																	 preferredStyle:UIAlertControllerStyleAlert];
			[sheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK",nil) style:UIAlertActionStyleCancel handler:nil]];
			[self.navigationController presentViewController:alert animated:YES completion:nil];
		}
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Open in Safari",nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
		NSString * escape = [self.url stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
		NSURL * url = [NSURL URLWithString:escape];
		[[UIApplication sharedApplication] openURL:url];
	}]];
	[self presentViewController:sheet animated:YES completion:nil];
	// set location
	sheet.popoverPresentationController.barButtonItem = sender;
}

#pragma mark Generic page controls

- (IBAction)cancel:(id)sender
{
	if ( self.navigationController ) {
		[self.navigationController popViewControllerAnimated:YES];
	} else {
		[self dismissViewControllerAnimated:YES completion:nil];
	}
}

@end
