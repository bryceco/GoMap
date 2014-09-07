//
//  CustomPresetListViewController.m
//  Go Map!!
//
//  Created by Bryce on 8/20/14.
//  Copyright (c) 2014 Bryce. All rights reserved.
//

#import "CommonTagList.h"
#import "CustomPresetController.h"
#import "CustomPresetListViewController.h"
#import "UITableViewCell+FixConstraints.h"


@implementation CustomPresetListViewController

- (void)viewDidLoad
{
	_customPresets = [CustomPresetList shared];

	[super viewDidLoad];

	self.navigationItem.rightBarButtonItem = self.editButtonItem;
}

- (void)viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];

	if ( [self isMovingFromParentViewController] ) {
		[_customPresets save];
	}
}

-(void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
	[cell fixConstraints];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
	// Fix bug on iPad where cell heights come back as -1:
	// CGFloat h = [super tableView:tableView heightForRowAtIndexPath:indexPath];
	return 44.0;
}

#pragma mark - Table view data source

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
	return NSLocalizedString(@"You can define your own custom presets here",nil);
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	if ( section != 0 )
		return 0;
	return _customPresets.count + 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	if ( indexPath.section != 0 )
		return nil;

	if ( indexPath.row < _customPresets.count ) {
		UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"backgroundCell" forIndexPath:indexPath];
		CustomPreset * preset = [_customPresets presetAtIndex:indexPath.row];
		cell.textLabel.text = preset.name;
		return cell;
	} else {
		UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"addNewCell" forIndexPath:indexPath];
		return cell;
	}
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
	if ( indexPath.section == 0 && indexPath.row < _customPresets.count )
		return YES;
	return NO;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
	if (editingStyle == UITableViewCellEditingStyleDelete) {
		// Delete the row from the data source
		[_customPresets removePresetAtIndex:indexPath.row];
		[tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
	} else if (editingStyle == UITableViewCellEditingStyleInsert) {
		// Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
	}
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)fromIndexPath toIndexPath:(NSIndexPath *)toIndexPath
{
	CustomPreset * preset = [_customPresets presetAtIndex:fromIndexPath.row];
	[_customPresets removePresetAtIndex:fromIndexPath.row];
	[_customPresets addPreset:preset atIndex:toIndexPath.row];
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath
{
	if ( indexPath.section == 0 && indexPath.row < _customPresets.count )
		return YES;
	return NO;
}


#pragma mark - Navigation

#if 0
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
}
#endif

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
	UITableViewController * controller = [segue destinationViewController];
	CustomPresetController * c = (id)controller;
	UITableViewCell * cell = sender;
	NSIndexPath * indexPath = [self.tableView indexPathForCell:cell];
	NSInteger row = indexPath.row;
	if ( row < _customPresets.count ) {
		// existing item is being edited
		c.customPreset = [_customPresets presetAtIndex:row];
	}

	c.completion = ^(CustomPreset * preset) {
		if ( row >= _customPresets.count ) {
			[_customPresets addPreset:preset atIndex:_customPresets.count];
		} else {
			[_customPresets removePresetAtIndex:row];
			[_customPresets addPreset:preset atIndex:row];
		}
		[self.tableView reloadData];
	};
}

@end
