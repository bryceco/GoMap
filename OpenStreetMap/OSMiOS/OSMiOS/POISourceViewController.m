//
//  POISourceViewController.m
//  OSMiOS
//
//  Created by Bryce Cogswell on 12/10/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import "POISourceViewController.h"
#import "POITabBarController.h"

@implementation POISourceViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

	_sourceArray = @[
		@"survey",
		@"local_knowledge",
		@"Bing",
		@"Yahoo",
	];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return _sourceArray.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *CellIdentifier = @"Cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier forIndexPath:indexPath];

	NSString * rawtext = _sourceArray[ indexPath.row ];
	NSString * text = [rawtext stringByReplacingOccurrencesOfString:@"_" withString:@" "];
	text = [text capitalizedString];
	cell.textLabel.text = text;

	POITabBarController * tabController = (id)self.tabBarController;
	BOOL selected = [[tabController.keyValueDict valueForKey:@"source"] isEqualToString:rawtext];
	cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;

    return cell;
}

#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	NSString * value = [_sourceArray objectAtIndex:indexPath.row];
	POITabBarController * tab = (id)self.tabBarController;
	[tab.keyValueDict setObject:value forKey:@"source"];

	[self.navigationController popViewControllerAnimated:YES];
}

@end
