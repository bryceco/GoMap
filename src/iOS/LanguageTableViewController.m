//
//  LanguageTableViewController.m
//  Go Map!!
//
//  Created by Bryce Cogswell on 11/12/15.
//  Copyright © 2015 Bryce Cogswell. All rights reserved.
//

#import "AppDelegate.h"
#import "MapView.h"
#import "LanguageTableViewController.h"
#import "PresetsDatabase.h"



@implementation LanguageTableViewController


- (void)viewDidLoad
{
    [super viewDidLoad];
	_languages = [PresetLanguages new];
	
	self.tableView.estimatedRowHeight = 44;
	self.tableView.rowHeight = UITableViewAutomaticDimension;
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
	if ( section == 0 ) {
		return NSLocalizedString(@"Language selection affects only Presets and only for those presets that are translated for iD. The main interface is still English.",nil);
	}
	return nil;
}


- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	return _languages.languageCodes.count+1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:indexPath];

	NSString * code = nil;

	if ( indexPath.row == 0 ) {

		// Default
		code = nil;

		// name in native language
		cell.textLabel.text = NSLocalizedString(@"Automatic", @"Automatic selection of presets languages");
		cell.detailTextLabel.text = nil;

	} else {

		code = _languages.languageCodes[ indexPath.row - 1 ];

		// name in native language
		cell.textLabel.text = [PresetLanguages languageNameForCode:code];

		// name in current language
		cell.detailTextLabel.text = [PresetLanguages localLanguageNameForCode:code];

	}

	// accessory checkmark
	cell.accessoryType = (_languages.preferredLanguageIsDefault ? indexPath.row == 0 : [code isEqualToString:_languages.preferredLanguageCode]) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	if ( indexPath.row == 0 ) {
		_languages.preferredLanguageCode = nil;
	} else {
		NSString * code = _languages.languageCodes[ indexPath.row - 1 ];
		_languages.preferredLanguageCode = code;
	}

	[self.tableView reloadData];

	[PresetsDatabase reload];	// reset tags
	[AppDelegate.shared.mapView refreshPushpinText];
}

@end
