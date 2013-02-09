//
//  CousineViewController.m
//  OSMiOS
//
//  Created by Bryce Cogswell on 12/10/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import "iosapi.h"
#import "POICuisineViewController.h"
#import "POITabBarController.h"
#import "TagInfo.h"


@implementation POICuisineViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

	_styleArray = [[TagInfoDatabase sharedTagInfoDatabase] cuisineStyleValues];
	_ethnicArray= [[TagInfoDatabase sharedTagInfoDatabase] cuisineEthnicValues];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	switch ( section ) {
		case 0:
			return _styleArray.count;
		case 1:
			return _ethnicArray.count;
	}
    return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
	switch ( section ) {
		case 0:
			return @"Style";
		case 1:
			return @"Ethnicity";
	}
	return nil;
}


- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *CellIdentifier = @"Cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier forIndexPath:indexPath];
	NSArray * a = nil;
	switch ( indexPath.section ) {
		case 0:
			a = _styleArray;
			break;
		case 1:
			a = _ethnicArray;
			break;
	}
	NSString * rawtext = a[ indexPath.row ];
	NSString * text = [rawtext stringByReplacingOccurrencesOfString:@"_" withString:@" "];
	text = [text capitalizedString];
	cell.textLabel.text = text;

	POITabBarController * tabController = (id)self.tabBarController;
	BOOL selected = [[tabController.keyValueDict valueForKey:@"cuisine"] isEqualToString:rawtext];
	cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	NSString * value = nil;
	switch ( indexPath.section ) {
		case 0:
			value = _styleArray[indexPath.row];
			break;
		case 1:
			value = _ethnicArray[indexPath.row];
			break;
	}
	assert(value);
	POITabBarController * tab = (id)self.tabBarController;
	[tab.keyValueDict setObject:value forKey:@"cuisine"];

	[self.navigationController popViewControllerAnimated:YES];
}

@end
