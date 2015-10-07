//
//  GpxConfigureViewController.m
//  Go Map!!
//
//  Created by Bryce on 10/6/15.
//  Copyright © 2015 Bryce. All rights reserved.
//

#import "GpxConfigureViewController.h"


@implementation GpxConfigureViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	_pickerView.delegate = self;

	[_pickerView selectRow:_expirationValue.integerValue inComponent:0 animated:NO];
}

- (NSString *)pickerView:(UIPickerView *)pickerView titleForRow:(NSInteger)row forComponent:(NSInteger)component
{
	if ( row == 0 )
		return @"Never";
	if ( row == 1 )
		return @"1 Day";
	return [NSString stringWithFormat:@"%ld Days",row];
}

- (void)pickerView:(UIPickerView *)pickerView didSelectRow:(NSInteger)row inComponent:(NSInteger)component
{
	self.expirationValue = @(row);
}


// returns the number of 'columns' to display.
- (NSInteger)numberOfComponentsInPickerView:(UIPickerView *)pickerView
{
	return 1;
}

// returns the # of rows in each component..
- (NSInteger)pickerView:(UIPickerView *)pickerView numberOfRowsInComponent:(NSInteger)component
{
	return 100;
}

-(IBAction)cancel:(id)sender
{
	[self dismissViewControllerAnimated:YES completion:nil];
}
-(IBAction)done:(id)sender
{
	self.completion( self.expirationValue );
	[self dismissViewControllerAnimated:YES completion:nil];
}

@end
