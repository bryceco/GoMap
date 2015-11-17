//
//  HtmlAlertViewController.m
//  Go Map!!
//
//  Created by Bryce on 11/11/15.
//  Copyright © 2015 Bryce. All rights reserved.
//

#import "HtmlAlertViewController.h"

@implementation HtmlAlertViewController

@synthesize htmlText = _htmlText;

- (void)viewDidLoad
{
	[super viewDidLoad];

	self.view.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.5];
	self.view.opaque = NO;
	self.popup.layer.cornerRadius = 15;
	self.view.layer.zPosition = 100000.0;

	// adjust font of bottons
	UIFont * buttonFont = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
	NSDictionary * attributes = @{ NSFontAttributeName : buttonFont };
	[_buttonBar setTitleTextAttributes:attributes forState:UIControlStateNormal];

	[self.buttonBar removeAllSegments];
	_callbackList = [NSMutableArray new];

	[self.buttonBar addTarget:self action:@selector(indexChanged:) forControlEvents:UIControlEventValueChanged];

	self.text.dataDetectorTypes =  UIDataDetectorTypeLink;
	self.text.delegate = self;
}

-(NSString *)htmlText
{
	return _htmlText;
}

-(void)setHtmlText:(NSString *)text
{
	_htmlText = text;

	NSRange r1 = [text rangeOfString:@"<a "];
	if ( r1.length > 0 ) {
		NSRange r2 = [text rangeOfString:@"\">"];
		if ( r2.length > 0 ) {
			NSRange r3 = [text rangeOfString:@"</a>"];
			if ( r3.length > 0 ) {
				text = [text stringByReplacingCharactersInRange:NSMakeRange(r1.location,r2.location+r2.length-r1.location) withString:@""];
				text = [text stringByReplacingOccurrencesOfString:@"</a>" withString:@""];
			}
		}
	}
	text = [text stringByReplacingOccurrencesOfString:@"&quot;" withString:@"\""];
	text = [text stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];

	self.text.text = text;

	// resize
	CGRect frame = _text.frame;
	frame.size.height = _text.contentSize.height;
	_text.frame = frame;
}

-(void)addButton:(NSString *)label callback:(void(^)(void))callback
{
	[self.buttonBar insertSegmentWithTitle:label atIndex:_callbackList.count animated:NO];
	[_callbackList addObject:callback];
}

-(IBAction)indexChanged:(UISegmentedControl *)sender
{
	NSInteger index = _buttonBar.selectedSegmentIndex;
	if ( index < _callbackList.count ) {
		void(^callback)(void) = _callbackList[ index ];
		callback();
	}
}


- (BOOL)textView:(UITextView *)textView shouldInteractWithURL:(NSURL *)URL inRange:(NSRange)characterRange
{
	return YES;
}

- (BOOL)textView:(UITextView *)textView shouldInteractWithTextAttachment:(NSTextAttachment *)textAttachment inRange:(NSRange)characterRange
{
	return YES;
}



@end
