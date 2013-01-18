//
//  WebPageViewController.h
//  OSMiOS
//
//  Created by Bryce Cogswell on 12/26/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <MessageUI/MessageUI.h>
#import <UIKit/UIKit.h>

@interface WebPageViewController : UIViewController <UIWebViewDelegate, UIActionSheetDelegate, MFMailComposeViewControllerDelegate>
{
	IBOutlet UIWebView					*	_webView;
	IBOutlet UIActivityIndicatorView	*	_activityIndicator;
	IBOutlet UIBarButtonItem			*	_actionButton;
}
@property (copy,nonatomic)	NSString * url;
@property (copy,nonatomic)	NSString * title;

- (IBAction)doAction:(id)sender;
@end
