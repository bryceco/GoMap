//
//  HelpViewController.m
//  Go Map!!
//
//  Created by Bryce Cogswell on 1/14/13.
//  Copyright (c) 2013 Bryce Cogswell. All rights reserved.
//

#import "AppDelegate.h"
#import "HelpViewController.h"


@implementation HelpViewController


- (void)viewDidLoad
{
    [super viewDidLoad];

	AppDelegate * appDelegate = [AppDelegate getAppDelegate];

	NSAttributedString * s = _textView.attributedText;
	NSMutableAttributedString * m = [s mutableCopy];
    
    if (@available(iOS 13.0, *)) {
        [m addAttribute:NSForegroundColorAttributeName
                  value:[UIColor labelColor]
                  range:NSMakeRange(0, s.length)];
    }
    
	NSString * s2 = m.string;
	NSRange range = [s2 rangeOfString:@"<version>"];
	if ( range.length ) {
		[m replaceCharactersInRange:range withString:appDelegate.appVersion];
		_textView.attributedText = m;
	}
}

- (void)viewDidLayoutSubviews
{
    [_textView setContentOffset:CGPointZero animated:NO];
}


- (IBAction)cancel:(id)sender
{
	[self dismissViewControllerAnimated:YES completion:nil];
}


@end
