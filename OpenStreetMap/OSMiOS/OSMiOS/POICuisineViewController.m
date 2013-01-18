//
//  CousineViewController.m
//  OSMiOS
//
//  Created by Bryce Cogswell on 12/10/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import "POICuisineViewController.h"
#import "POITabBarController.h"


@implementation POICuisineViewController

- (id)initWithStyle:(UITableViewStyle)style
{
    self = [super initWithStyle:style];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

	_styleArray = @[
		@"bagel",
		@"barbecue",
		@"bougatsa",
		@"burger",
		@"cake",
		@"chicken",
		@"coffee_shop",
		@"crepe",
		@"couscous",
		@"curry",
		@"doughnut",
		@"fish_and_chips",
		@"fried_food",
		@"friture",
		@"ice_cream",
		@"kebab",
		@"mediterranean",
		@"noodle",
		@"pasta",
		@"pie",
		@"pizza",
		@"regional",
		@"sandwich",
		@"sausage",
//		@"savory_pancakes",
		@"seafood",
		@"steak_house",
		@"sushi",
	];
	_ethnicArray = @[
		@"african",
		@"american",
		@"arab",
		@"argentinian",
		@"asian",
		@"balkan",
		@"basque",
		@"brazilian",
		@"chinese",
		@"croatian",
		@"czech",
		@"french",
		@"german",
		@"greek",
		@"indian",
		@"iranian",
		@"italian",
		@"japanese",
		@"korean",
		@"latin_american",
		@"lebanese",
		@"mexican",
		@"peruvian",
		@"portuguese",
		@"spanish",
		@"thai",
		@"turkish",
		@"vietnamese"
	];
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
