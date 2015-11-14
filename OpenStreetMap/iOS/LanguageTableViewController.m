//
//  LanguageTableViewController.m
//  Go Map!!
//
//  Created by Bryce on 11/12/15.
//  Copyright © 2015 Bryce. All rights reserved.
//

#import "CommonTagList.h"
#import "LanguageTableViewController.h"



@implementation LanguageTableViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

	_supportedLanguages = [NSMutableArray new];
	NSString * path = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"presets/translations"];
	NSArray * languageFiles = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:path error:NULL];
	languageFiles = [languageFiles arrayByAddingObject:@"en.json"];

	for ( NSString * file in languageFiles ) {
		NSString * code = [file stringByReplacingOccurrencesOfString:@".json" withString:@""];
		NSLocale * locale =  [NSLocale localeWithLocaleIdentifier:code];
		NSString * name = [locale displayNameForKey:NSLocaleIdentifier value:code];
		NSString * name2 = [[NSLocale currentLocale] displayNameForKey:NSLocaleIdentifier value:code];

		[_supportedLanguages addObject:@[ code, name, name2 ]];
	}

	[_supportedLanguages sortUsingComparator:^NSComparisonResult(NSArray * obj1, NSArray * obj2) {
		NSString * s1 = obj1[1];
		NSString * s2 = obj2[1];
		return [s1 compare:s2 options:NSCaseInsensitiveSearch];
	}];
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
	return _supportedLanguages.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:indexPath];
	NSArray * item = _supportedLanguages[ indexPath.row ];

	// name in native language
	NSString * name = item[1];
	cell.textLabel.text = name;

	// name in current language
	cell.detailTextLabel.text = item[2];

	// accessory checkmark
	NSString * code = item[0];
	NSString * preferred = [[NSUserDefaults standardUserDefaults] objectForKey:@"preferredLanguage"];
	cell.accessoryType = [preferred isEqualToString:code] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	NSArray * item = _supportedLanguages[ indexPath.row ];
	NSString * code = item[0];
	[[NSUserDefaults standardUserDefaults] setObject:code forKey:@"preferredLanguage"];

	[self.tableView reloadData];

	[CommonTagList initialize];	// reset tags
}

@end
