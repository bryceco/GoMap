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

	AppDelegate * appDelegate = [[UIApplication sharedApplication] delegate];

	NSAttributedString * s = _textView.attributedText;
	NSMutableAttributedString * m = [s mutableCopy];
	NSString * s2 = m.string;
	NSRange range = [s2 rangeOfString:@"<version>"];
	if ( range.length ) {
		[m replaceCharactersInRange:range withString:appDelegate.appVersion];
		_textView.attributedText = m;
	}
}


- (IBAction)cancel:(id)sender
{
	[self dismissViewControllerAnimated:YES completion:nil];
}



@end
