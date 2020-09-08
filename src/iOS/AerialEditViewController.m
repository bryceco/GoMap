//
//  AerialEditViewController.m
//  Go Map!!
//
//  Created by Bryce Cogswell on 8/21/14.
//  Copyright (c) 2014 Bryce Cogswell. All rights reserved.
//

#import "AerialList.h"
#import "AerialEditViewController.h"

static NSString * TMS_PROJECTION_NAME = @"(TMS)";

@interface AerialEditViewController ()
@end

@implementation AerialEditViewController

- (void)viewDidLoad
{
	[super viewDidLoad];

	nameField.text = self.name;
	urlField.text = self.url;
	zoomField.text = [self.zoom stringValue];
	projectionField.text = self.projection;

	_picker = [UIPickerView new];
	_picker.delegate = self;

	[_picker reloadAllComponents];
	NSInteger row = self.projection.length == 0 ? 0 : [AerialService.supportedProjections indexOfObject:self.projection]+1;
	[_picker selectRow:row inComponent:0 animated:NO];

	projectionField.inputView = _picker;
}

-(BOOL)isBannedURL:(NSString *)url
{
	NSString * pattern = @".*\\.google(apis)?\\..*/(vt|kh)[\\?/].*([xyz]=.*){3}.*";
	NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:NULL];
	NSRange range   = [regex rangeOfFirstMatchInString:url options:0 range:NSMakeRange(0,url.length)];
	if ( range.location != NSNotFound )
		return YES;
	return NO;
}

-(IBAction)done:(id)sender
{
	// remove white space from subdomain list
	NSString * url = [urlField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	url = [url stringByReplacingOccurrencesOfString:@"%7B" withString:@"{"];
	url = [url stringByReplacingOccurrencesOfString:@"%7D" withString:@"}"];

	if ( [self isBannedURL:urlField.text] )
		return;

	NSString * identifier = url;

	NSString * projection = projectionField.text;
	if ( [projection isEqualToString:TMS_PROJECTION_NAME] ) {
		projection = nil;
	}

	AerialService * service = [AerialService aerialWithName:[nameField.text	stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
												 			identifier:identifier
																	url:url
																maxZoom:[zoomField.text integerValue]
																roundUp:YES
															  startDate:nil
																endDate:nil
																wmsProjection:projection
																polygon:NULL
											   				attribString:nil
												 			attribIcon:nil
												  			 attribUrl:nil];
	self.completion(service);

	[self.navigationController popViewControllerAnimated:YES];
}

-(IBAction)cancel:(id)sender
{
	[self.navigationController popViewControllerAnimated:YES];
}

-(IBAction)contentChanged:(id)sender
{
	BOOL allowed = NO;
	if ( nameField.text.length > 0 && urlField.text.length > 0 ) {
		if ( ![self isBannedURL:urlField.text] ) {
			allowed = YES;
		}
	}
	self.navigationItem.rightBarButtonItem.enabled = allowed;
}

- (NSInteger)numberOfComponentsInPickerView:(nonnull UIPickerView *)pickerView
{
	return 1;
}

- (NSInteger)pickerView:(nonnull UIPickerView *)pickerView numberOfRowsInComponent:(NSInteger)component
{
	return AerialService.supportedProjections.count + 1;
}

- (NSString *)pickerView:(UIPickerView *)pickerView titleForRow:(NSInteger)row forComponent:(NSInteger)component
{
	return row == 0 ? TMS_PROJECTION_NAME : AerialService.supportedProjections[row-1];
}

- (void)pickerView:(UIPickerView *)pickerView didSelectRow:(NSInteger)row inComponent:(NSInteger)component
{
	projectionField.text = row == 0 ? TMS_PROJECTION_NAME : AerialService.supportedProjections[row-1];
	[self contentChanged:projectionField];
}

@end
