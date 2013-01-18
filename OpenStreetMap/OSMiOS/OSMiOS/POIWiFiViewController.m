//
//  POIWiFiViewController.m
//  OSMiOS
//
//  Created by Bryce on 12/10/12.
//  Copyright (c) 2012 Bryce. All rights reserved.
//

#import "POITabBarController.h"
#import "POIWiFiViewController.h"



@implementation POIWiFiViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

	_wifiArray = @[
		@"free",
		@"yes",
		@"no",
	];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return _wifiArray.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *CellIdentifier = @"Cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier forIndexPath:indexPath];
    
	NSString * rawtext = _wifiArray[ indexPath.row ];
	NSString * text = [rawtext stringByReplacingOccurrencesOfString:@"_" withString:@" "];
	text = [text capitalizedString];
	cell.textLabel.text = text;

	POITabBarController * tabController = (id)self.tabBarController;
	BOOL selected = [[tabController.keyValueDict valueForKey:@"wifi"] isEqualToString:rawtext];
	cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;

    return cell;
}

#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	NSString * value = [_wifiArray objectAtIndex:indexPath.row];
	POITabBarController * tab = (id)self.tabBarController;
	[tab.keyValueDict setObject:value forKey:@"wifi"];

	[self.navigationController popViewControllerAnimated:YES];
}

@end
