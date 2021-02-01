//
//  GpxConfigureViewController.m
//  Go Map!!
//
//  Created by Bryce Cogswell on 10/6/15.
//  Copyright © 2015 Bryce Cogswell. All rights reserved.
//

#import "GpxConfigureViewController.h"


@implementation GpxConfigureViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	_pickerView.delegate = self;
}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];

	[_pickerView selectRow:_expirationValue.integerValue inComponent:0 animated:NO];
}

- (NSString *)pickerView:(UIPickerView *)pickerView titleForRow:(NSInteger)row forComponent:(NSInteger)component
{
	if ( row == 0 )
		return NSLocalizedString(@"Never",@"Never delete old GPX tracks");
	if ( row == 1 )
		return NSLocalizedString(@"1 Day",@"1 day singular");
	return [NSString stringWithFormat:NSLocalizedString(@"%ld Days",@"Plural number of days"),(long)row];
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
