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
		return @"Language selection affects only Presets and only for those presets that are translated for iD. The main interface is still English.";
	}
	return nil;
}


- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	return _languages.languageCodes.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:indexPath];

	NSString * code = _languages.languageCodes[ indexPath.row ];

	// name in native language
	cell.textLabel.text = [_languages languageNameForCode:code];

	// name in current language
	cell.detailTextLabel.text = [_languages localLanguageNameForCode:code];

	// accessory checkmark
	cell.accessoryType = [code isEqualToString:_languages.preferredLanguageCode] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	NSString * code = _languages.languageCodes[ indexPath.row ];
	_languages.preferredLanguageCode = code;

	[self.tableView reloadData];

	[PresetsDatabase initialize];	// reset tags
	[[AppDelegate getAppDelegate].mapView refreshPushpinText];
}

@end
