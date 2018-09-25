//
//  CousineViewController.m
//  OSMiOS
//
//  Created by Bryce Cogswell on 12/10/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import "iosapi.h"
#import "CommonTagList.h"
#import "POIPresetViewController.h"
#import "POITabBarController.h"
#import "TagInfo.h"


@implementation POIPresetViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

	self.tableView.estimatedRowHeight 	= UITableViewAutomaticDimension;
	self.tableView.rowHeight 			= UITableViewAutomaticDimension;

#if 0
	_sectionValues	= [NSMutableArray new];
	_sectionNames	= [NSMutableArray new];

	for ( NSInteger i = 0; i < self.valueDefinitions.count; i++ ) {
		NSArray * valueList	= _valueDefinitions[i];
		if ( [valueList isKindOfClass:[NSString class]] ) {
			// expand using taginfo
			SEL selector = NSSelectorFromString((id)valueList);
			TagInfoDatabase * database = [TagInfoDatabase sharedTagInfoDatabase];
			if ( selector && [database respondsToSelector:selector]	) {
				IMP imp = [database methodForSelector:selector];
				NSArray * (*func)(id, SEL) = (void *)imp;
				valueList = func(database, selector);
			} else {
				valueList = @[];
			}
		} else {
			// should already be an array
			assert( [valueList isKindOfClass:[NSArray class]] );
		}
		[_sectionValues addObject:valueList];
		[_sectionNames addObject:sectionHeader];
	}
#endif
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	return _valueDefinitions.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
	return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	UITableViewCell *cell;
	CommonTagValue * preset = _valueDefinitions[ indexPath.row ];

	if ( preset.details )
		cell = [tableView dequeueReusableCellWithIdentifier:@"SubtitleCell" forIndexPath:indexPath];
	else
		cell = [tableView dequeueReusableCellWithIdentifier:@"BasicCell" forIndexPath:indexPath];

	if ( preset.name ) {
		cell.textLabel.text = preset.name;
		cell.detailTextLabel.text = preset.details;
	} else {
		NSString * text = [preset.tagValue stringByReplacingOccurrencesOfString:@"_" withString:@" "];
		text = [text capitalizedString];
		cell.textLabel.text = text;
		cell.detailTextLabel.text = nil;
	}

	POITabBarController * tabController = (id)self.tabBarController;
	BOOL selected = [[tabController.keyValueDict objectForKey:self.tag] isEqualToString:preset.tagValue];
	cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	CommonTagValue * preset = _valueDefinitions[ indexPath.row ];
	POITabBarController * tab = (id)self.tabBarController;
	[tab.keyValueDict setObject:preset.tagValue forKey:self.tag];

	[self.navigationController popViewControllerAnimated:YES];
}

@end
