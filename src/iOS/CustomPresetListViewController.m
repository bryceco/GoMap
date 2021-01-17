//
//  CustomPresetListViewController.m
//  Go Map!!
//
//  Created by Bryce Cogswell on 8/20/14.
//  Copyright (c) 2014 Bryce Cogswell. All rights reserved.
//

#import "CustomPresetController.h"
#import "CustomPresetListViewController.h"


@implementation CustomPresetListViewController

- (void)viewDidLoad
{
	_customPresets = PresetKeyUserDefinedList.shared;

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



#pragma mark - Table view data source

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
	return NSLocalizedString(@"You can define your own custom presets here",@"POI editor presets");
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	if ( section != 0 )
		return 0;
	return _customPresets.list.count + 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	assert( indexPath.section == 0 );
	if ( indexPath.row < _customPresets.list.count ) {
		UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"backgroundCell" forIndexPath:indexPath];
		PresetKeyUserDefined * preset = _customPresets.list[indexPath.row];
		cell.textLabel.text = preset.name;
		return cell;
	} else {
		UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"addNewCell" forIndexPath:indexPath];
		return cell;
	}
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
	if ( indexPath.section == 0 && indexPath.row < _customPresets.list.count )
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
	PresetKeyUserDefined * preset = _customPresets.list[fromIndexPath.row];
	[_customPresets removePresetAtIndex:fromIndexPath.row];
	[_customPresets addPreset:preset atIndex:toIndexPath.row];
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath
{
	if ( indexPath.section == 0 && indexPath.row < _customPresets.list.count )
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
	if ( row < _customPresets.list.count ) {
		// existing item is being edited
		c.customPreset = _customPresets.list[row];
	}

	c.completion = ^(PresetKeyUserDefined * preset) {
		if ( row >= _customPresets.list.count ) {
			[_customPresets addPreset:preset atIndex:_customPresets.list.count];
		} else {
			[_customPresets removePresetAtIndex:row];
			[_customPresets addPreset:preset atIndex:row];
		}
		[self.tableView reloadData];
	};
}

@end
