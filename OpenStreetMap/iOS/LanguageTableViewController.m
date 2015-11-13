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
	for ( NSString * file in languageFiles ) {
		NSString * code = [file stringByReplacingOccurrencesOfString:@".json" withString:@""];
		NSLocale * locale =  [NSLocale localeWithLocaleIdentifier:code];
		NSString * name = [locale displayNameForKey:NSLocaleIdentifier value:code];

		[_supportedLanguages addObject:@[ code, name ]];
	}
	[_supportedLanguages addObject:@[ @"en", @"English" ]];

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

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	return _supportedLanguages.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:indexPath];
	NSArray * item = _supportedLanguages[ indexPath.row ];
	NSString * name = item[1];
	cell.textLabel.text = name;

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
