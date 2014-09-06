//
//  CustomPresetController.h
//  Go Map!!
//
//  Created by Bryce on 8/21/14.
//  Copyright (c) 2014 Bryce. All rights reserved.
//

#import "CommonTagList.h"
#import "CustomPresetController.h"
#import "POICommonTagsViewController.h"
#import "UITableViewCell+FixConstraints.h"

@interface CustomPresetController ()
@end

@implementation CustomPresetController

- (void)viewDidLoad
{
	[super viewDidLoad];

	nameField.text = self.commonTag.name;
	tagField.text = _commonTag.tagKey;
	placeholderField.text = _commonTag.placeholder;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
	// Fix bug on iPad where cell heights come back as -1:
	// CGFloat h = [super tableView:tableView heightForRowAtIndexPath:indexPath];
	return 44.0;
}

-(IBAction)done:(id)sender
{
	// remove white space from subdomain list
	NSString * name = [nameField.text	stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	NSString * tag  = [tagField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	NSString * placeholder  = [placeholderField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	NSArray * presets = nil;

	CommonTag * commonTag = [CommonTag tagWithName:name tagKey:tag placeholder:placeholder presets:presets];
	self.completion(commonTag);
	[self.navigationController popViewControllerAnimated:YES];
}

-(IBAction)cancel:(id)sender
{
	[self.navigationController popViewControllerAnimated:YES];
}

-(void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
	[cell fixConstraints];
}

-(IBAction)contentChanged:(id)sender
{
	if ( nameField.text.length > 0 && tagField.text.length > 0 ) {
		self.navigationItem.rightBarButtonItem.enabled = YES;
	} else {
		self.navigationItem.rightBarButtonItem.enabled = NO;
	}
}


@end
